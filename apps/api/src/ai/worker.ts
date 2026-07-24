import { Worker } from "bullmq";
import { Redis } from "ioredis";
import { config } from "../config.js";
import type { AiJob } from "../domain.js";
import { PgStore } from "../pg-store.js";
import { createObjectStore } from "../object-store.js";
import { HttpAiProvider } from "./provider.js";

if (!config.DATABASE_URL || !config.REDIS_URL || !config.AI_PROVIDER_URL) {
  throw new Error("DATABASE_URL, REDIS_URL and AI_PROVIDER_URL are required for the AI worker.");
}
const connection = new Redis(config.REDIS_URL, { maxRetriesPerRequest: null });
const store = new PgStore(config.DATABASE_URL);
const provider = new HttpAiProvider(config.AI_PROVIDER_URL, config.AI_PROVIDER_TOKEN);
const objects = createObjectStore(config);
const worker = new Worker<AiJob>("glideframe-ai", async (queued) => {
  const now = new Date().toISOString();
  await store.updateAiJob(queued.data.id, { status: "running", updatedAt: now });
  try {
    const upload = await store.getUpload(queued.data.uploadId);
    if (!upload || upload.status !== "completed") throw new Error("AI job media is unavailable.");
    const result = await provider.run(queued.data, await objects.playbackUrl(upload.storageKey));
    await store.updateAiJob(queued.data.id, { status: "succeeded", result, updatedAt: new Date().toISOString() });
  } catch (error) {
    await store.updateAiJob(queued.data.id, { status: "failed", error: error instanceof Error ? error.message : "AI job failed", updatedAt: new Date().toISOString() });
    throw error;
  }
}, { connection, concurrency: 4 });

async function shutdown() { await worker.close(); await connection.quit(); await store.close(); process.exit(0); }
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
