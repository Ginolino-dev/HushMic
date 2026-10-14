# Local CPU comparison — 14 October 2026

Compared optimized release builds 1.1.4, 1.1.5 and 1.1.6 on the same Apple Silicon Mac, running macOS 27.0.1, with Apple Music. The menu bar popover was closed. Music was playing before microphone activation and remained paused during each long microphone session.

CPU was calculated from process CPU-time deltas sampled approximately once per second, divided by elapsed monotonic time. Percentages refer to one CPU core. These are local measurements, not a cross-device benchmark.

| Steady microphone-active interval | Before | After |
| --- | ---: | ---: |
| Samples, approximately one second each | 81 | 56 |
| Mean CPU | 6.72% | 4.16% |
| Median CPU | 6.91% | 3.96% |
| Maximum sampled CPU | 8.91% | 4.96% |

The steady-state mean decreased by about 38%. Fade transitions were excluded from these intervals. The process returned to 0% sampled CPU after the optimized test. Independent sessions and background system load limit the precision of this comparison.

A stack sample of 1.1.4 identified repeated Automation permission checks and separate AppleScript state/identity queries in the quarter-second pause-ownership check. Version 1.1.5 combines those reads into one authorized script execution. It does not cache permission or playback state, lengthen the polling interval, or change fade/resume decisions.

Validation: 50 automated tests pass, including a regression that failed on the previous separate-query implementation. The optimized Apple Music long-session logs confirmed retained pause ownership, successful resume and completed fade-in. The user also confirmed fade-out, pause, resume and original-volume restoration in both Apple Music and Spotify after the change, with no observed problems.

To repeat: measure idle first, play a track, leave the microphone active for at least 90 seconds, then stop. Compare only intervals after pause confirmation and before microphone deactivation; check fade completion and return to idle separately. Keep the same player and UI visibility for both runs.

## Compiled-command reuse (1.1.6)

The same paused-state query now reuses its compiled AppleScript object, with at most one per supported player. Permission and playback results are still read afresh on each check. The compiled object is discarded on execution error or player process change; reentrant execution is rejected. Fade, pause and resume commands and the polling interval are unchanged. This path also removes a redundant running-process lookup.

| Steady microphone-active interval | 1.1.5 | 1.1.6 |
| --- | ---: | ---: |
| Samples, approximately one second each | 56 | 56 |
| Mean CPU | 4.16% | 2.98% |
| Median CPU | 3.96% | 2.96% |
| Maximum sampled CPU | 4.96% | 3.95% |

The steady mean fell approximately another 28%, or 56% relative to 1.1.4. The 1.1.6 interval covers sample indices 40–95, after pause confirmation and before microphone deactivation. These separate sessions do not isolate compilation cost from the other small change or background system load. CPU returned to 0% in the idle samples afterward.

All 54 automated tests passed, including four real AppleScript tests covering compiled-object reuse with fresh execution, process changes, permission denial, and recovery after execution errors. The installed release's Apple Music long-session logs show completed fade-out, retained pause ownership, successful resume, and completed fade-in. After the requested Spotify desktop retest, the latest microphone session (19:11:32–19:11:52 local time) also logged completed fade-out, confirmed pause, successful resume, and completed fade-in. An earlier session canceled resume ownership while the microphone was still active. The user subsequently reported that they think they accidentally changed playback, which prompted the retest. This is consistent with the manual-override safeguard; the logs do not independently establish the cause of that earlier cancellation. The repeat session completed the full cycle without a logged failure.
