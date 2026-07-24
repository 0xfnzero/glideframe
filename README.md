# GlideFrame

GlideFrame is a local-first macOS screen recorder for polished product demos. This repository contains the native recorder/editor, the commercial API, and the cloud sharing workspace.

## Implemented Vertical Slice

- Native Swift 6 macOS app using ScreenCaptureKit, AVFoundation, VideoToolbox, SwiftUI, and AppKit.
- Display/window capture, system audio, separate microphone/camera files, pause/resume, pointer event capture, and recovery journals.
- Versioned `.svproject` packages, non-destructive trim graph, click-driven automatic zooms, canvas styles, bilingual UI, and MP4 H.264/HEVC export with mixed audio.
- Fastify API with magic links, signed entitlements, quotas, multipart local/S3 uploads, password/expiry protected shares, analytics, AI jobs, Paddle webhooks, and checkout creation.
- PostgreSQL production store, Redis/BullMQ worker, S3 adapter, Resend mail adapter, Vite/React cloud workspace, and responsive video viewer.

## Local Development

Requirements: macOS 14+, Apple Silicon, Swift 6, Node.js 22+, and full Xcode for running the signed macOS application.

```bash
npm install
npm run dev:api
npm run dev:web
```

Open [http://127.0.0.1:3000](http://127.0.0.1:3000). In development, request a magic link and use the displayed development continuation button.

The API defaults to an in-memory store and `.data/storage`. For production-like infrastructure:

```bash
docker compose up -d
cp apps/api/.env.example apps/api/.env
npm run db:migrate -w @glideframe/api
```

Set `DATABASE_URL`, `REDIS_URL`, AWS credentials, the S3/MinIO fields, Paddle price IDs, and Resend credentials in the process environment. No credential belongs in the repository.

## macOS Application

The Swift Package can compile shared logic with Command Line Tools:

```bash
swift build --target GlideFrameApp
swift run GlideFrameChecks
```

For a permission-aware `.app`, install XcodeGen, generate the project, then open it in full Xcode:

```bash
brew install xcodegen
xcodegen generate
open GlideFrame.xcodeproj
```

Select a development team before running. Screen recording, microphone, and camera permission prompts require the generated app bundle and its `Info.plist`.

## Verification

```bash
npm test
npm run typecheck
npm run build
npm audit
swift build --target GlideFrameApp
swift run GlideFrameChecks
```

See [architecture](docs/ARCHITECTURE.md), [security](docs/SECURITY.md), and the [release checklist](docs/RELEASE_CHECKLIST.md) before production deployment.
