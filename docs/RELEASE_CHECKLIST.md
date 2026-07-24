# Release Checklist

## Desktop

- Run two-hour 4K60 recordings on the oldest and newest supported Apple Silicon devices.
- Verify display/window permissions, multi-monitor scaling, Bluetooth audio, camera disconnect, disk full, sleep/wake, and crash recovery.
- Confirm export audio sync remains within 50 ms after one hour and all Free/Pro limits are enforced offline and online.
- Generate a signed archive, enable hardened runtime, notarize, staple, and test the DMG on a clean macOS account.
- Configure Sparkle signing keys and staged update feeds before enabling automatic updates.

## Cloud

- Apply migrations against a backup-restorable PostgreSQL instance and test rollback from a staging snapshot.
- Configure private S3, lifecycle deletion, CDN, Redis persistence, Resend domain, Paddle products/webhooks, and AI cost alerts.
- Run authorization, upload interruption, duplicate webhook, expired link, password brute force, data export, and account deletion suites.
- Verify logs and traces redact emails, tokens, titles, captions, and object URLs.

## Launch Gate

- Recording start success >= 99.5%, crash-free sessions >= 99.8%, export success >= 99%.
- No critical/high dependency advisories and no unresolved security findings.
- Privacy policy, DPA/subprocessor list, retention schedule, refund policy, incident runbook, and support escalation are published.
