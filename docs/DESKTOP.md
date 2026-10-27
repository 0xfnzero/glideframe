# 桌面开发与验证

此仓库同时维护 macOS 原生版和 macOS/Windows Tauri 版。前者安装为 `GlideFrame.app`，后者安装为 `GlideFrame Desktop.app`，可以同时存在。本机验收安装的原生版命名为 `/Applications/GlideFrame Native.app`，用于区分历史同名安装；应用身份仍为 `app.glideframe.studio`。

## 目录

- `Sources/GlideFrameApp`：原生 SwiftUI 界面和录制会话。
- `Sources/GlideFrameKit`：项目、恢复日志、几何和暂停时间轴。
- `Sources/GlideFrameKit/Capture`：`GlideFrameCapture` 模块；两个 macOS 界面共享的编码器、麦克风、摄像头与 AVFoundation 导出。
- `Sources/GlideFrameCaptureBridge`：供 Tauri 加载的进程内 Swift 桥。
- `Sources/GlideFrameTauriHelper`：开发与集成验证 CLI，不参与应用的授权或录制进程。
- `crates/glideframe-recorder`：独立于 Tauri 的 Rust 项目库与平台录制后端，可单独跨平台编译和测试。
- `apps/desktop`：React 界面、Tauri 命令和平台打包配置。

## macOS 原生版

要求 macOS 14+、Xcode、XcodeGen（`brew install xcodegen`）。

```bash
npm install
make mac
make mac-release
make mac-dmg
```

原生 Release 应用：`DerivedDataRelease/Build/Products/Release/GlideFrame.app`。
安装镜像：`dist/release/GlideFrame-v<version>-macOS-<arch>.dmg`。

## Tauri macOS 版

另需 Node.js 22+ 与 Rust stable。

```bash
npm install
npm run dev:desktop
npm run tauri:build -w @glideframe/desktop
# 只构建应用包，供本地测试：
npm run tauri:build -w @glideframe/desktop -- --debug --bundles app
```

macOS 开发命令会先构建 Swift 桥，Windows 开发命令会准备 FFmpeg/ffprobe。

默认 Release 输出位于 `apps/desktop/src-tauri/target/release/bundle`。
macOS 打包脚本先构建并校验签名的 `.app`，再使用 `hdiutil` 生成带 Applications 链接的 DMG，避免 Finder 自动排版等待系统自动化授权。`--bundles app` 只生成应用包；默认或 `--bundles app,dmg` 同时生成镜像。
录制与导出由随应用打包的 Swift 动态库完成；运行时不依赖源码、Swift 或 FFmpeg。
本地打包自动选用已有 Apple Development 签名，也可设置 `APPLE_SIGNING_IDENTITY`。分发签名与公证使用 Tauri 标准 Apple 环境变量。无开发证书的 CI 使用临时签名；不要用每次变化的临时签名验证持久授权。

录屏权限应只授予当前安装路径下的 `GlideFrame` 和 `GlideFrame Desktop`；不需要给单独 helper 授权。
如果旧版本显示已授权却持续失败，先检查是否有多份同名安装和签名身份不一致。确认为旧记录损坏后，可针对 **Tauri 版**执行一次：

```bash
tccutil reset ScreenCapture com.openfnzero.glideframe.desktop
```

然后在系统设置的“隐私与安全性 → 录屏与系统录音”中重新添加 `/Applications/GlideFrame Desktop.app`，退出并重新打开。此操作只用于旧版本授权迁移，不应在每次启动或构建时执行。

## Tauri Windows 版

要求 Windows 10/11、Node.js 22+、Rust MSVC、Visual Studio C++ Build Tools 与 FFmpeg。WebView2 由安装器检查和安装。

```powershell
winget install Gyan.FFmpeg
npm ci
npm run dev:desktop
npm run tauri:build -w @glideframe/desktop
```

打包脚本将真正的 `ffmpeg.exe` 和同目录的 `ffprobe.exe` 一起打包；若 PATH 指向 Chocolatey 启动器，设置 `GLIDEFRAME_FFMPEG_PATH` 指向实际二进制。
安装器输出在 `apps/desktop/src-tauri/target/release/bundle/nsis`。终端用户无需安装 Swift、Rust 或 FFmpeg。

屏幕录制由 GDI/FFmpeg 完成；系统音频使用 WASAPI loopback，麦克风使用 WASAPI 输入。暂停会结束当前屏幕片段，继续时新建片段，停止时合并，避免把暂停时间写入视频。Windows 摄像头当前不支持，界面禁用该功能。

## 自动检查

```bash
make verify
npm run build
cargo check --manifest-path crates/glideframe-recorder/Cargo.toml --target x86_64-pc-windows-msvc
```

Windows 交叉编译检查需先 `rustup target add x86_64-pc-windows-msvc`；它检查录制后端的 Windows 专用代码，不替代 Windows 安装与设备实测。
`.github/workflows/desktop.yml` 为 Windows 构建并静默安装 NSIS 安装器、运行 Rust 测试，并用安装目录内的工具进行真实屏幕录制、暂停、继续、保存和导出 smoke test。托管 runner 的自动测试不验证实体麦克风、扬声器或摄像头。

Windows 本机可重复运行：

```powershell
cargo run --manifest-path apps/desktop/src-tauri/Cargo.toml -- --smoke-recording "$env:TEMP/GlideFrame-smoke"
```

## 人工验收

分别运行两个已安装的 macOS 应用：刷新来源 → 录制显示器与选定区域 → 暂停 → 继续 → 停止 → 播放 → 导出 MP4。再从另一个应用打开同一项目，确认项目时长、音轨和播放正常。更新同一签名的安装包后重复来源刷新，确认权限保持有效。

旧项目兼容范围包括 `sourceID`/`sourceId`、整数秒或带毫秒的 ISO 8601 日期，以及原生平铺目录、Tauri 日期子目录和早期 `GlideFrame/<日期>` 目录。不会移动或删除现有录制文件。恢复日志记录录制进程；另一个客户端刷新项目库时会跳过仍在录制的项目。

## 统一界面与编辑行为

Tauri 与 SwiftUI 使用同一套工作区结构：左侧项目库、顶部录制/导出/格式转换工具栏、中央预览、下方时间线和右侧样式面板。Tauri 使用平台系统字体，跟随浅色/深色外观，支持简体中文与英文；新建录制先打开来源与设备设置弹窗。区域录制可在来源预览中拖动选择，也可精确输入坐标。

两版左下角固定显示“打开全部录制文件夹”，打开 `~/Movies/GlideFrame/Projects`（Windows 使用系统视频目录）。选中项目后，预览上方显示实际视频路径与“打开视频文件夹”，直接在文件管理器中选中原始视频，兼容原生 `Sources` 与 Tauri `media` 目录。录制和导出完成时显示保存位置并提供打开按钮；编辑后的成片通过“导出”生成。

两版都可修改背景、横屏/竖屏/方形比例、留白、圆角和裁剪，并根据点击事件生成自动运镜。Tauri 编辑会自动保存，切换项目或导出前会等待保存完成；保存时合并原始 JSON，保留未参与修改的扩展字段。导出应用裁剪、画框、背景、比例与运镜，原生与 Tauri macOS 共用 AVFoundation 合成，Windows 使用 FFmpeg 合成。运镜效果在导出时应用；预览用于播放与确认画面样式。尚未实现的“移除静音”不再显示为可操作控件。

Tauri 格式转换支持与原生相同的 16 种容器/音频格式及兼容编码、质量、尺寸、帧率、音频选项和批量队列。macOS 通过进程内桥调用与原生相同的 `FFmpegConversionService`，Windows 使用随安装包附带的 FFmpeg。macOS **录制/项目导出不依赖 FFmpeg**；独立格式转换需要 Homebrew FFmpeg，或在应用 Resources/Tools 中预置 FFmpeg/ffprobe，这与原生版一致。

本机界面回归证据保存在忽略目录 `dist/validation/`：两个 macOS 应用已操作录制、暂停/继续、保存、互开项目、样式与裁剪编辑、播放、导出；Tauri 转换队列已实际完成短片转换。Windows 后端交叉编译和平台中立的 FFmpeg 合成回归通过；Windows 安装和设备运行仍由 CI/Windows 环境验证，未宣称本机实测通过。
