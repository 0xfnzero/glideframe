import type { AnalyticsEventInput, CreateAiJob, Entitlement, Plan } from "@glideframe/contracts";

export type User = { id: string; email: string; createdAt: string };
export type Upload = {
  id: string;
  userId: string;
  filename: string;
  contentType: string;
  sizeBytes: number;
  partCount: number;
  storageKey: string;
  storageUploadId: string;
  status: "uploading" | "completed" | "deleted";
  createdAt: string;
};
export type Share = {
  id: string;
  token: string;
  userId: string;
  uploadId: string;
  title: string;
  passwordHash?: string;
  expiresAt?: string;
  revokedAt?: string;
  createdAt: string;
};
export type AiJob = CreateAiJob & {
  id: string;
  userId: string;
  status: "queued" | "running" | "succeeded" | "failed";
  result?: unknown;
  error?: string;
  createdAt: string;
  updatedAt: string;
};

export interface Store {
  createMagicLink(email: string, tokenHash: string, expiresAt: string): Promise<void>;
  consumeMagicLink(tokenHash: string, now: string): Promise<User | null>;
  getEntitlement(userId: string): Promise<Entitlement>;
  setPlan(userId: string, plan: Plan, status: Entitlement["status"], expiresAt: string | null): Promise<void>;
  createUpload(upload: Upload): Promise<void>;
  getUpload(id: string): Promise<Upload | null>;
  completeUpload(id: string): Promise<void>;
  createShare(share: Share): Promise<void>;
  listShares(userId: string): Promise<Share[]>;
  getShareByToken(token: string): Promise<Share | null>;
  getShare(id: string): Promise<Share | null>;
  revokeShare(id: string, userId: string, now: string): Promise<boolean>;
  addAnalytics(shareId: string, event: AnalyticsEventInput): Promise<void>;
  getAnalytics(shareId: string): Promise<{ views: number; uniqueViewers: number; completionRate: number }>;
  createAiJob(job: AiJob): Promise<void>;
  getAiJob(id: string): Promise<AiJob | null>;
  updateAiJob(id: string, patch: Partial<AiJob>): Promise<void>;
  markWebhookProcessed(id: string): Promise<boolean>;
}
