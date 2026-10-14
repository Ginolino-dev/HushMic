# MicMinder

**麦克风使用时，音乐自动暂停。**

MicMinder 是一个轻量的 macOS 菜单栏应用。它在麦克风开始使用时暂停音乐，并在麦克风空闲后恢复自己暂停的播放，适合语音输入、通话和录音场景。

[English](README.md) · [版本说明（英文）](CHANGELOG.md) · [报告问题](https://github.com/Ginolino-dev/MicMinder/issues)

## 功能

- 通过明确的播放命令控制 Apple Music 和 Spotify。
- 可选的约半秒音乐淡出和淡入，只调整播放器音量，不改变系统音量。
- 确认暂停后才记录恢复责任；切换曲目、播放器退出、手动恢复播放或关闭自动控制后，取消待执行的恢复。
- 首次启动欢迎窗口，帮助连接播放器；也可稍后从菜单栏打开播放权限。
- 自动暂停/恢复、音乐淡入淡出、开机自启和语言选择。

## 当前版本

当前经过本地测试的版本为 **1.0.3**。Apple Music 的暂停、恢复及淡入淡出已通过手动测试；Spotify 支持已实现，仍需同样的实际验证。开发验证包含 43 项通过的回归测试。

目前**尚未发布可下载的 GitHub 版本**。请按下方说明从源码构建。本地应用使用临时签名，尚未配置 Developer ID 签名和公证。

## 安装与设置

运行需要 macOS 14 或更新版本；构建需要 Xcode 或命令行工具提供的 Swift 5.9 或更新版本。

```bash
git clone https://github.com/Ginolino-dev/MicMinder.git
cd MicMinder
BUILD_CONFIGURATION=release APP_VERSION=1.0.3 APP_BUILD_NUMBER=5 ./script/build_and_run.sh --package
```

将 `dist/MicMinder.app` 复制到 Applications 并打开。欢迎窗口可启用 Apple Music 或 Spotify，并请求 macOS 自动化授权。Spotify 需要从 [官方网站](https://www.spotify.com/download/mac/) 安装桌面应用。

拒绝过授权时，请前往系统设置 → 隐私与安全性 → 自动化，启用 MicMinder 下的对应播放器。可跳过设置，并稍后从菜单栏打开播放权限。

关闭自动暂停/恢复会取消待执行的恢复；已经暂停的音乐保持暂停，直到您手动播放。应用包含可执行文件、图标和语言资源，不依赖开发目录；如需开机自启，请在安装后的副本中启用。

## 隐私与限制

- 通过 CoreAudio 检测麦克风活动，不录制麦克风音频，也不上传遥测数据。
- 播放控制需要各播放器的自动化权限，不需要辅助功能权限。
- 检测的是麦克风使用，而非说话声音。会议应用可能一直占用麦克风；应用内静音不一定释放麦克风。
- Codex 语音输入已测试。其他占用麦克风的应用应触发相同机制，但仍需逐一验证。
- 当前安装版本不控制浏览器播放器，也没有应用或网站排除列表。Chrome/YouTube 浏览器控制仅在独立实验原型中验证。
- 无法读取曲目标识的媒体可能被跳过；两次检查之间的短暂用户操作可能无法观察到。淡入淡出时间取决于播放器响应速度。

## 开发

```bash
swift test
./script/build_and_run.sh --verify
```

`--logs`、`--telemetry` 和 `--debug` 可用于本地调试；`--telemetry` 只读取本地诊断日志，不会上传数据。

## 来源与许可证

MicMinder 基于 [location-txl 的 HushMic](https://github.com/location-txl/HushMic)，加入播放恢复修复、可选权限设置、事件驱动监听、新名称与图标及音乐淡入淡出。

采用 [MIT 许可证](LICENSE)。
