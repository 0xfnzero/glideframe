# Contributing to GlideFrame

Thanks for helping improve GlideFrame.

This repository focuses on the local-first recorder, editor, project format, export pipeline, contracts, and documentation.

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
- Do not commit secrets, signing identities, `.env` files, customer data, generated build products, or non-public implementation details.
- Keep public APIs and project-file changes backward-compatible when possible.
- Document any project manifest migration.

## Scope

Changes should fit the local-first recorder, editor, export pipeline, project format, public contracts, or documentation. Do not include secrets, customer data, hosted operations, analytics systems, or customer-specific deployment details.
