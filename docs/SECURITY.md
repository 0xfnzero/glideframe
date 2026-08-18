# Security Baseline

- Raw recordings remain local until the user explicitly starts an upload or AI task.
- Access tokens expire after 15 minutes; share unlock tokens expire after one hour.
- Passwords use scrypt with a random per-share salt. Magic links are stored only as SHA-256 hashes and are single-use.
- S3 multipart uploads use short-lived presigned URLs and server-side encryption. Object keys are server-generated.
- Local media paths reject traversal and support bounded HTTP Range requests.
- Telemetry must never contain video, audio, captions, titles, emails, tokens, or share passwords.
- Production startup must provide a strong `JWT_SECRET`, Resend credentials, TLS termination, and private PostgreSQL/Redis networking.

Before launch, perform dependency, authorization, IDOR, rate-limit, malformed media, object retention, and account deletion testing. Add edge rate limiting and a malware scanning job before accepting uploads from untrusted sources.

Report security issues privately to the address published in the production security policy. Do not include user recordings in reports.
