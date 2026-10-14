# Playback notification investigation — 14 October 2026

Read-only investigation against installed Apple Music and Spotify on macOS 27.0.1. MicMinder 1.1.5 remained installed and unchanged. The user tested Play, Pause, Play, Next track and Pause in each player without microphone input.

Observed distributed notifications:

| Player | Notification | Observed payload |
| --- | --- | --- |
| Apple Music | `com.apple.Music.playerInfo` | Playing/Paused, descriptive metadata, duration; no stable track identifier in these samples |
| Apple Music compatibility events | `com.apple.iTunes.playerInfo` | Duplicates of the Music events in this test |
| Spotify | `com.spotify.client.PlaybackStateChanged` | Playing/Paused with Track ID; Stopped events sometimes contain only state |

The listener received 15 Music events, 15 matching iTunes-named compatibility events and 8 Spotify events. This demonstrates that both players broadcast changes; counts do not establish delivery completeness or a latency guarantee. Only field names, playback state and hashed identifiers were retained, not song titles or audio.

Apple documents distributed notification latency as unbounded and states that notifications may be dropped when the server queue fills. Payloads are untrusted. See https://developer.apple.com/documentation/Foundation/DistributedNotificationCenter?language=objc . No official guarantee for these player-specific event contracts was established.

## Decision

Do not replace authoritative playback/identity checks with notification payloads alone. A hybrid could use events as invalidation hints, verify state and identity directly, recheck immediately before resume, and retain periodic fallback checks. Missing notifications remain relevant: reducing fallback frequency can miss user play/pause or track-away-and-back changes that the existing quarter-second checks might observe. This is a reliability tradeoff, not a proven equivalent optimization.

Before changing polling cadence, investigate reducing the cost of each existing query (for example reusing compiled, stateless AppleScript commands without caching playback or permission results). That approach can preserve current observation frequency. That follow-up was implemented in 1.1.6; see [measured CPU results](PERFORMANCE.md).

Further notification testing would need rapid play/pause, track-away-and-back while paused, player quit/relaunch, sleep/wake, missing/delayed/duplicate notifications, Spotify Connect, and permission changes. No notification-driven control code was added to the shipping app in this investigation.
