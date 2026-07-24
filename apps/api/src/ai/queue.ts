import type { AiJob } from "../domain.js";
import { Queue } from "bullmq";
import { Redis } from "ioredis";

export interface AiJobQueue { enqueue(job: AiJob): Promise<void>; close(): Promise<void> }

export class InlineAiJobQueue implements AiJobQueue {
  async enqueue(_job: AiJob): Promise<void> {}
  async close(): Promise<void> {}
}

export async function createAiQueue(redisUrl?: string): Promise<AiJobQueue> {
  if (!redisUrl) return new InlineAiJobQueue();
  const connection = new Redis(redisUrl, { maxRetriesPerRequest: null });
  const queue = new Queue<AiJob>("glideframe-ai", { connection });
  return {
    async enqueue(job) { await queue.add(job.operation, job, { jobId: job.id, attempts: 3, backoff: { type: "exponential", delay: 2000 }, removeOnComplete: 1000 }); },
    async close() { await queue.close(); await connection.quit(); }
  };
}
