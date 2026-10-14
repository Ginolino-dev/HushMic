<p align="center">
  <img src="design/MicMinder-icon.png" alt="MicMinder teal microphone and pause icon" width="120">
</p>

# MicMinder

**Music takes a break when your microphone is in use.**

MicMinder is a small macOS menu bar app that automatically pauses your music when the microphone becomes active, then resumes the playback it paused when the microphone becomes idle. It is useful for voice input, calls, and recording while listening to music.

[Setup](#get-started) · [Release notes](CHANGELOG.md) · [Build from source](#build-from-source) · [Report an issue](https://github.com/Ginolino-dev/MicMinder/issues) · [简体中文](README.zh-CN.md)

## What it does

- **Automatic pause and resume:** controls Apple Music and Spotify with explicit player commands.
- **Optional music fades:** aims for a half-second fade-out before pausing and fade-in after playback resumes. Changes the player's volume, not your Mac's system volume.
- **Careful playback restoration:** confirms a pause before owning its resume, and skips resuming if the track or player changes, playback restarts, permission is lost, or automatic control is disabled.
- **Simple setup:** a first-launch welcome window helps connect your player. Playback Permissions remains available from the menu.
- **Menu bar controls:** switch Auto Pause/Resume or Fade Music on and off, view microphone activity, and enable Launch at Login.
- **English and Simplified Chinese:** choose a language or follow your system preference.

## Current version and availability

The current tested local build is **1.0.3**. Apple Music pause/resume and both fades have been manually confirmed; Spotify support is implemented and still needs the same live validation. The version's development verification included 43 passing regression tests.

**There is no published downloadable release yet.** For now, build from source using the instructions below. Local app bundles use ad hoc signing and are not Developer ID signed or notarized. See [release notes](CHANGELOG.md) for the version history and [GitHub Releases](https://github.com/Ginolino-dev/MicMinder/releases) for future published builds.

## Get started

1. Put `MicMinder.app` in **Applications** and open it.
2. In the welcome window, enable **Apple Music** or **Spotify** and allow macOS's Automation request. Spotify requires its desktop app, available from [Spotify's website](https://www.spotify.com/download/mac/).
3. Play some music, then start and stop microphone input. MicMinder should pause and resume that playback.
4. Use the microphone icon in your menu bar to change settings. You can skip setup and return to **Playback Permissions…** later.

If you previously denied permission, the setup window links to **System Settings → Privacy & Security → Automation**. Enable the player under MicMinder there.

### Everyday controls

| Control | What it does |
| --- | --- |
| Auto Pause/Resume | Enables automatic playback control. Turning it off cancels any pending resume; already-paused music stays paused until you press Play. |
| Fade Music | Enables player-volume fades around pause and resume. Your volume changes while paused are respected. |
| Playback Permissions… | Shows player connection status and helps authorize playback control. |
| Launch at Login | Starts the installed app when you log in. |

## Supported behavior and limitations

Microphone detection is system-wide, rather than specific to Codex. Codex voice input has been tested. Other apps that activate the microphone should trigger the same behavior, but individual call and recording apps still need validation.

MicMinder detects **microphone use, not speech**. If a meeting app keeps the microphone active, music can remain paused throughout the call. Muting inside an app does not necessarily release the microphone.

- The installed app controls native players. **Browser players are not supported in this version.** A separate Chrome/YouTube prototype has demonstrated pause/resume, but latency and media identity need further validation.
- App exclusions and website exclusions are not implemented.
- Music that was already paused should remain paused. Changing tracks, restarting playback yourself, or disabling automatic control relinquishes the pending resume.
- Track identifiers must be readable; unsupported streams may be skipped. Brief changes between activity checks may not be observable.
- Fade timing depends on how quickly the player responds to automation commands.

## Privacy and permissions

MicMinder observes microphone activity through CoreAudio. It does **not record microphone audio**. The app has no audio capture pipeline or network telemetry.

Playback control needs **Automation permission for each player**. No Accessibility permission is required, and there is no global media-key test. Authorization is requested through the setup window, not silently by background monitoring.

## Build from source

Running the app requires **macOS 14 or later**. Building also requires the Swift 5.9 or newer toolchain supplied by Xcode or Xcode Command Line Tools.

```bash
git clone https://github.com/Ginolino-dev/MicMinder.git
cd MicMinder
BUILD_CONFIGURATION=release APP_VERSION=1.0.3 APP_BUILD_NUMBER=5 ./script/build_and_run.sh --package
```

Copy `dist/MicMinder.app` to Applications and open that copy. The bundle contains its executable, icon, and language resources, so it runs independently of the source checkout and build caches. Enable Launch at Login from the installed copy.

### Development and verification

```bash
swift test
./script/build_and_run.sh --verify
```

The packaging script defaults to a debug build. Set `BUILD_CONFIGURATION=release` for an optimized build. Its `--logs`, `--telemetry`, and `--debug` modes support local debugging; `--telemetry` streams local diagnostic logs and does not upload them.

The bundle identifier is `dev.ginolino.MicMinder`. Renaming or moving from HushMic may require fresh Automation authorization.

## Credits and license

MicMinder is a fork of [HushMic by location-txl](https://github.com/location-txl/HushMic), with playback restoration fixes, optional permission setup, event-driven microphone monitoring, a standalone release bundle, new branding, and music fades.

Available under the [MIT License](LICENSE).
