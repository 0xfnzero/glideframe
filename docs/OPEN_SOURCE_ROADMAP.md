# Community Edition Roadmap

Status: planned, not committed to a release date.

GlideFrame Community Edition is the public foundation for a trustworthy local-first macOS screen recorder and demo editor. It should be useful on its own, easy to build, and safe for contributors to inspect and extend.

The Community Edition is not planned as the full product surface for AI, hosted cloud, team collaboration, billing, or enterprise administration. Those product layers are outside this repository's public scope.

## Product Boundary

The public repository should focus on:

- Native macOS recording and local editing.
- Portable `.svproject` project files.
- Local export and recovery reliability.
- Basic visual polish for product demos and tutorials.
- Public contracts, file-format documentation, and extension points.
- Developer documentation, tests, and reproducible local builds.

The public repository should not become responsible for:

- Hosted cloud operations.
- Account billing, entitlements, payment flows, or plan logic.
- Proprietary AI orchestration, cost controls, or provider routing.
- Team administration, enterprise policy, SSO, SCIM, audit, or compliance workflows.
- Private analytics, growth experiments, or App Store commercial packaging.

## License Direction

Current public repository licensing strategy:

- macOS desktop source and Swift shared logic: `MPL-2.0`.
- Shared contracts, schemas, SDK examples, integration surfaces, and documentation: `Apache-2.0`.
- Any self-hostable public server or web prototype kept in this repository: `AGPL-3.0-or-later`.
- Brand assets, logos, names, icons, and website identity: separate trademark and brand policy in `TRADEMARKS.md`.

Rationale:

- `MPL-2.0` is a practical fit for a community desktop core because modifications to covered files stay open while commercial extensions can live in separate files or repositories.
- `Apache-2.0` is a good fit for schemas, examples, and SDK-facing material because broad reuse helps integrations.
- `AGPL-3.0-or-later` should only be used for public network-service code that is intentionally offered as self-hostable community infrastructure.
- Brand assets should be handled separately so forks can exist without confusing users about what is official.

Before public launch, review dependency licenses, contributor expectations, contributor license policy, App Store distribution needs, and trademark rules.

## Phase 1: Public Core Cleanup

- [ ] Decide the final public repository name and directory layout.
- [ ] Keep commercial-only code, secrets, payment flows, hosted operations, and private roadmap material out of this repository.
- [ ] Keep public build instructions working after the split.
- [ ] Add `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `NOTICE`, issue templates, and a public security policy.
- [ ] Add a contributor policy that preserves the ability to ship a separate commercial edition.
- [ ] Add a clear feature comparison document without mentioning private implementation details.

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
- [ ] Keep project files portable across community and commercial editions.

## Phase 4: Community Editor

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

## Phase 6: Public Extension Points

- [ ] Document extension points for captions, transcript import/export, AI provider adapters, and publish targets.
- [ ] Keep AI and cloud integration interfaces provider-agnostic.
- [ ] Add examples that demonstrate local or self-managed integrations without bundling hosted commercial logic.
- [ ] Add stable TypeScript contracts for project metadata and share/upload integration experiments.

## Community Success Criteria

- [ ] A developer can build and run the desktop app from source in under 30 minutes.
- [ ] A user can record, edit, and export locally without creating an account.
- [ ] A project created in Community Edition can be opened by the commercial edition.
- [ ] Security-sensitive local recording and export behavior is auditable from source.
- [ ] Contributors can improve the local recorder without needing private infrastructure.
