# GlideFrame

本地优先的 macOS 录屏与演示视频工具社区版，用于产品演示和教程制作。

[English](README.md) | [中文](README.zh-CN.md) | [开发路线图](docs/OPEN_SOURCE_ROADMAP.md) | [仓库策略](docs/REPOSITORY_STRATEGY.md) | [Discord](https://discord.gg/2YzakxfyaC) | [Telegram](https://t.me/open_fnzero)

GlideFrame Community Edition 是原生 macOS 录屏与编辑应用的公开基础。目标是通过开放项目格式，让屏幕录制更可信、更容易本地编辑和导出。

GlideFrame 采用 open-core 模式。公开仓库聚焦社区版录屏器、本地编辑器、项目格式、共享协议和开发文档。托管 AI、云分享、团队协作、商业发行和企业控制能力规划放在独立的闭源商业仓库。

项目仍处于早期阶段。当前仓库里仍保留了 API 和 Web 工作区原型代码，后续会按公开/闭源仓库边界继续拆分。

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
- 本地优先的项目文件，未来可被商业版和第三方集成工作流打开。

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

完整规划见 [社区版开发路线图](docs/OPEN_SOURCE_ROADMAP.md) 和 [仓库策略](docs/REPOSITORY_STRATEGY.md)。

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

启动 API 和 Web 工作区：

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
| `make mac-swift` | 不通过应用包，直接运行 SwiftPM 可执行文件 |
| `make start` | 启动 API 和 Web 开发服务 |
| `make api` | 只启动 API 服务 |
| `make web` | 只启动 Web 应用 |
| `make infra` | 启动本地 PostgreSQL、Redis 和对象存储服务 |
| `make migrate` | 运行 API 数据库迁移 |
| `make typecheck` | 检查 TypeScript workspace 类型 |
| `make test` | 运行 API 和 Swift 测试 |
| `make build` | 构建 Web/API workspace |

## macOS 应用开发

如果要测试录屏权限相关流程，请使用 Xcode 项目或运行：

```bash
make mac
```

录屏、麦克风和摄像头权限会绑定到应用包身份。`swift run` 适合快速调试，但它在 Dock、签名和权限流程上不会像正常 macOS 应用包一样工作。

如果需要重新生成 Xcode 项目：

```bash
brew install xcodegen
xcodegen generate
open GlideFrame.xcodeproj
```

在 Xcode 中运行前，请打开 Xcode Settings，添加 Apple ID，然后在 GlideFrame target 的 Signing & Capabilities 里选择开发团队。

## 云端原型开发

API 原型默认使用本地开发设置和 `.data/storage`。托管云、AI 编排、权益、团队和企业能力规划放在闭源商业仓库。

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

- [社区版开发路线图](docs/OPEN_SOURCE_ROADMAP.md)
- [仓库策略](docs/REPOSITORY_STRATEGY.md)
- [架构说明](docs/ARCHITECTURE.md)
- [安全说明](docs/SECURITY.md)
- [发布检查清单](docs/RELEASE_CHECKLIST.md)

## 社区

- Discord: [https://discord.gg/2YzakxfyaC](https://discord.gg/2YzakxfyaC)
- Telegram: [https://t.me/open_fnzero](https://t.me/open_fnzero)

欢迎提交 issue、设计建议、录制问题、本地编辑反馈、项目格式反馈和文档改进。

## 开源协议

本仓库是 GlideFrame 的公开社区版仓库。GlideFrame 也规划一个独立的闭源商业仓库，该仓库不由本仓库授权。

- macOS 桌面应用：`MPL-2.0`。
- 共享 contracts、schema、SDK、示例和集成客户端：`Apache-2.0`。
- 仍保留在本仓库中的公开 server 或 web 原型代码：`AGPL-3.0-or-later`。
- 品牌资产、Logo、名称、图标和官网视觉：[商标和品牌政策](TRADEMARKS.md)。

完整协议映射见 [LICENSE.md](LICENSE.md)，选择原因见 [社区版开发路线图](docs/OPEN_SOURCE_ROADMAP.md#license-direction)。
