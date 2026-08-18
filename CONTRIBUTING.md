# Contributing to GlideFrame Community Edition

Thanks for helping improve GlideFrame Community Edition.

This repository focuses on the public local-first recorder, editor, project format, export pipeline, contracts, and documentation. Commercial-only features such as hosted AI, account billing, proprietary cloud operations, team administration, and enterprise controls are planned for a separate private repository.

## Good First Contribution Areas

- macOS recording reliability.
- ScreenCaptureKit permission and source-selection bugs.
- `.svproject` project-file compatibility.
- Local editor usability.
- Export stability and compatibility.
- Documentation, examples, and test coverage.

## Development Setup

Install the project dependencies:

```bash
npm install
```

Show available commands:

```bash
make
```

Run the macOS app as an app bundle:

```bash
make mac
```

Run checks before opening a pull request:

```bash
npm run typecheck
npm test
npm run build
swift test
swift run GlideFrameChecks
```

## Pull Request Guidelines

- Keep changes scoped to one behavior or one documentation area.
- Include tests when changing recording, project persistence, export, API contracts, or compatibility behavior.
- Do not commit secrets, signing identities, `.env` files, customer data, generated build products, or private commercial implementation details.
- Keep public APIs and project-file changes backward-compatible when possible.
- Document any project manifest migration.

## Public and Commercial Boundaries

Community fixes that improve shared behavior should happen in this repository. Features that depend on hosted operations, private analytics, payment providers, commercial entitlement logic, or customer-specific deployment should stay out of this repository.
