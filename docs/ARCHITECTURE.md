# Architecture

## Data Flow

ScreenCaptureKit writes the screen and system audio into a fragmented movie while AVFoundation writes optional microphone and camera sources. Pointer events and recovery state are journaled beside the media. Editing changes only the versioned `manifest.json`; source media is immutable.

Export builds an AVComposition from the edit graph, applies click-driven transforms through AVVideoComposition, mixes system and microphone audio, and uses hardware-backed H.264 or HEVC export. Cloud upload is always an explicit project action.

Format conversion is a separate batch workflow backed by FFmpeg/ffprobe. `GlideFrameKit` owns the validated container/codec matrix, command construction, process lifecycle, progress parsing, and cancellation. The app owns file selection, queue state, output naming, and Finder integration. Development builds discover Homebrew; release builds should use a legally reviewed FFmpeg toolchain bundled under `Contents/Resources/Tools`.

The API issues short-lived access tokens, applies community usage guards, presigns multipart object uploads, and stores only metadata in PostgreSQL. Public shares use high-entropy tokens plus optional scrypt passwords and expiry. AI work is queued in Redis; a provider receives a one-hour S3 URL rather than permanent object credentials.

## Cross-platform Direction

The first release is native Swift because macOS capture quality depends on ScreenCaptureKit, AVFoundation, Metal, permissions, and hardware encoders. Flutter can later provide a shared library/editor/account UI, but each OS still requires a native media plugin:

- macOS: ScreenCaptureKit.
- iOS: ReplayKit, with system restrictions on capturing other applications.
- Windows: Windows Graphics Capture and Media Foundation.
- Android: MediaProjection and MediaCodec.

If Windows or mobile demand is validated, keep `ProjectManifest` and the cloud contracts stable, move reusable timeline/render math into Rust, and expose it through Flutter FFI. Do not replace the proven macOS capture engine merely to share UI code.

## Service Boundaries

- `GlideFrameKit`: versioned project model, timeline math, automatic polish, persistence.
- `GlideFrameApp`: capture, editor UI, export, permissions, application lifecycle.
- `@glideframe/contracts`: validated public request/response inputs.
- `@glideframe/api`: identity, community usage guards, media metadata, share access, and AI extension hooks.
- `@glideframe/web`: authenticated upload workspace and public playback experience.
