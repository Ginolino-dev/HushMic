# MicMinder

[English](README.md)

MicMinder 是一个轻量的 macOS 菜单栏工具，用来监听麦克风是否正在被使用，并在你开始说话、开会、录音时处理媒体播放。麦克风开始使用时，它可以暂停当前正在播放的媒体；麦克风停止使用后，它只恢复自己暂停过的媒体播放。

MicMinder 使用 Swift 编写，是一个 Swift Package Manager 可执行目标。它使用 AppKit 搭建菜单栏应用外壳和权限窗口，使用 SwiftUI 构建菜单界面，使用 CoreAudio 监听麦克风状态，使用 ServiceManagement 注册开机自启，并通过 AppleScript 或媒体键控制播放。

## 为什么做这个工具

MicMinder 的使用场景来自 Vibe Coding：在使用 Codex、Claude Code 这类工具写代码时，经常会通过麦克风做语音转文字，直接和模型交流。如果这时音乐或播客还在播放，播放器声音会干扰麦克风收音，也会影响转写质量。MicMinder 的目标就是把这一步自动化，只在麦克风使用期间暂停播放，并在麦克风空闲后恢复自己暂停过的媒体播放。

## 截图

| 菜单 | 权限 |
| --- | --- |
| ![MicMinder 中文菜单](Screenshot/zh_menu.png) | ![MicMinder 中文权限窗口](Screenshot/zh_authorization.png) |

## 它能做什么

- 在 macOS 菜单栏显示当前麦克风状态。
- 通过 CoreAudio 检测正在使用的输入设备。
- 麦克风开始输入时自动暂停媒体播放。
- 麦克风空闲后，只恢复 MicMinder 自己暂停过的媒体播放。
- 通过 AppleScript 读取并控制 Music、Spotify、iTunes 的播放状态。
- 全局媒体键仅供手动测试，不自动切换浏览器或未知播放器。
- 支持英文、简体中文和自动语言选择。
- 可以把打包后的应用注册为 macOS 登录项。

## 环境要求

- macOS 14 或更高版本。
- Swift 5.9 工具链，可通过 Xcode 或 Xcode Command Line Tools 安装。

## 构建

编译 SwiftPM 可执行目标：

```bash
swift build
```

构建并打包为 `dist/MicMinder.app`：

```bash
./script/build_and_run.sh --package
```

构建、打包并打开应用：

```bash
./script/build_and_run.sh
```

构建、打包、启动，并确认进程已运行：

```bash
./script/build_and_run.sh --verify
```

## 安装

构建优化后的独立发布版：

```bash
BUILD_CONFIGURATION=release APP_VERSION=1.0.0 ./script/build_and_run.sh --package
```

将 `dist/MicMinder.app` 复制到 `/Applications`，然后打开该副本。
应用包含可执行文件和语言资源，不依赖开发目录或编译缓存。
如需开机自启，请在安装后的副本中启用。

本分支使用包标识 `dev.ginolino.MicMinder`。从 HushMic 迁移后，macOS 可能需要重新授权自动化权限。
本地构建采用临时签名；公开发布需要单独配置开发者签名和公证。

## 开发命令

```bash
./script/build_and_run.sh --logs
```

查看 `MicMinder` 进程日志。

```bash
./script/build_and_run.sh --telemetry
```

查看 subsystem 为 `dev.ginolino.MicMinder` 的日志。

```bash
./script/build_and_run.sh --debug
```

使用 `lldb` 运行打包后的二进制文件。

## 权限说明

监听麦克风活动无需授权。可从菜单打开“播放权限…”并仅授权需要控制的播放器。可随时通过“完成”、“暂不授权”或关闭按钮退出权限窗口。

自动控制 Music、Spotify 或 iTunes 仅需对应播放器的自动化权限。辅助功能是可选权限，仅用于“测试媒体键”。后台监听不会请求自动化授权。

自动控制使用明确的暂停和播放命令，确认暂停后记录播放器进程和曲目。如果播放器退出、曲目更改、用户恢复播放、权限撤销、其他已授权播放器正在播放，或关闭自动控制，则跳过恢复。麦克风使用期间开启自动控制或完成授权将在下一次检测生效。

浏览器和未知播放器不会自动切换，因为全局媒体键无法可靠地指定和恢复原播放器。无法读取曲目标识的流媒体也会跳过。两次检测之间的短暂用户操作可能无法观察到。

## 开机自启

菜单里的”开机自启”会把打包后的 `dist/MicMinder.app` 注册为 macOS 登录项。测试这个流程前请先运行 `./script/build_and_run.sh`，确保应用是从真实的 `.app` bundle 启动的。

## 许可证

MicMinder 使用 [MIT 许可证](LICENSE) 开源。
