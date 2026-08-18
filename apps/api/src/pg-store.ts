import type { AnalyticsEventInput, Entitlement } from "@glideframe/contracts";
import { Pool, type PoolClient } from "pg";
import type { AiJob, Share, Store, Upload, User } from "./domain.js";

export class PgStore implements Store {
  readonly pool: Pool;
  constructor(databaseUrl: string) { this.pool = new Pool({ connectionString: databaseUrl, max: 10, idleTimeoutMillis: 30_000 }); }
  async close(): Promise<void> { await this.pool.end(); }

  async createMagicLink(email: string, tokenHash: string, expiresAt: string): Promise<void> {
    await this.pool.query(
      `INSERT INTO magic_links(token_hash, email, expires_at) VALUES ($1, lower($2), $3)
       ON CONFLICT(token_hash) DO UPDATE SET email=excluded.email, expires_at=excluded.expires_at, consumed_at=NULL`,
      [tokenHash, email, expiresAt]
    );
  }

  async consumeMagicLink(tokenHash: string, now: string): Promise<User | null> {
    const client = await this.pool.connect();
    try {
      await client.query("BEGIN");
      const link = await client.query<{ email: string }>(
        `UPDATE magic_links SET consumed_at=$2 WHERE token_hash=$1 AND consumed_at IS NULL AND expires_at>$2 RETURNING email`,
        [tokenHash, now]
      );
      if (!link.rows[0]) { await client.query("ROLLBACK"); return null; }
      const user = await client.query<{ id: string; email: string; created_at: Date }>(
        `INSERT INTO users(email) VALUES (lower($1)) ON CONFLICT(email) DO UPDATE SET email=excluded.email RETURNING id,email,created_at`,
        [link.rows[0].email]
      );
      await client.query("COMMIT");
      const row = user.rows[0]!;
      return { id: row.id, email: row.email, createdAt: row.created_at.toISOString() };
    } catch (error) { await client.query("ROLLBACK"); throw error; }
    finally { client.release(); }
  }

  async getEntitlement(userId: string): Promise<Entitlement> {
    const result = await this.pool.query<{
      storage_used: string; ai_used: number; shares_used: string;
    }>(
      `SELECT COALESCE((SELECT SUM(size_bytes) FROM uploads WHERE user_id=$1 AND status<>'deleted'),0) storage_used,
        COALESCE((SELECT SUM(media_minutes) FROM ai_jobs WHERE user_id=$1 AND created_at>=date_trunc('month',now())),0) ai_used,
        COALESCE((SELECT COUNT(*) FROM shares WHERE user_id=$1 AND created_at>=date_trunc('month',now())),0) shares_used`,
      [userId]
    );
    const row = result.rows[0]!;
    return {
      plan: "community", status: "active", expiresAt: null,
      maxRecordingSeconds: null, maxExportHeight: 2160, maxFrameRate: 60,
      monthlyAiMinutes: 0, aiMinutesUsed: Number(row.ai_used), storageBytes: 10 * 1024 ** 3,
      storageBytesUsed: Number(row.storage_used), monthlyShares: 100, sharesUsed: Number(row.shares_used), deviceLimit: 1
    };
  }
  async createUpload(value: Upload): Promise<void> {
    await this.pool.query(
      `INSERT INTO uploads(id,user_id,filename,content_type,size_bytes,part_count,storage_key,storage_upload_id,status,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
      [value.id,value.userId,value.filename,value.contentType,value.sizeBytes,value.partCount,value.storageKey,value.storageUploadId,value.status,value.createdAt]
    );
  }
  async getUpload(id: string): Promise<Upload | null> {
    const result = await this.pool.query(`SELECT * FROM uploads WHERE id=$1`, [id]);
    return result.rows[0] ? uploadFromRow(result.rows[0]) : null;
  }
  async completeUpload(id: string): Promise<void> { await this.pool.query(`UPDATE uploads SET status='completed' WHERE id=$1`, [id]); }
  async createShare(value: Share): Promise<void> {
    await this.pool.query(
      `INSERT INTO shares(id,token,user_id,upload_id,title,password_hash,expires_at,revoked_at,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
      [value.id,value.token,value.userId,value.uploadId,value.title,value.passwordHash ?? null,value.expiresAt ?? null,value.revokedAt ?? null,value.createdAt]
    );
  }
  async listShares(userId: string): Promise<Share[]> { const r=await this.pool.query(`SELECT * FROM shares WHERE user_id=$1 ORDER BY created_at DESC LIMIT 100`,[userId]); return r.rows.map(shareFromRow); }
  async getShareByToken(token: string): Promise<Share | null> { const r=await this.pool.query(`SELECT * FROM shares WHERE token=$1`,[token]); return r.rows[0]?shareFromRow(r.rows[0]):null; }
  async getShare(id: string): Promise<Share | null> { const r=await this.pool.query(`SELECT * FROM shares WHERE id=$1`,[id]); return r.rows[0]?shareFromRow(r.rows[0]):null; }
  async revokeShare(id: string, userId: string, now: string): Promise<boolean> { const r=await this.pool.query(`UPDATE shares SET revoked_at=$3 WHERE id=$1 AND user_id=$2 AND revoked_at IS NULL`,[id,userId,now]); return (r.rowCount??0)>0; }
  async addAnalytics(shareId: string, event: AnalyticsEventInput): Promise<void> {
    await this.pool.query(`INSERT INTO share_events(share_id,event,session_id,progress,occurred_at) VALUES($1,$2,$3,$4,$5)`,[shareId,event.event,event.sessionId,event.progress,event.occurredAt]);
  }
  async getAnalytics(shareId: string): Promise<{ views: number; uniqueViewers: number; completionRate: number }> {
    const r=await this.pool.query<{views:string;unique_viewers:string;completed:string}>(
      `SELECT COUNT(*) FILTER(WHERE event='play') views,COUNT(DISTINCT session_id) unique_viewers,
       COUNT(DISTINCT session_id) FILTER(WHERE event='complete' OR progress>=.95) completed FROM share_events WHERE share_id=$1`,[shareId]
    );
    const row=r.rows[0]!; const unique=Number(row.unique_viewers); return {views:Number(row.views),uniqueViewers:unique,completionRate:unique?Number(row.completed)/unique:0};
  }
  async createAiJob(job: AiJob): Promise<void> {
    await this.pool.query(
      `INSERT INTO ai_jobs(id,user_id,upload_id,operation,source_language,target_language,media_minutes,status,result,error,created_at,updated_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
      [job.id,job.userId,job.uploadId,job.operation,job.sourceLanguage,job.targetLanguage??null,job.mediaMinutes,job.status,job.result??null,job.error??null,job.createdAt,job.updatedAt]
    );
  }
  async getAiJob(id: string): Promise<AiJob | null> { const r=await this.pool.query(`SELECT * FROM ai_jobs WHERE id=$1`,[id]); return r.rows[0]?aiJobFromRow(r.rows[0]):null; }
  async updateAiJob(id: string, patch: Partial<AiJob>): Promise<void> {
    await this.pool.query(`UPDATE ai_jobs SET status=COALESCE($2,status),result=COALESCE($3,result),error=$4,updated_at=COALESCE($5,now()) WHERE id=$1`,[id,patch.status??null,patch.result??null,patch.error??null,patch.updatedAt??null]);
  }
}

function uploadFromRow(row: Record<string, unknown>): Upload { return { id:String(row.id),userId:String(row.user_id),filename:String(row.filename),contentType:String(row.content_type),sizeBytes:Number(row.size_bytes),partCount:Number(row.part_count),storageKey:String(row.storage_key),storageUploadId:String(row.storage_upload_id),status:row.status as Upload["status"],createdAt:(row.created_at as Date).toISOString() }; }
function shareFromRow(row: Record<string, unknown>): Share { return { id:String(row.id),token:String(row.token),userId:String(row.user_id),uploadId:String(row.upload_id),title:String(row.title),...(row.password_hash?{passwordHash:String(row.password_hash)}:{}),...(row.expires_at?{expiresAt:(row.expires_at as Date).toISOString()}:{}),...(row.revoked_at?{revokedAt:(row.revoked_at as Date).toISOString()}:{}),createdAt:(row.created_at as Date).toISOString() }; }
function aiJobFromRow(row: Record<string, unknown>): AiJob { return { id:String(row.id),userId:String(row.user_id),uploadId:String(row.upload_id),operation:row.operation as AiJob["operation"],sourceLanguage:row.source_language as AiJob["sourceLanguage"],...(row.target_language?{targetLanguage:row.target_language as AiJob["targetLanguage"]}:{}),mediaMinutes:Number(row.media_minutes),status:row.status as AiJob["status"],...(row.result?{result:row.result}:{}),...(row.error?{error:String(row.error)}:{}),createdAt:(row.created_at as Date).toISOString(),updatedAt:(row.updated_at as Date).toISOString() }; }
