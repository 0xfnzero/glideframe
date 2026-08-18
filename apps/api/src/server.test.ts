import { randomUUID } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { AppConfig } from "./config.js";
import { MemoryStore } from "./memory-store.js";
import { LocalObjectStore } from "./object-store.js";
import { createServer } from "./server.js";

describe("community API flow", () => {
  let root: string;
  let store: MemoryStore;
  let app: Awaited<ReturnType<typeof createServer>>;
  const config: AppConfig = {
    NODE_ENV: "test", HOST: "127.0.0.1", PORT: 4100,
    PUBLIC_API_URL: "http://127.0.0.1:4100", WEB_URL: "http://127.0.0.1:3000",
    JWT_SECRET: "test-secret-with-at-least-32-characters", STORAGE_DRIVER: "local",
    STORAGE_ROOT: ".data/test", S3_REGION: "us-east-1"
  };

  beforeEach(async () => {
    root = await mkdtemp(path.join(tmpdir(), "glideframe-api-"));
    store = new MemoryStore();
    app = await createServer({ config: { ...config, STORAGE_ROOT: root }, store, objects: new LocalObjectStore(root, config.PUBLIC_API_URL) });
  });

  afterEach(async () => { await app.close(); await rm(root, { recursive: true, force: true }); });

  it("authenticates, uploads, shares and records viewing analytics", async () => {
    const { accessToken } = await authenticate("creator@example.com");
    const auth = { authorization: `Bearer ${accessToken}` };
    const entitlement = await app.inject({ method: "GET", url: "/v1/entitlements", headers: auth });
    expect(entitlement.statusCode).toBe(200);
    expect(entitlement.json().plan).toBe("community");

    const created = await app.inject({
      method: "POST", url: "/v1/uploads", headers: auth,
      payload: { filename: "demo.mp4", contentType: "video/mp4", sizeBytes: 9, partCount: 1 }
    });
    expect(created.statusCode).toBe(201);
    const upload = created.json();
    const partPath = new URL(upload.partUrls[0]).pathname;
    const part = await app.inject({ method: "PUT", url: partPath, headers: { "content-type": "application/octet-stream" }, payload: Buffer.from("demo-data") });
    expect(part.statusCode).toBe(204);

    const completed = await app.inject({
      method: "POST", url: `/v1/uploads/${upload.id}/complete`, headers: auth,
      payload: { parts: [{ partNumber: 1, etag: "local-9" }] }
    });
    expect(completed.statusCode).toBe(200);

    const shared = await app.inject({ method: "POST", url: "/v1/shares", headers: auth, payload: { uploadId: upload.id, title: "Launch demo" } });
    expect(shared.statusCode).toBe(201);
    const share = shared.json();
    const publicShare = await app.inject({ method: "GET", url: `/v1/shares/public/${share.token}` });
    expect(publicShare.json().playbackUrl).toContain("/v1/media/");
    const mediaPath = new URL(publicShare.json().playbackUrl).pathname;
    const range = await app.inject({ method: "GET", url: mediaPath, headers: { range: "bytes=0-3" } });
    expect(range.statusCode).toBe(206);
    expect(range.headers["content-range"]).toBe("bytes 0-3/9");
    expect(range.rawPayload.byteLength).toBe(4);
    const localStore = new LocalObjectStore(root, config.PUBLIC_API_URL);
    expect(() => localStore.localPath("../outside.mp4")).toThrow("Invalid object key");

    const sessionId = randomUUID();
    await app.inject({ method: "POST", url: `/v1/analytics/shares/${share.token}/events`, payload: { event: "play", sessionId, progress: 0, occurredAt: new Date().toISOString() } });
    await app.inject({ method: "POST", url: `/v1/analytics/shares/${share.token}/events`, payload: { event: "complete", sessionId, progress: 1, occurredAt: new Date().toISOString() } });
    const analytics = await app.inject({ method: "GET", url: `/v1/analytics/shares/${share.id}`, headers: auth });
    expect(analytics.json()).toEqual({ views: 1, uniqueViewers: 1, completionRate: 1 });
  });

  it("enforces password protection and community AI quota", async () => {
    const { accessToken } = await authenticate("creator@example.com");
    const auth = { authorization: `Bearer ${accessToken}` };
    const uploadId = await completedUpload(auth);
    const shared = await app.inject({ method: "POST", url: "/v1/shares", headers: auth, payload: { uploadId, title: "Private demo", password: "correct-horse" } });
    const share = shared.json();
    const blocked = await app.inject({ method: "GET", url: `/v1/shares/public/${share.token}` });
    expect(blocked.json().requiresPassword).toBe(true);
    const wrong = await app.inject({ method: "POST", url: `/v1/shares/public/${share.token}/verify`, payload: { password: "wrong-password" } });
    expect(wrong.statusCode).toBe(401);
    const verified = await app.inject({ method: "POST", url: `/v1/shares/public/${share.token}/verify`, payload: { password: "correct-horse" } });
    expect(verified.statusCode).toBe(200);

    const deniedJob = await app.inject({ method: "POST", url: "/v1/ai-jobs", headers: auth, payload: { uploadId, operation: "transcribe", sourceLanguage: "auto", mediaMinutes: 4 } });
    expect(deniedJob.statusCode).toBe(402);
  });

  async function authenticate(email: string): Promise<{ accessToken: string; userId: string }> {
    const requested = await app.inject({ method: "POST", url: "/v1/auth/magic-link", payload: { email } });
    const token = requested.json().previewToken;
    const verified = await app.inject({ method: "POST", url: "/v1/auth/verify", payload: { token } });
    return { accessToken: verified.json().accessToken, userId: verified.json().user.id };
  }

  async function completedUpload(auth: Record<string, string>): Promise<string> {
    const created = await app.inject({ method: "POST", url: "/v1/uploads", headers: auth, payload: { filename: "demo.mp4", contentType: "video/mp4", sizeBytes: 1, partCount: 1 } });
    const upload = created.json();
    await app.inject({ method: "PUT", url: new URL(upload.partUrls[0]).pathname, headers: { "content-type": "application/octet-stream" }, payload: Buffer.from("x") });
    await app.inject({ method: "POST", url: `/v1/uploads/${upload.id}/complete`, headers: auth, payload: { parts: [{ partNumber: 1, etag: "local-1" }] } });
    return upload.id;
  }
});
