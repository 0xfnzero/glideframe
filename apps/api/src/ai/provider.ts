import type { AiJob } from "../domain.js";

export interface AiProvider { run(job: AiJob, mediaUrl: string): Promise<unknown> }

export class HttpAiProvider implements AiProvider {
  constructor(private readonly url: string, private readonly token?: string) {}
  async run(job: AiJob, mediaUrl: string): Promise<unknown> {
    const response = await fetch(this.url, {
      method: "POST",
      headers: { "content-type": "application/json", ...(this.token ? { authorization: `Bearer ${this.token}` } : {}) },
      body: JSON.stringify({ jobId: job.id, mediaUrl, operation: job.operation, sourceLanguage: job.sourceLanguage, targetLanguage: job.targetLanguage })
    });
    if (!response.ok) throw new Error(`AI provider returned ${response.status}.`);
    return response.json();
  }
}
