import { randomUUID } from "node:crypto";
import type { AnalyticsEventInput, Entitlement, Plan } from "@glideframe/contracts";
import type { AiJob, Share, Store, Upload, User } from "./domain.js";

type MagicLink = { email: string; tokenHash: string; expiresAt: string; consumed: boolean };

export class MemoryStore implements Store {
  private readonly users = new Map<string, User>();
  private readonly usersByEmail = new Map<string, string>();
  private readonly magicLinks: MagicLink[] = [];
  private readonly plans = new Map<string, { plan: Plan; status: Entitlement["status"]; expiresAt: string | null }>();
  private readonly uploads = new Map<string, Upload>();
  private readonly shares = new Map<string, Share>();
  private readonly events = new Map<string, AnalyticsEventInput[]>();
  private readonly jobs = new Map<string, AiJob>();
  private readonly webhooks = new Set<string>();

  async createMagicLink(email: string, tokenHash: string, expiresAt: string): Promise<void> {
    this.magicLinks.push({ email: email.toLowerCase(), tokenHash, expiresAt, consumed: false });
  }

  async consumeMagicLink(tokenHash: string, now: string): Promise<User | null> {
    const link = this.magicLinks.find((item) => item.tokenHash === tokenHash && !item.consumed && item.expiresAt > now);
    if (!link) return null;
    link.consumed = true;
    const existingId = this.usersByEmail.get(link.email);
    if (existingId) return this.users.get(existingId) ?? null;
    const user = { id: randomUUID(), email: link.email, createdAt: now };
    this.users.set(user.id, user);
    this.usersByEmail.set(user.email, user.id);
    return user;
  }

  async getEntitlement(userId: string): Promise<Entitlement> {
    const subscription = this.plans.get(userId) ?? { plan: "free" as const, status: "active" as const, expiresAt: null };
    const isPro = subscription.plan === "pro" && ["active", "trialing"].includes(subscription.status);
    const userUploads = [...this.uploads.values()].filter((upload) => upload.userId === userId && upload.status !== "deleted");
    const thisMonth = new Date().toISOString().slice(0, 7);
    const aiMinutesUsed = [...this.jobs.values()]
      .filter((job) => job.userId === userId && job.createdAt.startsWith(thisMonth))
      .reduce((sum, job) => sum + job.mediaMinutes, 0);
    const sharesUsed = [...this.shares.values()].filter((share) => share.userId === userId && share.createdAt.startsWith(thisMonth)).length;
    return {
      plan: isPro ? "pro" : "free",
      status: subscription.status,
      expiresAt: subscription.expiresAt,
      maxRecordingSeconds: isPro ? null : 600,
      maxExportHeight: isPro ? 2160 : 1080,
      maxFrameRate: isPro ? 60 : 30,
      monthlyAiMinutes: isPro ? 180 : 0,
      aiMinutesUsed,
      storageBytes: isPro ? 50 * 1024 ** 3 : 2 * 1024 ** 3,
      storageBytesUsed: userUploads.reduce((sum, upload) => sum + upload.sizeBytes, 0),
      monthlyShares: isPro ? 1000 : 3,
      sharesUsed,
      deviceLimit: isPro ? 3 : 1
    };
  }

  async setPlan(userId: string, plan: Plan, status: Entitlement["status"], expiresAt: string | null): Promise<void> {
    this.plans.set(userId, { plan, status, expiresAt });
  }
  async createUpload(upload: Upload): Promise<void> { this.uploads.set(upload.id, upload); }
  async getUpload(id: string): Promise<Upload | null> { return this.uploads.get(id) ?? null; }
  async completeUpload(id: string): Promise<void> { const upload = this.uploads.get(id); if (upload) upload.status = "completed"; }
  async createShare(share: Share): Promise<void> { this.shares.set(share.id, share); }
  async listShares(userId: string): Promise<Share[]> { return [...this.shares.values()].filter((share) => share.userId === userId).sort((a, b) => b.createdAt.localeCompare(a.createdAt)); }
  async getShareByToken(token: string): Promise<Share | null> { return [...this.shares.values()].find((share) => share.token === token) ?? null; }
  async getShare(id: string): Promise<Share | null> { return this.shares.get(id) ?? null; }
  async revokeShare(id: string, userId: string, now: string): Promise<boolean> {
    const share = this.shares.get(id);
    if (!share || share.userId !== userId) return false;
    share.revokedAt = now;
    return true;
  }
  async addAnalytics(shareId: string, event: AnalyticsEventInput): Promise<void> {
    this.events.set(shareId, [...(this.events.get(shareId) ?? []), event]);
  }
  async getAnalytics(shareId: string): Promise<{ views: number; uniqueViewers: number; completionRate: number }> {
    const events = this.events.get(shareId) ?? [];
    const sessions = new Set(events.map((event) => event.sessionId));
    const completed = new Set(events.filter((event) => event.event === "complete" || event.progress >= 0.95).map((event) => event.sessionId));
    return { views: events.filter((event) => event.event === "play").length, uniqueViewers: sessions.size, completionRate: sessions.size ? completed.size / sessions.size : 0 };
  }
  async createAiJob(job: AiJob): Promise<void> { this.jobs.set(job.id, job); }
  async getAiJob(id: string): Promise<AiJob | null> { return this.jobs.get(id) ?? null; }
  async updateAiJob(id: string, patch: Partial<AiJob>): Promise<void> { const job = this.jobs.get(id); if (job) this.jobs.set(id, { ...job, ...patch }); }
  async markWebhookProcessed(id: string): Promise<boolean> { if (this.webhooks.has(id)) return false; this.webhooks.add(id); return true; }
}
