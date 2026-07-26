# Commercial Roadmap

Status: planned, not committed to a release date.

This document tracks work that is intentionally not implemented yet. Items move into a release milestone only after product validation and explicit prioritization. The primary product promise is:

> Help product, support, sales, and engineering teams create and share a polished product demonstration in minutes.

## Prioritization Rules

- P0 establishes a product that can be sold reliably to individual professionals.
- P1 adds team retention, higher average revenue per account, and scalable cloud workflows.
- P2 addresses enterprise procurement and platform expansion after retention is proven.
- New work should shorten time-to-published-video, increase successful shares, improve retention, or reduce operational risk.
- Generic media conversion and unrelated creator features must not displace the recording-to-share workflow.

## P0: Monetizable Product

### Editor and Output Fidelity

- [ ] Make editor preview output match exported output for canvas, zoom, camera, captions, audio, and timing.
- [ ] Add a real playhead with frame-accurate scrubbing and synchronized preview.
- [ ] Support split, delete, ripple delete, reorder, and multi-clip trim operations.
- [ ] Add undo and redo for every destructive or styling edit.
- [ ] Make automatic zoom keyframes selectable, movable, resizable, removable, and manually creatable.
- [ ] Add zoom easing, duration, strength, and focus controls.
- [ ] Render the camera track with position, size, crop, shape, border, and visibility controls.
- [ ] Generate, edit, style, and burn captions into exports.
- [ ] Implement silence removal instead of storing the setting only.
- [ ] Implement microphone noise reduction, gain, mute, and system/microphone mixing controls.
- [ ] Render real audio waveforms and maintain audio/video synchronization after edits.
- [ ] Add cursor replacement, click emphasis, and cursor visibility controls.
- [ ] Add blur and redaction regions for sensitive on-screen information.
- [ ] Add reusable brand presets for background, font, logo, frame, and export format.
- [ ] Add export progress, cancellation, estimated completion time, and actionable failure recovery.

Editor acceptance criteria:

- [ ] A new user can record, polish, and export a 60-second product demo in under five minutes without documentation.
- [ ] Preview and export have no visible layout or timing differences in the supported edit graph.
- [ ] Reopening a project preserves every supported edit and can reproduce the same export.

### Desktop-to-Cloud Workflow

- [ ] Add account sign-in and secure token storage to the macOS app.
- [ ] Connect desktop entitlements to the existing Free and Pro plans with an offline grace period.
- [ ] Add one-click export, multipart upload, share creation, and link copying from the editor.
- [ ] Upload in the background with pause, retry, resume, and recoverable failure states.
- [ ] Allow password, expiry, download permission, title, and cover selection before publishing.
- [ ] Allow a published video to be replaced while preserving its share URL.
- [ ] List, open, copy, update, expire, and revoke shares from the desktop app.
- [ ] Keep raw recordings local unless the user explicitly publishes or starts an AI operation.

Publishing acceptance criteria:

- [ ] A user can move from stopped recording to copied share link without opening the web workspace.
- [ ] Interrupted uploads resume without restarting completed parts.
- [ ] Repeated publish actions cannot create duplicate uploads or quota charges.

### Production-Ready Desktop Release

- [ ] Complete every desktop item in `RELEASE_CHECKLIST.md`.
- [ ] Produce a hardened, signed, notarized, and stapled application and DMG.
- [ ] Add Sparkle updates with signed feeds, staged rollout, and rollback capability.
- [ ] Add privacy-preserving crash reporting and recording/export quality telemetry.
- [ ] Add automated capture, edit, export, recovery, and permission regression tests.
- [ ] Test two-hour 4K60 capture, multi-display layouts, Retina scaling, sleep/wake, disk full, Bluetooth audio, and device disconnection.
- [ ] Publish an FFmpeg redistribution decision and license inventory before bundling conversion tools.

Release quality gates:

- [ ] Recording start success is at least 99.5%.
- [ ] Crash-free recording sessions are at least 99.8%.
- [ ] Export success is at least 99%.
- [ ] One-hour exports keep audio/video drift below 50 ms.

## P1: Team Product

### Workspace and Collaboration

- [ ] Add organizations, workspaces, memberships, invitations, and seat limits to the data model.
- [ ] Add Owner, Admin, Member, and Viewer roles with server-side authorization.
- [ ] Add a shared video library with folders, search, ownership, and access controls.
- [ ] Add timestamped comments, mentions, replies, resolved states, and review status.
- [ ] Add video versions that preserve comments and the public URL where possible.
- [ ] Add shared brand presets and administrator-controlled defaults.
- [ ] Add workspace activity history for publishing, sharing, comments, and membership changes.
- [ ] Integrate share notifications with Slack, Jira, Linear, and Notion after core retention is proven.

### Billing and Account Lifecycle

- [ ] Extend Free and Pro billing with trials, cancellation, resume, refund, and plan changes.
- [ ] Add Paddle customer portal access, invoices, tax handling, and billing email updates.
- [ ] Handle failed renewal, grace period, past-due recovery, and entitlement expiration consistently.
- [ ] Add seat-based team plans with prorated seat changes.
- [ ] Add device registration, device removal, and enforce device limits in the desktop app.
- [ ] Add coupon and campaign attribution without embedding price logic in clients.
- [ ] Add account data export and account deletion with verified object cleanup.

### Cloud Media and Analytics

- [ ] Add an asynchronous ingest pipeline for metadata extraction, thumbnails, and validation.
- [ ] Transcode published media to adaptive HLS renditions instead of relying on raw source playback.
- [ ] Put playback behind a CDN with signed access and controlled cache behavior.
- [ ] Add retention policies, orphaned multipart cleanup, object deletion jobs, and restore-tested backups.
- [ ] Add malware and malformed-media scanning before processing untrusted uploads.
- [ ] Add viewer engagement heatmaps, drop-off points, unique viewers, and referrer attribution.
- [ ] Add optional viewer identity collection with explicit privacy controls.
- [ ] Add embeds, custom thumbnails, custom domains, and workspace branding.
- [ ] Add transcription, summaries, chapters, and searchable video content with per-job cost controls.

P1 acceptance criteria:

- [ ] A workspace administrator can invite, remove, and bill members without support intervention.
- [ ] A reviewer can comment at a timestamp and the creator can publish a corrected version without sending a new link.
- [ ] Cloud storage, transcoding, AI, and CDN costs are measurable per workspace and bounded by plan limits.

## P2: Enterprise and Expansion

### Enterprise Readiness

- [ ] Add SAML SSO, enforced SSO, and domain verification.
- [ ] Add SCIM provisioning and deprovisioning.
- [ ] Add immutable audit logs and administrator export.
- [ ] Add configurable retention, legal hold, and data residency options.
- [ ] Add enterprise key management and documented encryption boundaries.
- [ ] Add IP restrictions, sharing policies, download controls, and public-link restrictions.
- [ ] Complete SOC 2 readiness, penetration testing, incident response, DPA, and subprocessor documentation.
- [ ] Define support severity levels, response targets, status communication, and enterprise escalation.

### Platform Expansion

- [ ] Validate Windows demand with paid macOS retention and lost-deal evidence before implementation.
- [ ] Implement Windows capture with Windows Graphics Capture and Media Foundation only after validation.
- [ ] Keep project manifests and cloud contracts compatible across platforms.
- [ ] Evaluate mobile companion apps for viewing, comments, and share management before mobile recording.
- [ ] Do not replace the native macOS capture engine solely to share UI code.

## Product and Business Instrumentation

- [ ] Measure permission completion, first recording, first successful export, and first published share.
- [ ] Measure time from recording stop to export and to copied share link.
- [ ] Measure weekly active creators, videos per creator, share rate, and repeat recording rate.
- [ ] Measure trial-to-paid conversion, paid retention, expansion, churn, and failed-payment recovery.
- [ ] Measure support volume, top failure categories, cloud gross margin, and AI cost per paid account.
- [ ] Establish a regular customer interview and cancellation-feedback process.

Initial validation targets, subject to revision after real cohort data:

- [ ] At least 60% of activated users complete a first recording.
- [ ] At least 40% of users who finish a recording produce an export or share.
- [ ] Self-serve trial-to-paid conversion reaches 5% or better.
- [ ] Paid month-three retention reaches 75% or better.
- [ ] Cloud and AI unit economics support a software gross margin of at least 75%.

## Explicitly Deferred

- [ ] Additional generic conversion formats beyond the current supported set.
- [ ] Broad social-video creation features unrelated to product demonstrations.
- [ ] Live streaming and game-streaming workflows.
- [ ] Windows, iOS, and Android capture before macOS paid retention is proven.
- [ ] Enterprise compliance work before the team workflow has active design partners, except baseline security obligations.

## Recommended Milestone Order

1. Paid desktop: editor fidelity, one-click publishing, entitlements, release quality, and updates.
2. Team workflow: workspaces, review comments, versions, seat billing, and reliable cloud playback.
3. Enterprise and expansion: SSO, SCIM, audit, compliance, Windows, and companion clients.
