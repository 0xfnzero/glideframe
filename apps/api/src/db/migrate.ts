import { readFile } from "node:fs/promises";
import { Pool } from "pg";
import { config } from "../config.js";

if (!config.DATABASE_URL) throw new Error("DATABASE_URL is required.");
const pool = new Pool({ connectionString: config.DATABASE_URL });
try {
  const sql = await readFile(new URL("../../migrations/001_init.sql", import.meta.url), "utf8");
  await pool.query(sql);
  await pool.query(`INSERT INTO schema_migrations(version) VALUES('001_init') ON CONFLICT DO NOTHING`);
  console.log("Applied database migration 001_init");
} finally { await pool.end(); }
