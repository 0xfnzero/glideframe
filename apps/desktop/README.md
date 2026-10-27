# GlideFrame Desktop

Tauri 2 client for macOS and Windows, maintained with the native SwiftUI macOS app in this repository.

- React/TypeScript UI and Tauri commands: this directory.
- Shared session, project and platform backend: `../../crates/glideframe-recorder`.
- macOS: bundled in-process Swift capture bridge using shared ScreenCaptureKit/AVFoundation code. Only the installed main app needs screen recording permission.
- Windows: bundled FFmpeg/ffprobe for GDI screen capture and export, WASAPI loopback/microphone audio. Camera capture is disabled.
- Both clients read the same `.svproject` format and project library.

From the repository root:

```bash
npm ci
npm run dev:desktop
npm run tauri:build -w @glideframe/desktop
make desktop-rust-test
```

For permission validation on macOS, use the signed installed application produced by the packaging command. Terminal development mode can inherit Terminal permissions and does not establish that an installed app is authorized.

See [desktop build, permissions and validation](../../docs/DESKTOP.md). Do not repeatedly reset permissions after rebuilding; use a stable signing identity and bundle identifier.
