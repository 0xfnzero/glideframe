<div align="center">
  <h1>🎬 GlideFrame</h1>
  <h3><em>本地优先的 macOS 录屏与演示视频工具</em></h3>
</div>

<p align="center">
  <strong>原生 macOS 录屏与编辑应用，通过开放项目格式，让屏幕录制更可信、更容易在本地编辑和导出，适合制作精美的产品演示和教程。</strong>
</p>

<p align="center">
  <a href="https://github.com/0xfnzero/glideframe/releases"><img src="https://img.shields.io/github/v/release/0xfnzero/glideframe" alt="Release"></a>
  <a href="https://github.com/0xfnzero/glideframe/blob/main/LICENSE.md"><img src="https://img.shields.io/badge/license-multiple-blue.svg" alt="License"></a>
  <a href="https://github.com/0xfnzero/glideframe"><img src="https://img.shields.io/github/stars/0xfnzero/glideframe?style=social" alt="GitHub stars"></a>
  <a href="https://github.com/0xfnzero/glideframe/network"><img src="https://img.shields.io/github/forks/0xfnzero/glideframe?style=social" alt="GitHub forks"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-FA7343?style=for-the-badge&amp;logo=swift&amp;logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/macOS%2014%2B-000000?style=for-the-badge&amp;logo=apple&amp;logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/FFmpeg-007808?style=for-the-badge&amp;logo=ffmpeg&amp;logoColor=white" alt="FFmpeg">
</p>

<p align="center">
    <a href="https://github.com/0xfnzero/glideframe/blob/main/README.zh-CN.md">中文</a> |
    <a href="https://github.com/0xfnzero/glideframe/blob/main/README.md">English</a> |
    <a href="https://fnzero.dev/">Website</a> |
    <a href="https://t.me/open_fnzero">Telegram</a> |
    <a href="https://discord.gg/2YzakxfyaC">Discord</a>
</p>

本仓库聚焦本地录屏器、编辑器、项目格式、共享协议和开发文档。

项目仍处于早期阶段。当前仓库包含原生 macOS 应用、Tauri 多平台应用、共享协议、API 原型、Web 工作区和本地开发基础设施。

## 一个仓库，两种桌面应用

- **GlideFrame**：SwiftUI 原生 macOS 应用。`make mac` 启动；`make mac-dmg` 生成安装包。
- **GlideFrame Desktop**：Tauri + React 应用，支持 macOS 和 Windows。`npm run dev:desktop` 开发；`npm run tauri:build -w @glideframe/desktop` 为当前系统打包。
- macOS 两种界面共用 `GlideFrameCapture` 编码、音轨、暂停与导出实现，以及 `GlideFrameKit` 项目格式。Tauri 将 Swift 录制桥打包为应用内动态库，录屏无需源码目录、Swift 工具链或外部 helper 应用。
- 两种应用读取同一个 `~/Movies/GlideFrame/Projects` 项目库，并兼容旧的按日期分类的项目。
- Windows 使用 FFmpeg GDI 录屏与 WASAPI 音频采集；安装包内置 FFmpeg、ffprobe。当前 Windows 摄像头入口禁用。

完整构建、权限修复、测试步骤见 [桌面开发与验证](docs/DESKTOP.md)。旧工程和安装包保存在本机 `.local-backups/`，不纳入 Git 或发布包。

## 项目适合做什么

| 方向 | 覆盖范围 |
| --- | --- |
| 桌面录制 | 使用 SwiftUI、AppKit、ScreenCaptureKit、AVFoundation、VideoToolbox 构建的原生 macOS 应用 |
| 演示视频编辑 | `.svproject` 项目包、非破坏性编辑图、自动缩放数据、画布样式、裁剪模型、导出流程 |
| 录制来源 | 显示器、应用窗口、选定区域、系统音频、麦克风、摄像头、光标和点击事件 |
| 媒体输出 | H.264/HEVC 导出、混合音频、本地项目恢复、基于 FFmpeg 的转换工具 |
| 公开协议 | 共享 schema 和集成接口，保持项目文件可迁移 |
| 扩展方向 | 字幕、转写导入导出、AI adapter 和发布目标的 provider-agnostic 扩展点 |

## 为什么做 GlideFrame

基础录屏已经有 macOS 自带录屏、OBS、会议软件和浏览器工具。GlideFrame 关注的是录制之后的步骤：把粗糙的屏幕录制变成更适合发布的产品演示或教程视频。

适合这个项目的搜索关键词包括 macOS 录屏、ScreenCaptureKit 录屏、SwiftUI 视频编辑器、产品演示录屏、教程视频编辑、本地优先录屏和开放项目格式。

计划中的差异化能力包括：

- 围绕重要点击和区域自动缩放。
- 更干净的鼠标高亮和光标轨迹优化。
- 适合产品讲解的摄像头气泡布局。
- 背景、边框、画面比例和可复用视觉预设。
- 字幕、转写、AI adapter 和发布目标的扩展点。
- 本地优先的项目文件，未来可被第三方集成工作流打开。

## 当前状态

已实现的纵向切片：

- Swift 6 原生 macOS 应用。
- 基于 ScreenCaptureKit 的显示器/窗口捕获。
- 系统音频捕获，以及独立的麦克风和摄像头文件。
- 暂停、继续、停止、恢复日志和项目持久化。
- 版本化 `.svproject` 项目包。
- 指针事件捕获和自动缩放关键帧数据。
- 基于 FFmpeg 的批量媒体转换。
- Fastify API、PostgreSQL-ready 存储、Redis/BullMQ worker 路径、S3 兼容对象存储适配器和 React/Vite 工作区原型。

完整规划见 [开发路线图](docs/ROADMAP.md)。

## 环境要求

- macOS 14+
- 推荐 Apple Silicon Mac
- Xcode 和 Swift 6 工具链
- Node.js 22+
- Docker，用于本地基础设施
- FFmpeg 和 ffprobe，用于本地转换流程

使用 Homebrew 安装 FFmpeg：

```bash
brew install ffmpeg
```

## 快速开始

安装依赖：

```bash
npm install
```

查看可用命令：

```bash
make
```

以真实 `.app` 应用包方式运行 macOS 应用：

```bash
make mac
```

启动 API 和 Web 工作区。这个命令不会启动桌面端：

```bash
make start
```

打开 Web 工作区：

```text
http://127.0.0.1:3000
```

## 开发命令

| 命令 | 说明 |
| --- | --- |
| `make` | 输出所有可用命令 |
| `make mac` | 构建并打开 macOS 应用包 |
| `make mac-build` | 构建 macOS Debug 应用包但不打开 |
| `make mac-swift` | 不通过应用包，直接运行 SwiftPM 可执行文件 |
| `make mac-release` | 构建 macOS Release 应用包 |
| `make mac-dmg` | 构建 macOS Release 应用包并打包 DMG |
| `make start` | 启动 API 和 Web 开发服务 |
| `make api` | 只启动 API 服务 |
| `make web` | 只启动 Web 应用 |
| `make infra` | 启动本地 PostgreSQL、Redis 和对象存储服务 |
| `make migrate` | 运行 API 数据库迁移 |
| `make typecheck` | 检查 TypeScript workspace 类型 |
| `make test` | 运行 API 和 Swift 测试 |
| `make build` | 构建 Web/API workspace |

## macOS 应用开发

如果要测试录屏权限相关流程，请使用仓库中的 Xcode 项目或运行：

```bash
make mac
```

录屏、麦克风和摄像头权限会绑定到应用包身份。`swift run` 适合快速调试，但它在 Dock、签名和权限流程上不会像正常 macOS 应用包一样工作。

只构建桌面端但不打开应用：

```bash
make mac-build
```

打开 Xcode 项目：

```bash
open GlideFrame.xcodeproj
```

在 Xcode 中运行前，请打开 Xcode Settings，添加 Apple ID，然后在 GlideFrame target 的 Signing & Capabilities 里选择开发团队。

## macOS 打包

构建 Release `.app` 应用包：

```bash
make mac-release
```

创建可下载的 DMG：

```bash
make mac-dmg
```

默认输出路径是：

```text
dist/release/GlideFrame-v<version>-macOS-<arch>.dmg
```

`make mac-dmg` 不会覆盖已经存在的 DMG。如果要指定另一个输出路径：

```bash
make mac-dmg DMG=dist/release/GlideFrame-custom.dmg
```

在发布到 GitHub Release 前，建议先运行 `make mac-dmg`，安装生成的 DMG，并确认应用可以打开，图标、语言菜单和权限弹窗都符合预期。

## 云端原型开发

API 原型默认使用本地开发设置和 `.data/storage`。

如需使用本地基础设施：

```bash
make infra
cp apps/api/.env.example apps/api/.env
make migrate
make start
```

数据库、Redis、对象存储、邮件和 AI provider 等配置请写入本地环境变量或 `.env` 文件。不要提交密钥。

## 项目结构

```text
.
├── Sources/GlideFrameApp      原生 macOS 应用
├── Sources/GlideFrameKit      Swift 项目、导出和媒体共享逻辑
├── Sources/GlideFrameChecks   本地验证可执行程序
├── Tests/                     Swift 测试
├── apps/api                   Fastify API 和 worker 代码
├── apps/web                   React/Vite Web 工作区
├── packages/contracts         共享 TypeScript 协议
├── docs                       架构、安全、发布和路线图文档
├── macos                      macOS plist 和 entitlements
├── docker-compose.yml         本地基础设施
└── project.yml                XcodeGen 项目定义
```

## 验证

```bash
npm test
npm run typecheck
npm run build
swift build --target GlideFrameApp
swift test
swift run GlideFrameChecks
```

## 文档

- [开发路线图](docs/ROADMAP.md)
- [架构说明](docs/ARCHITECTURE.md)
- [安全说明](docs/SECURITY.md)
- [发布检查清单](docs/RELEASE_CHECKLIST.md)

## 社区

- Discord: [https://discord.gg/2YzakxfyaC](https://discord.gg/2YzakxfyaC)
- Telegram: [https://t.me/open_fnzero](https://t.me/open_fnzero)

欢迎提交 issue、设计建议、录制问题、本地编辑反馈、项目格式反馈和文档改进。

## 开源协议

本仓库包含 GlideFrame。本仓库之外的代码、服务、资产、文档和配置不由本仓库授权。

- macOS 桌面应用：`MPL-2.0`。
- 共享 contracts、schema、SDK、示例和集成客户端：`Apache-2.0`。
- 仍保留在本仓库中的公开 server 或 web 原型代码：`AGPL-3.0-or-later`。
- 品牌资产、Logo、名称、图标和官网视觉：[商标和品牌政策](TRADEMARKS.md)。

完整协议映射见 [LICENSE.md](LICENSE.md)，选择原因见 [开发路线图](docs/ROADMAP.md#license-direction)。
