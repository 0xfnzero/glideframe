import { z } from "zod";

export const planSchema = z.enum(["community"]);
export type Plan = z.infer<typeof planSchema>;

export const entitlementSchema = z.object({
  plan: planSchema,
  status: z.enum(["active"]),
  expiresAt: z.string().datetime().nullable(),
  maxRecordingSeconds: z.number().int().positive().nullable(),
  maxExportHeight: z.number().int().positive(),
  maxFrameRate: z.number().int().positive(),
  monthlyAiMinutes: z.number().nonnegative(),
  aiMinutesUsed: z.number().nonnegative(),
  storageBytes: z.number().nonnegative(),
  storageBytesUsed: z.number().nonnegative(),
  monthlyShares: z.number().int().nonnegative(),
  sharesUsed: z.number().int().nonnegative(),
  deviceLimit: z.number().int().positive()
});
export type Entitlement = z.infer<typeof entitlementSchema>;

export const magicLinkRequestSchema = z.object({ email: z.string().email().max(320) });
export const magicLinkVerifySchema = z.object({ token: z.string().min(32).max(256) });

export const createUploadSchema = z.object({
  filename: z.string().min(1).max(240),
  contentType: z.enum(["video/mp4", "video/quicktime"]),
  sizeBytes: z.number().int().positive().max(100 * 1024 * 1024 * 1024),
  partCount: z.number().int().min(1).max(10_000)
});

export const completeUploadSchema = z.object({
  parts: z.array(z.object({ partNumber: z.number().int().positive(), etag: z.string().min(1) })).min(1)
});

export const createShareSchema = z.object({
  uploadId: z.string().uuid(),
  title: z.string().trim().min(1).max(160),
  password: z.string().min(8).max(128).optional(),
  expiresAt: z.string().datetime().optional()
});

export const verifyShareSchema = z.object({ password: z.string().max(128) });

export const analyticsEventSchema = z.object({
  event: z.enum(["play", "progress", "complete"]),
  sessionId: z.string().uuid(),
  progress: z.number().min(0).max(1),
  occurredAt: z.string().datetime()
});

export const createAiJobSchema = z.object({
  uploadId: z.string().uuid(),
  operation: z.enum(["transcribe", "translate", "summarize", "detect-silence"]),
  sourceLanguage: z.enum(["auto", "en", "zh-Hans"]),
  targetLanguage: z.enum(["en", "zh-Hans"]).optional(),
  mediaMinutes: z.number().positive().max(180)
});

export type CreateUpload = z.infer<typeof createUploadSchema>;
export type CompleteUpload = z.infer<typeof completeUploadSchema>;
export type CreateShare = z.infer<typeof createShareSchema>;
export type AnalyticsEventInput = z.infer<typeof analyticsEventSchema>;
export type CreateAiJob = z.infer<typeof createAiJobSchema>;
