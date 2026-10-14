# Release notes

## 1.1.0

- Custom music-note and pause symbol for the menu bar and charcoal app icon.
- Compact native panel with switches for automatic control, fades and login launch.
- Inline Apple Music and Spotify switches, with persistent per-player control.
- Redesigned welcome screen using the same player controls.
- Player disable restores an owned fade before relinquishing playback control.
- Spotify volume acknowledgement fix validated manually alongside Apple Music.
- Clarified microphone-triggered call use cases and browser-support limitations.


These notes describe the local development builds. No downloadable GitHub release has been published yet. Browser-control experiments are separate from the installed MicMinder app.

## 1.0.3 — 14 October 2026

### Fixed

- Fade-in waits for confirmed playback before starting its half-second timer. A slow Apple Music Play command no longer consumes the fade duration.
- Delayed playback confirmation no longer cancels fade-in immediately.
- Playback and volume callbacks cannot revive a canceled fade or overwrite queued microphone changes with stale timer updates.
- Ending microphone input during a volume write restores the player's original volume safely.

### Verified

- Apple Music pause/resume and fade-out/fade-in confirmed in manual voice-input testing.
- 43 regression tests passed during development verification.

## 1.0.2 — 14 October 2026

### Added

- Optional Fade Music menu control, enabled by default.
- Player-volume fade-out before pausing and fade-in when resuming.
- Restoration of normal player volume while paused, with respect for volume changes made during the pause.
- Recovery of interrupted volume changes when Automation access returns while the app is running.

### Improved

- Playback Permissions window activation and foreground ordering.
- Cleanup when automatic control is disabled or the app quits.

## 1.0.1 — 14 October 2026

### Added

- First-launch welcome flow for connecting Apple Music and Spotify.
- Connected, denied, and unavailable-player feedback, with a link to Automation settings when needed.

### Removed

- Manual Test Media Key control and its Accessibility permission dependency.
- Empty Settings window and unused SwiftUI menu view.

## 1.0.0 — 14 October 2026

### Added

- MicMinder name, teal microphone-and-pause icon, and updated bundle identity.
- Optimized standalone macOS app bundle that can run from Applications independently of the development folder.

### Inherited improvements from this fork

- Confirmed pause ownership and conservative playback restoration.
- Support for delayed Apple Music pause confirmation.
- Optional, dismissible permission setup.
- Event-driven CoreAudio monitoring and fewer unnecessary UI updates and background scans.

## Experimental work

A separate prototype has demonstrated explicit YouTube pause and resume in Chrome without a browser extension. Browser playback control, app exclusions, and website exclusions are **not part of the current installed app**. Prototype results do not establish support for every browser, website, or tab-switching scenario.
