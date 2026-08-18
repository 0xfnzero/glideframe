CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS magic_links (
  token_hash text PRIMARY KEY,
  email text NOT NULL,
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz
);

CREATE TABLE IF NOT EXISTS uploads (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  filename text NOT NULL,
  content_type text NOT NULL,
  size_bytes bigint NOT NULL CHECK (size_bytes > 0),
  part_count integer NOT NULL CHECK (part_count > 0),
  storage_key text NOT NULL UNIQUE,
  storage_upload_id text NOT NULL,
  status text NOT NULL CHECK (status IN ('uploading', 'completed', 'deleted')),
  created_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS uploads_user_status_idx ON uploads(user_id, status);

CREATE TABLE IF NOT EXISTS shares (
  id uuid PRIMARY KEY,
  token text NOT NULL UNIQUE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  upload_id uuid NOT NULL REFERENCES uploads(id) ON DELETE CASCADE,
  title text NOT NULL,
  password_hash text,
  expires_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS shares_user_created_idx ON shares(user_id, created_at);

CREATE TABLE IF NOT EXISTS share_events (
  id bigserial PRIMARY KEY,
  share_id uuid NOT NULL REFERENCES shares(id) ON DELETE CASCADE,
  event text NOT NULL CHECK (event IN ('play', 'progress', 'complete')),
  session_id uuid NOT NULL,
  progress double precision NOT NULL CHECK (progress >= 0 AND progress <= 1),
  occurred_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS share_events_share_idx ON share_events(share_id, occurred_at);

CREATE TABLE IF NOT EXISTS ai_jobs (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  upload_id uuid NOT NULL REFERENCES uploads(id) ON DELETE CASCADE,
  operation text NOT NULL,
  source_language text NOT NULL,
  target_language text,
  media_minutes double precision NOT NULL CHECK (media_minutes > 0),
  status text NOT NULL CHECK (status IN ('queued', 'running', 'succeeded', 'failed')),
  result jsonb,
  error text,
  created_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS ai_jobs_user_created_idx ON ai_jobs(user_id, created_at);

CREATE TABLE IF NOT EXISTS schema_migrations (
  version text PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
);
