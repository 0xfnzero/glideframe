# Architecture

## Data Flow

ScreenCaptureKit writes the screen and system audio into a fragmented movie while AVFoundation writes optional microphone and camera sources. Pointer events and recovery state are journaled beside the media. Editing changes only the versioned `manifest.json`; source media is immutable.

Export builds an AVComposition from the edit graph, applies click-driven transforms through AVVideoComposition, mixes system and microphone audio, and uses hardware-backed H.264 or HEVC export. Cloud upload is always an explicit project action.

Format conversion is a separate batch workflow backed by FFmpeg/ffprobe. `GlideFrameKit` owns the validated container/codec matrix, command construction, process lifecycle, progress parsing, and cancellation. The app owns file selection, queue state, output naming, and Finder integration. Development builds discover Homebrew; release builds should use a legally reviewed FFmpeg toolchain bundled under `Contents/Resources/Tools`.

The API issues short-lived access tokens, applies community usage guards, presigns multipart object uploads, and stores only metadata in PostgreSQL. Public shares use high-entropy tokens plus optional scrypt passwords and expiry. AI work is queued in Redis; a provider receives a one-hour S3 URL rather than permanent object credentials.

## Desktop applications

The repository ships a native SwiftUI macOS app and a Tauri/React app for macOS and Windows. Both macOS interfaces use `GlideFrameCapture` for encoding, audio, pause/resume and AVFoundation export, and `GlideFrameKit` for the open project format. Tauri loads `GlideFrameCaptureBridge` in its main process so screen capture requests and recording use the same macOS application identity.

The independent `glideframe-recorder` Rust crate owns Tauri sessions, project persistence and platform dispatch. On Windows it records screen segments with FFmpeg GDI, records audio with WASAPI, omits paused intervals, and combines segments at stop. The installer includes FFmpeg and ffprobe. Windows camera capture is currently unavailable.

Both applications list native flat project directories and Tauri date-grouped directories under `~/Movies/GlideFrame`. Earlier manifest key and timestamp variants remain readable. See [desktop development](DESKTOP.md).

## Service Boundaries

- `GlideFrameKit`: versioned project model, timeline math, automatic polish, persistence.
- `GlideFrameCapture`: shared macOS encoding, auxiliary audio/camera capture and export.
- `GlideFrameApp`: native editor UI, recording sessions, permissions, application lifecycle.
- `GlideFrameCaptureBridge`: in-process C ABI for the Tauri macOS backend.
- `glideframe-recorder`: Rust sessions, project storage, platform recording and export.
- `@glideframe/desktop`: Tauri/React desktop application.
- `@glideframe/contracts`: validated public request/response inputs.
- `@glideframe/api`: identity, community usage guards, media metadata, share access, and AI extension hooks.
- `@glideframe/web`: authenticated upload workspace and public playback experience.
