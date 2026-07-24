import { randomBytes, randomUUID } from "node:crypto";
import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import cors from "@fastify/cors";
import {
  analyticsEventSchema,
  completeUploadSchema,
  createAiJobSchema,
  createShareSchema,
  createUploadSchema,
  magicLinkRequestSchema,
  magicLinkVerifySchema,
  verifyShareSchema
} from "@glideframe/contracts";
import Fastify, { type FastifyRequest } from "fastify";
import { z } from "zod";
import type { AiJobQueue } from "./ai/queue.js";
import { InlineAiJobQueue } from "./ai/queue.js";
import type { AppConfig } from "./config.js";
import type { AiJob, Share, Store, Upload } from "./domain.js";
import { createMailer, type MagicLinkMailer } from "./email.js";
import { MemoryStore } from "./memory-store.js";
import type { ObjectStore } from "./object-store.js";
import { LocalObjectStore } from "./object-store.js";
import { createAccessToken, createShareToken, hashPassword, sha256, verifyPaddleSignature, verifyPassword, verifyToken } from "./security.js";

export type ServerDependencies = {
  config: AppConfig;
  store?: Store;
  objects?: ObjectStore;
  aiQueue?: AiJobQueue;
  mailer?: MagicLinkMailer;
  now?: () => Date;
};

type RawRequest = FastifyRequest & { rawBody?: Buffer };

export async function createServer(dependencies: ServerDependencies) {
  const { config } = dependencies;
  const store = dependencies.store ?? new MemoryStore();
  const objects = dependencies.objects ?? new LocalObjectStore(config.STORAGE_ROOT, config.PUBLIC_API_URL);
  const aiQueue = dependencies.aiQueue ?? new InlineAiJobQueue();
  const now = dependencies.now ?? (() => new Date());
  const app = Fastify({ logger: config.NODE_ENV !== "test", bodyLimit: 16 * 1024 * 1024 });
  const mailer = dependencies.mailer ?? createMailer(config, (fields, message) => app.log.info(fields, message));

  app.addContentTypeParser("application/json", { parseAs: "buffer" }, (request, body, done) => {
    try {
      (request as RawRequest).rawBody = body as Buffer;
      done(null, JSON.parse((body as Buffer).toString("utf8")));
    } catch (error) { done(error as Error, undefined); }
  });
  app.addContentTypeParser("application/octet-stream", { parseAs: "buffer" }, (_request, body, done) => done(null, body));
  await app.register(cors, { origin: config.WEB_URL, methods: ["GET", "POST", "PUT", "DELETE"] });

  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof z.ZodError) return reply.code(400).send({ error: "invalid_request", details: error.issues });
    const status = typeof error === "object" && error !== null && "statusCode" in error && typeof error.statusCode === "number" ? error.statusCode : 500;
    if (status >= 500) app.log.error(error);
    const message = error instanceof Error ? error.message : "request_failed";
    return reply.code(status).send({ error: status === 500 ? "internal_error" : message });
  });

  app.get("/health", async () => ({ status: "ok", version: "0.1.0" }));

  app.post("/v1/auth/magic-link", async (request, reply) => {
    const input = magicLinkRequestSchema.parse(request.body);
    const token = randomBytes(32).toString("base64url");
    await store.createMagicLink(input.email, sha256(token), new Date(now().getTime() + 15 * 60_000).toISOString());
    await mailer.send(input.email, `${config.WEB_URL}/auth/verify?token=${token}`);
    return reply.code(202).send({ accepted: true, ...(config.NODE_ENV !== "production" ? { previewToken: token } : {}) });
  });

  app.post("/v1/auth/verify", async (request, reply) => {
    const input = magicLinkVerifySchema.parse(request.body);
    const user = await store.consumeMagicLink(sha256(input.token), now().toISOString());
    if (!user) return reply.code(401).send({ error: "invalid_or_expired_link" });
    return { accessToken: await createAccessToken(config.JWT_SECRET, user.id, user.email), expiresIn: 900, user: { id: user.id, email: user.email } };
  });

  app.get("/v1/entitlements", async (request) => {
    const userId = await requireUser(request, config.JWT_SECRET);
    return store.getEntitlement(userId);
  });

  app.get("/v1/billing/plans", async () => ({
    currency: "USD",
    plans: [
      { id: "pro-monthly", amount: 15, interval: "month", aiMinutes: 180, storageGB: 50, devices: 3 },
      { id: "pro-annual", amount: 144, interval: "year", aiMinutes: 180, storageGB: 50, devices: 3 }
    ]
  }));

  app.post("/v1/billing/checkout", async (request, reply) => {
    const userId = await requireUser(request, config.JWT_SECRET);
    const input = z.object({ price: z.enum(["monthly", "annual"]) }).parse(request.body);
    const priceId = input.price === "monthly" ? config.PADDLE_PRO_MONTHLY_PRICE_ID : config.PADDLE_PRO_ANNUAL_PRICE_ID;
    if (!config.PADDLE_API_KEY || !priceId) return reply.code(503).send({ error: "billing_not_configured" });
    const baseURL = config.PADDLE_ENV === "sandbox" ? "https://sandbox-api.paddle.com" : "https://api.paddle.com";
    const response = await fetch(`${baseURL}/transactions`, {
      method: "POST",
      headers: { authorization: `Bearer ${config.PADDLE_API_KEY}`, "content-type": "application/json" },
      body: JSON.stringify({ items: [{ price_id: priceId, quantity: 1 }], custom_data: { user_id: userId }, checkout: { url: `${config.WEB_URL}/dashboard?billing=complete` } })
    });
    if (!response.ok) { app.log.error({ status: response.status }, "Paddle checkout creation failed"); return reply.code(502).send({ error: "checkout_unavailable" }); }
    const transaction = z.object({ data: z.object({ checkout: z.object({ url: z.string().url() }) }) }).parse(await response.json());
    return { checkoutUrl: transaction.data.checkout.url };
  });

  app.post("/v1/uploads", async (request, reply) => {
    const userId = await requireUser(request, config.JWT_SECRET);
    const input = createUploadSchema.parse(request.body);
    const entitlement = await store.getEntitlement(userId);
    if (entitlement.storageBytesUsed + input.sizeBytes > entitlement.storageBytes) return reply.code(402).send({ error: "storage_quota_exceeded" });
    const id = randomUUID();
    const storageKey = `users/${userId}/${id}.mp4`;
    const initiated = await objects.initiate(storageKey, input.contentType, input.partCount);
    const upload: Upload = { id, userId, ...input, storageKey, storageUploadId: initiated.uploadId, status: "uploading", createdAt: now().toISOString() };
    await store.createUpload(upload);
    return reply.code(201).send({ id, partUrls: initiated.partUrls, expiresIn: 900 });
  });

  app.put<{ Params: { uploadId: string; partNumber: string } }>("/v1/uploads/local/:uploadId/parts/:partNumber", async (request, reply) => {
    if (!objects.putLocalPart || !Buffer.isBuffer(request.body)) return reply.code(404).send({ error: "not_found" });
    const partNumber = Number(request.params.partNumber);
    if (!Number.isInteger(partNumber) || partNumber < 1) return reply.code(400).send({ error: "invalid_part" });
    const etag = await objects.putLocalPart(request.params.uploadId, partNumber, request.body as Buffer);
    return reply.header("etag", etag).code(204).send();
  });

  app.post<{ Params: { id: string } }>("/v1/uploads/:id/complete", async (request, reply) => {
    const userId = await requireUser(request, config.JWT_SECRET);
    const input = completeUploadSchema.parse(request.body);
    const upload = await store.getUpload(request.params.id);
    if (!upload || upload.userId !== userId) return reply.code(404).send({ error: "upload_not_found" });
    if (new Set(input.parts.map((part) => part.partNumber)).size !== upload.partCount) return reply.code(400).send({ error: "incomplete_parts" });
    await objects.complete(upload.storageKey, upload.storageUploadId, input.parts);
    await store.completeUpload(upload.id);
    return { id: upload.id, status: "completed" };
  });

  app.post("/v1/shares", async (request, reply) => {
    const userId = await requireUser(request, config.JWT_SECRET);
    const input = createShareSchema.parse(request.body);
    const [upload, entitlement] = await Promise.all([store.getUpload(input.uploadId), store.getEntitlement(userId)]);
    if (!upload || upload.userId !== userId || upload.status !== "completed") return reply.code(404).send({ error: "upload_not_found" });
    if (entitlement.sharesUsed >= entitlement.monthlyShares) return reply.code(402).send({ error: "share_quota_exceeded" });
    if (input.expiresAt && input.expiresAt <= now().toISOString()) return reply.code(400).send({ error: "expiry_must_be_future" });
    const share: Share = {
      id: randomUUID(), token: randomBytes(18).toString("base64url"), userId, uploadId: upload.id, title: input.title,
      ...(input.password ? { passwordHash: await hashPassword(input.password) } : {}),
      ...(input.expiresAt ? { expiresAt: input.expiresAt } : {}), createdAt: now().toISOString()
    };
    await store.createShare(share);
    return reply.code(201).send({ id: share.id, token: share.token, url: `${config.WEB_URL}/watch/${share.token}` });
  });

  app.get("/v1/shares", async (request) => {
    const userId = await requireUser(request, config.JWT_SECRET);
    const shares = await store.listShares(userId);
    return Promise.all(shares.map(async (share) => ({
      id: share.id, token: share.token, title: share.title, url: `${config.WEB_URL}/watch/${share.token}`,
      protected: Boolean(share.passwordHash), expiresAt: share.expiresAt ?? null, revokedAt: share.revokedAt ?? null,
      createdAt: share.createdAt, analytics: await store.getAnalytics(share.id)
    })));
  });

  app.get<{ Params: { token: string } }>("/v1/shares/public/:token", async (request, reply) => {
    const share = await activeShare(store, request.params.token, now(), reply);
    if (!share) return;
    if (share.passwordHash && !(await hasShareAccess(request, config.JWT_SECRET, share.id))) {
      return { id: share.id, title: share.title, requiresPassword: true, expiresAt: share.expiresAt ?? null };
    }
    const upload = await store.getUpload(share.uploadId);
    if (!upload) return reply.code(404).send({ error: "media_not_found" });
    return { id: share.id, title: share.title, requiresPassword: false, playbackUrl: await objects.playbackUrl(upload.storageKey), expiresAt: share.expiresAt ?? null };
  });

  app.post<{ Params: { token: string } }>("/v1/shares/public/:token/verify", async (request, reply) => {
    const input = verifyShareSchema.parse(request.body);
    const share = await activeShare(store, request.params.token, now(), reply);
    if (!share) return;
    if (!share.passwordHash || !(await verifyPassword(input.password, share.passwordHash))) return reply.code(401).send({ error: "invalid_password" });
    return { accessToken: await createShareToken(config.JWT_SECRET, share.id), expiresIn: 3600 };
  });

  app.delete<{ Params: { id: string } }>("/v1/shares/:id", async (request, reply) => {
    const userId = await requireUser(request, config.JWT_SECRET);
    const revoked = await store.revokeShare(request.params.id, userId, now().toISOString());
    return revoked ? reply.code(204).send() : reply.code(404).send({ error: "share_not_found" });
  });

  app.post<{ Params: { token: string } }>("/v1/analytics/shares/:token/events", async (request, reply) => {
    const input = analyticsEventSchema.parse(request.body);
    const share = await activeShare(store, request.params.token, now(), reply);
    if (!share) return;
    await store.addAnalytics(share.id, input);
    return reply.code(202).send({ accepted: true });
  });

  app.get<{ Params: { id: string } }>("/v1/analytics/shares/:id", async (request, reply) => {
    const userId = await requireUser(request, config.JWT_SECRET);
    const share = await store.getShare(request.params.id);
    if (!share || share.userId !== userId) return reply.code(404).send({ error: "share_not_found" });
    return store.getAnalytics(share.id);
  });

  app.post("/v1/ai-jobs", async (request, reply) => {
    const userId = await requireUser(request, config.JWT_SECRET);
    const input = createAiJobSchema.parse(request.body);
    const [upload, entitlement] = await Promise.all([store.getUpload(input.uploadId), store.getEntitlement(userId)]);
    if (!upload || upload.userId !== userId || upload.status !== "completed") return reply.code(404).send({ error: "upload_not_found" });
    if (entitlement.aiMinutesUsed + input.mediaMinutes > entitlement.monthlyAiMinutes) return reply.code(402).send({ error: "ai_quota_exceeded" });
    const timestamp = now().toISOString();
    const job: AiJob = { id: randomUUID(), userId, ...input, status: "queued", createdAt: timestamp, updatedAt: timestamp };
    await store.createAiJob(job);
    await aiQueue.enqueue(job);
    return reply.code(202).send({ id: job.id, status: job.status });
  });

  app.get<{ Params: { id: string } }>("/v1/ai-jobs/:id", async (request, reply) => {
    const userId = await requireUser(request, config.JWT_SECRET);
    const job = await store.getAiJob(request.params.id);
    if (!job || job.userId !== userId) return reply.code(404).send({ error: "job_not_found" });
    return job;
  });

  app.post("/v1/billing/paddle/webhook", async (request, reply) => {
    if (!config.PADDLE_WEBHOOK_SECRET) return reply.code(503).send({ error: "billing_not_configured" });
    const signature = request.headers["paddle-signature"];
    const rawBody = (request as RawRequest).rawBody;
    if (typeof signature !== "string" || !rawBody || !verifyPaddleSignature(rawBody, signature, config.PADDLE_WEBHOOK_SECRET)) {
      return reply.code(401).send({ error: "invalid_signature" });
    }
    const event = paddleEventSchema.parse(request.body);
    if (!(await store.markWebhookProcessed(event.event_id))) return reply.code(204).send();
    const status = mapPaddleStatus(event.data.status);
    await store.setPlan(event.data.custom_data.user_id, "pro", status, event.data.next_billed_at ?? null);
    return reply.code(204).send();
  });

  app.get<{ Params: { key: string } }>("/v1/media/:key", async (request, reply) => {
    if (!objects.localPath) return reply.code(404).send({ error: "not_found" });
    try {
      const file = objects.localPath(request.params.key);
      const metadata = await stat(file);
      const range = request.headers.range?.match(/^bytes=(\d+)-(\d*)$/);
      if (range) {
        const start = Number(range[1]);
        const end = range[2] ? Math.min(Number(range[2]), metadata.size - 1) : metadata.size - 1;
        if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start > end || start >= metadata.size) {
          return reply.header("content-range", `bytes */${metadata.size}`).code(416).send();
        }
        return reply
          .code(206)
          .headers({ "accept-ranges": "bytes", "content-range": `bytes ${start}-${end}/${metadata.size}`, "content-length": end - start + 1, "content-type": "video/mp4" })
          .send(createReadStream(file, { start, end }));
      }
      return reply.headers({ "accept-ranges": "bytes", "content-type": "video/mp4", "content-length": metadata.size }).send(createReadStream(file));
    } catch { return reply.code(404).send({ error: "not_found" }); }
  });

  app.addHook("onClose", async () => aiQueue.close());
  return app;
}

async function requireUser(request: FastifyRequest, secret: string): Promise<string> {
  const token = bearerToken(request.headers.authorization);
  if (!token) throw httpError(401, "authentication_required");
  try {
    const payload = await verifyToken(secret, token);
    if (payload.type !== "access" || typeof payload.sub !== "string") throw new Error();
    return payload.sub;
  } catch { throw httpError(401, "invalid_access_token"); }
}

async function hasShareAccess(request: FastifyRequest, secret: string, shareId: string): Promise<boolean> {
  const token = bearerToken(request.headers.authorization);
  if (!token) return false;
  try { const payload = await verifyToken(secret, token); return payload.type === "share" && payload.shareId === shareId; }
  catch { return false; }
}

function bearerToken(header?: string): string | undefined { return header?.startsWith("Bearer ") ? header.slice(7) : undefined; }
function httpError(statusCode: number, message: string): Error & { statusCode: number } { return Object.assign(new Error(message), { statusCode }); }

async function activeShare(store: Store, token: string, now: Date, reply: { code: (status: number) => { send: (body: unknown) => unknown } }): Promise<Share | null> {
  const share = await store.getShareByToken(token);
  if (!share || share.revokedAt || (share.expiresAt && share.expiresAt <= now.toISOString())) {
    reply.code(404).send({ error: "share_not_found" });
    return null;
  }
  return share;
}

const paddleEventSchema = z.object({
  event_id: z.string(),
  event_type: z.string(),
  data: z.object({ status: z.string(), next_billed_at: z.string().datetime().nullable().optional(), custom_data: z.object({ user_id: z.string().uuid() }) })
});
function mapPaddleStatus(status: string): "active" | "trialing" | "past_due" | "canceled" {
  if (status === "trialing") return "trialing";
  if (status === "past_due" || status === "paused") return "past_due";
  if (status === "canceled") return "canceled";
  return "active";
}
