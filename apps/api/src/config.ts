import { z } from "zod";

const configSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  HOST: z.string().default("127.0.0.1"),
  PORT: z.coerce.number().int().positive().default(4100),
  PUBLIC_API_URL: z.string().url().default("http://127.0.0.1:4100"),
  WEB_URL: z.string().url().default("http://127.0.0.1:3000"),
  JWT_SECRET: z.string().min(32).default("development-only-secret-change-me-0001"),
  DATABASE_URL: z.string().url().optional(),
  REDIS_URL: z.string().url().optional(),
  STORAGE_DRIVER: z.enum(["local", "s3"]).default("local"),
  STORAGE_ROOT: z.string().default(".data/storage"),
  S3_BUCKET: z.string().optional(),
  S3_REGION: z.string().default("us-east-1"),
  S3_ENDPOINT: z.string().url().optional(),
  RESEND_API_KEY: z.string().min(16).optional(),
  EMAIL_FROM: z.string().email().optional(),
  AI_PROVIDER_URL: z.string().url().optional(),
  AI_PROVIDER_TOKEN: z.string().optional()
});

export type AppConfig = z.infer<typeof configSchema>;
export const config = configSchema.parse(process.env);
