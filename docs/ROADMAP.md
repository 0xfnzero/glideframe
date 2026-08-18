# Roadmap

Status: planned, not committed to a release date.

GlideFrame is a local-first macOS screen recorder and demo editor for product demos, tutorials, support videos, and team knowledge sharing. This roadmap tracks the public development plan for the repository.

The project should be useful without an account, transparent about what happens to recordings, and easy for contributors to build, inspect, and extend.

## Principles

- Keep recording and editing trustworthy by making the local capture path auditable.
- Keep user projects portable through an open `.svproject` format.
- Keep raw recordings local unless the user explicitly exports, uploads, or starts an integration workflow.
- Prefer open standards, documented APIs, and migration-friendly storage layouts.
- Keep optional integrations provider-agnostic so users can choose their own tools.
- Keep public builds reproducible and contributor setup practical.

## License Direction

Current public repository licensing strategy:

- macOS desktop source and Swift shared logic: `MPL-2.0`.
- Shared contracts, schemas, SDK examples, integration surfaces, and documentation: `Apache-2.0`.
- Any self-hostable public server or web prototype kept in this repository: `AGPL-3.0-or-later`.
- Brand assets, logos, names, icons, and website identity: separate trademark and brand policy in `TRADEMARKS.md`.

Rationale:

- `MPL-2.0` is a practical fit for the macOS client because modifications to covered files stay open while allowing broad distribution flexibility.
- `Apache-2.0` is a good fit for schemas, examples, and SDK-facing material because broad reuse helps integrations.
- `AGPL-3.0-or-later` should only be used for public network-service code that is intentionally offered as self-hostable community infrastructure.
- Brand assets should be handled separately so forks can exist without confusing users about what is official.

Before public launch, review dependency licenses, contributor expectations, contributor license policy, App Store distribution needs, and trademark rules.

## Phase 1: Public Project Readiness

- [ ] Keep public build instructions reliable on a fresh clone.
- [ ] Add `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `NOTICE`, issue templates, and a public security policy.
- [ ] Add a clear privacy note explaining what stays local and what is sent to configured services.
- [ ] Add architecture diagrams for capture, project files, export, upload experiments, and sharing.
- [ ] Add reproducible sample projects and demo recordings.
- [ ] Add release signing, checksums, and provenance metadata for official builds.

## Phase 2: Local Recording Foundation

- [ ] Stabilize display, window, selected-region, system-audio, microphone, camera, and cursor capture.
- [ ] Improve permission handling, first-run guidance, and recovery from denied permissions.
- [ ] Make recording start, pause, resume, stop, and failure states reliable and testable.
- [ ] Add automated tests for capture geometry, interrupted recordings, project persistence, and recovery journals.
- [ ] Add compatibility checks for Retina scaling, multi-display layouts, sleep/wake, disk-full states, and audio-device changes.

## Phase 3: Portable Project Format

- [ ] Stabilize the `.svproject` package layout.
- [ ] Document manifest schema, media track layout, recovery files, and versioning rules.
- [ ] Add migration tests for older project versions.
- [ ] Add sample projects that can be used for regression testing.
- [ ] Keep project files portable across local workflows and future integrations.

## Phase 4: Editor and Demo Polish

- [ ] Add reliable local preview for recorded screen, camera, microphone, system audio, and cursor layers.
- [ ] Support trim, split, delete, undo, redo, timeline scrubbing, and simple clip reordering.
- [ ] Improve automatic zoom detection and allow manual zoom adjustment.
- [ ] Add cursor visibility, click emphasis, and pointer path controls.
- [ ] Add basic camera bubble layout controls.
- [ ] Add basic canvas styles, backgrounds, padding, frame, and aspect ratio presets.
- [ ] Add blur and redaction regions for sensitive on-screen content.

## Phase 5: Local Export Quality

- [ ] Make preview and export match for canvas, zoom, camera, captions, cursor, audio, and timing.
- [ ] Add robust export progress, cancellation, resumable failure handling, and compatibility checks.
- [ ] Improve H.264/HEVC export stability and audio/video synchronization.
- [ ] Keep FFmpeg-backed conversion tools optional and clearly documented.
- [ ] Add release checks for one-hour recordings and exports.

## Phase 6: Extension Points

- [ ] Document extension points for captions, transcript import/export, AI provider adapters, and publish targets.
- [ ] Keep AI and cloud integration interfaces provider-agnostic.
- [ ] Add examples that demonstrate local or self-managed integrations.
- [ ] Add stable TypeScript contracts for project metadata and share/upload integration experiments.

## Success Criteria

- [ ] A developer can build and run the desktop app from source in under 30 minutes.
- [ ] A user can record, edit, and export locally without creating an account.
- [ ] Project files remain portable and migration-friendly.
- [ ] Security-sensitive local recording and export behavior is auditable from source.
- [ ] Contributors can improve the local recorder without needing hosted infrastructure.
