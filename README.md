# GlideFrame

Local-first macOS screen recorder for polished product demos and tutorials.

[English](README.md) | [中文](README.zh-CN.md) | [Discord](https://discord.gg/2YzakxfyaC) | [Telegram](https://t.me/open_fnzero)

GlideFrame is a native macOS recording and editing app. The goal is to make screen recordings easy to trust, edit, and export locally through an open project format.

This repository focuses on the local recorder, editor, project format, shared contracts, and developer documentation.

The project is early. This repository includes a native macOS app, shared contracts, prototype API code, a web workspace, and local development infrastructure.

## What This Project Is For

| Area | Coverage |
| --- | --- |
| Desktop recording | Native macOS app built with SwiftUI, AppKit, ScreenCaptureKit, AVFoundation, and VideoToolbox |
| Demo editing | `.svproject` packages, non-destructive edit graph, automatic zoom data, canvas styles, trimming model, export pipeline |
| Capture sources | Displays, app windows, selected regions, system audio, microphone, camera, cursor and pointer events |
| Media output | H.264/HEVC export, mixed audio, local project recovery, FFmpeg-backed conversion tools |
| Public contracts | Shared schemas and integration surfaces that keep project files portable |
| Extension direction | Provider-agnostic hooks for captions, transcript import/export, AI adapters, and publish targets |

## Why GlideFrame

Basic screen recording is already solved by macOS, OBS, meeting apps, and browser tools. GlideFrame focuses on the step after recording: turning raw screen capture into a polished product demo or tutorial.

Useful search terms for this project include macOS screen recorder, ScreenCaptureKit recorder, SwiftUI video editor, product demo recorder, tutorial video editor, local-first screen capture, and open project format.

Planned differentiators include:

- Automatic zooms around important clicks and regions.
- Clean cursor emphasis and pointer-path polish.
- Camera bubble layouts for product walkthroughs.
- Backgrounds, frames, aspect ratios, and reusable visual presets.
- Extension points for captions, transcripts, AI adapters, and publish targets.
- Local-first projects that can be opened by future integrations.

## Current Status

Implemented vertical slice:

- Native Swift 6 macOS app.
- Display/window capture with ScreenCaptureKit.
- System audio capture plus separate microphone and camera files.
- Pause, resume, stop, recovery journals, and project persistence.
- Versioned `.svproject` packages.
- Pointer event capture and automatic zoom keyframe data.
- Batch media conversion through FFmpeg.
- Prototype Fastify API, PostgreSQL-ready store, Redis/BullMQ worker path, S3-compatible storage adapter, and React/Vite workspace.

See [Roadmap](docs/ROADMAP.md) for the public development plan.

## Requirements

- macOS 14+
- Apple Silicon Mac recommended
- Xcode with Swift 6 toolchain
- Node.js 22+
- Docker, for local infrastructure
- FFmpeg and ffprobe, for local conversion workflows

Install FFmpeg with Homebrew:

```bash
brew install ffmpeg
```

## Quick Start

Clone and install dependencies:

```bash
npm install
```

Show available commands:

```bash
make
```

Run the macOS app as a real `.app` bundle:

```bash
make mac
```

Run the API and web workspace:

```bash
make start
```

Open the web workspace:

```text
http://127.0.0.1:3000
```

## Development Commands

| Command | Description |
| --- | --- |
| `make` | Print all available commands |
| `make mac` | Build and open the signed macOS app bundle |
| `make mac-swift` | Run the SwiftPM executable without an app bundle |
| `make start` | Start API and web dev servers |
| `make api` | Start only the API server |
| `make web` | Start only the web app |
| `make infra` | Start local PostgreSQL, Redis, and object-storage services |
| `make migrate` | Run API database migrations |
| `make typecheck` | Type-check TypeScript workspaces |
| `make test` | Run API and Swift tests |
| `make build` | Build web/API workspaces |

## macOS App Development

For permission-aware screen recording, run the generated Xcode project or use:

```bash
make mac
```

Screen recording, microphone, and camera permissions are tied to the app bundle identity. `swift run` is useful for quick debugging, but it does not behave like a normal macOS app bundle in Dock, signing, and permission flows.

If the project needs to be regenerated:

```bash
brew install xcodegen
xcodegen generate
open GlideFrame.xcodeproj
```

Before running from Xcode, open Xcode Settings, add an Apple ID, then select a development team under the GlideFrame target's Signing & Capabilities tab.

## Prototype Cloud Development

The prototype API defaults to local development settings and `.data/storage`.

For infrastructure-backed development:

```bash
make infra
cp apps/api/.env.example apps/api/.env
make migrate
make start
```

Set environment variables such as database URL, Redis URL, object storage settings, email settings, and AI provider settings in your local environment or `.env` file. Do not commit secrets.

## Project Structure

```text
.
├── Sources/GlideFrameApp      Native macOS app
├── Sources/GlideFrameKit      Shared Swift project, export, and media logic
├── Sources/GlideFrameChecks   Local verification executable
├── Tests/                     Swift tests
├── apps/api                   Fastify API and worker code
├── apps/web                   React/Vite web workspace
├── packages/contracts         Shared TypeScript contracts
├── docs                       Architecture, security, release, and roadmap docs
├── macos                      macOS plist and entitlements
├── docker-compose.yml         Local infrastructure
└── project.yml                XcodeGen project definition
```

## Verification

```bash
npm test
npm run typecheck
npm run build
swift build --target GlideFrameApp
swift test
swift run GlideFrameChecks
```

## Documentation

- [Roadmap](docs/ROADMAP.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Security](docs/SECURITY.md)
- [Release Checklist](docs/RELEASE_CHECKLIST.md)

## Community

- Discord: [https://discord.gg/2YzakxfyaC](https://discord.gg/2YzakxfyaC)
- Telegram: [https://t.me/open_fnzero](https://t.me/open_fnzero)

Issues, design notes, capture bug reports, local editing feedback, and project-format feedback are welcome.

## License

This repository contains GlideFrame. Code, services, assets, documentation, and configuration outside this repository are not licensed by this repository.

- macOS desktop application: `MPL-2.0`.
- Shared contracts, schemas, SDKs, examples, and integration clients: `Apache-2.0`.
- Public server or web prototypes that remain in this repository: `AGPL-3.0-or-later`.
- Brand assets, logos, names, icons, and website identity: [trademark and brand policy](TRADEMARKS.md).

See [LICENSE.md](LICENSE.md) for the full license map and [Roadmap](docs/ROADMAP.md#license-direction) for the rationale.
