import { createReadStream, createWriteStream } from "node:fs";
import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { pipeline } from "node:stream/promises";
import type { Readable } from "node:stream";
import {
  CompleteMultipartUploadCommand,
  CreateMultipartUploadCommand,
  GetObjectCommand,
  S3Client,
  UploadPartCommand
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import type { AppConfig } from "./config.js";

export interface ObjectStore {
  initiate(key: string, contentType: string, parts: number): Promise<{ uploadId: string; partUrls: string[] }>;
  putLocalPart?(uploadId: string, partNumber: number, body: Buffer): Promise<string>;
  complete(key: string, uploadId: string, parts: { partNumber: number; etag: string }[]): Promise<void>;
  playbackUrl(key: string): Promise<string>;
  localPath?(key: string): string;
}

export class LocalObjectStore implements ObjectStore {
  constructor(private readonly root: string, private readonly publicApiUrl: string) {}

  async initiate(_key: string, _contentType: string, parts: number) {
    const uploadId = crypto.randomUUID();
    await mkdir(path.join(this.root, "parts", uploadId), { recursive: true });
    return {
      uploadId,
      partUrls: Array.from({ length: parts }, (_, index) => `${this.publicApiUrl}/v1/uploads/local/${uploadId}/parts/${index + 1}`)
    };
  }

  async putLocalPart(uploadId: string, partNumber: number, body: Buffer): Promise<string> {
    const target = path.join(this.root, "parts", uploadId, String(partNumber));
    await mkdir(path.dirname(target), { recursive: true });
    await writeFile(target, body);
    return `local-${body.byteLength}`;
  }

  async complete(key: string, uploadId: string, parts: { partNumber: number }[]): Promise<void> {
    const destination = this.localPath(key);
    await mkdir(path.dirname(destination), { recursive: true });
    const output = createWriteStream(`${destination}.partial`);
    for (const part of [...parts].sort((a, b) => a.partNumber - b.partNumber)) {
      await pipeline(createReadStream(path.join(this.root, "parts", uploadId, String(part.partNumber))), output, { end: false });
    }
    output.end();
    await new Promise<void>((resolve, reject) => { output.on("finish", resolve); output.on("error", reject); });
    await rename(`${destination}.partial`, destination);
    await rm(path.join(this.root, "parts", uploadId), { recursive: true, force: true });
  }

  async playbackUrl(key: string): Promise<string> { return `${this.publicApiUrl}/v1/media/${encodeURIComponent(key)}`; }
  localPath(key: string): string {
    const base = path.resolve(this.root, "objects");
    const resolved = path.resolve(base, key);
    if (!resolved.startsWith(`${base}${path.sep}`)) throw new Error("Invalid object key.");
    return resolved;
  }
}

export class S3ObjectStore implements ObjectStore {
  private readonly client: S3Client;
  constructor(private readonly config: AppConfig) {
    this.client = new S3Client({ region: config.S3_REGION, ...(config.S3_ENDPOINT ? { endpoint: config.S3_ENDPOINT, forcePathStyle: true } : {}) });
  }
  async initiate(key: string, contentType: string, parts: number) {
    const bucket = this.requiredBucket();
    const created = await this.client.send(new CreateMultipartUploadCommand({ Bucket: bucket, Key: key, ContentType: contentType, ServerSideEncryption: "AES256" }));
    if (!created.UploadId) throw new Error("S3 did not return an upload ID.");
    const partUrls = await Promise.all(Array.from({ length: parts }, (_, index) => getSignedUrl(
      this.client,
      new UploadPartCommand({ Bucket: bucket, Key: key, UploadId: created.UploadId, PartNumber: index + 1 }),
      { expiresIn: 900 }
    )));
    return { uploadId: created.UploadId, partUrls };
  }
  async complete(key: string, uploadId: string, parts: { partNumber: number; etag: string }[]): Promise<void> {
    await this.client.send(new CompleteMultipartUploadCommand({
      Bucket: this.requiredBucket(), Key: key, UploadId: uploadId,
      MultipartUpload: { Parts: parts.map((part) => ({ PartNumber: part.partNumber, ETag: part.etag })) }
    }));
  }
  async playbackUrl(key: string): Promise<string> {
    return getSignedUrl(this.client, new GetObjectCommand({ Bucket: this.requiredBucket(), Key: key }), { expiresIn: 3600 });
  }
  private requiredBucket(): string { if (!this.config.S3_BUCKET) throw new Error("S3_BUCKET is required."); return this.config.S3_BUCKET; }
}

export function createObjectStore(config: AppConfig): ObjectStore {
  return config.STORAGE_DRIVER === "s3" ? new S3ObjectStore(config) : new LocalObjectStore(config.STORAGE_ROOT, config.PUBLIC_API_URL);
}
