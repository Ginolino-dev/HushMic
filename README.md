# HushMic

[中文](README.zh-CN.md)

HushMic is a lightweight macOS menu bar utility that watches microphone activity and keeps your media playback out of the way. When the microphone becomes active, it can pause the currently playing media. When the microphone becomes idle again, it only resumes media playback that HushMic paused.

HushMic is written in Swift as a Swift Package Manager executable. It uses AppKit for the menu bar app shell and permission window, SwiftUI for menu UI, CoreAudio for microphone activity detection, ServiceManagement for launch-at-login registration, and AppleScript/media keys for playback control.

## Why

HushMic was built for Vibe Coding workflows, especially when using tools like Codex or Claude Code with speech-to-text to talk to an AI model while coding. If music or a podcast keeps playing in the background, that audio can leak into the microphone and reduce transcription quality. HushMic removes that friction by pausing playback while the microphone is in use, then restoring only the media playback it paused.

## Screenshots

| Menu | Permissions |
| --- | --- |
| ![HushMic English menu](Screenshot/en_menu.png) | ![HushMic English permission window](Screenshot/en_authorization.png) |

## What It Does

- Shows the current microphone state from the macOS menu bar.
- Detects active input devices through CoreAudio.
- Automatically pauses media when microphone input starts.
- Restores only media playback that HushMic paused.
- Supports Music, Spotify, and iTunes through AppleScript playback state checks.
- Keeps global media keys manual; browser and unknown-player audio is not automatically toggled.
- Provides English, Simplified Chinese, and automatic language selection.
- Can register the packaged app as a macOS login item.

## Requirements

- macOS 14 or later.
- Swift 5.9 toolchain from Xcode or Xcode Command Line Tools.

## Build

Compile the SwiftPM executable:

```bash
swift build
```

Build and package the app into `dist/HushMic.app`:

```bash
./script/build_and_run.sh --package
```

Build, package, and open the app:

```bash
./script/build_and_run.sh
```

Build, package, launch, and verify the process started:

```bash
./script/build_and_run.sh --verify
```

## Install

Download the latest packaged app from [GitHub Releases](https://github.com/location-txl/HushMic/releases).

If macOS says the app is damaged, move `HushMic.app` to `/Applications`, then run:

```bash
xattr -dr com.apple.quarantine /Applications/HushMic.app
```

## Development Commands

```bash
./script/build_and_run.sh --logs
```

Streams logs for the `HushMic` process.

```bash
./script/build_and_run.sh --telemetry
```

Streams logs for subsystem `com.location.HushMic`.

```bash
./script/build_and_run.sh --debug
```

Runs the packaged binary under `lldb`.

## Permissions

Microphone activity monitoring works without granting permissions. Open **Playback Permissions…** from the menu to authorize only the players you want to control. The window can be dismissed with **Done**, **Not Now**, or its close button.

Automatic Music/Spotify/iTunes control uses per-player Automation permission. Accessibility is optional and is only used by **Test Media Key**. Background monitoring never requests Automation consent.

Automatic control sends explicit pause/play commands, confirms the pause, and remembers the player process and current track. It skips resume if the player quit, the track changed, playback was restarted, permission was revoked, another authorized player is playing, or Auto Pause/Resume was switched off. Granting permission or enabling control during microphone use takes effect on the next activity check.

Browser and other unknown-player audio is left alone: a global play/pause key cannot safely target or restore it. The manual media-key button remains available. Track identifiers must be readable; unsupported streams are skipped. Brief user changes between activity checks may not be observable.

## Testing

Run the regression suite with `swift test`. For a packaged-app check:

1. Open Music or Spotify and play a track. In HushMic, open **Playback Permissions…** and authorize that player. Accessibility can remain off.
2. Enable **Auto Pause/Resume**, then start and stop microphone use. The same track should pause and resume.
3. Repeat with music already paused: it should stay paused.
4. While the microphone is active, turn auto-control off, change tracks, or manually resume playback. HushMic should skip its pending resume.
5. Open the permission window and dismiss it without authorizing. Monitoring and the menu should remain available.
6. With auto-control off during microphone use, turn it on. A playing authorized track should pause on the next check.

## Launch at Login

The "Launch at Login" menu item registers the packaged `dist/HushMic.app` bundle as a macOS login item. Use `./script/build_and_run.sh` before testing this flow so the app is running from a real `.app` bundle.

## License

HushMic is available under the [MIT License](LICENSE).
