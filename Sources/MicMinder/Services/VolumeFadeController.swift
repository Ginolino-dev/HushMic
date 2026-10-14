import Foundation
import OSLog

// Own only temporary player-volume changes. Never change the system volume.
final class VolumeFadeController {
  private let playback: PlaybackAccess
  private let logger = Logger(subsystem: "dev.ginolino.MicMinder", category: "VolumeFade")
  private var stepping = false
  private var commandInFlight = false
  var onStepFinished: (() -> Void)?
  var isBusy: Bool { stepping || commandInFlight }
  private var timer: Timer?
  private var recoveryTimer: Timer?
  private var operation: Operation?
  private var deferredRestorations: [String: Operation] = [:]

  init(playback: PlaybackAccess) { self.playback = playback }
  deinit { cancel(); recoveryTimer?.invalidate() }

  func fadeOut(_ player: ScriptableMediaPlayer, identity: String,
               valid: @escaping () -> Bool, cancelled: @escaping () -> Void, pause: @escaping () -> Void) {
    cancel()
    guard let volume = playback.volume(player), volume > 0 else { pause(); return }
    begin(player, identity: identity, original: volume, from: volume, to: 0,
          valid: valid, cancelled: cancelled, completion: pause)
  }

  func fadeIn(_ player: ScriptableMediaPlayer, identity: String,
              valid: @escaping () -> Bool, ready: @escaping () -> Bool, play: () -> Bool) -> Bool {
    cancel()
    guard let volume = playback.volume(player), volume > 0 else { return play() }
    guard playback.setVolume(player, 0) else { return play() }
    begin(player, identity: identity, original: volume, from: 0, to: volume,
          valid: valid, cancelled: {}, completion: {})
    operation?.ready = ready
    operation?.waitingForPlayback = true
    let operationID = operation?.id
    commandInFlight = true
    let played = play()
    commandInFlight = false
    guard operation?.id == operationID else { return played }
    guard played else { cancel(); return false }
    operation?.started = ProcessInfo.processInfo.systemUptime
    logger.notice("Fade-in Play returned; waiting for confirmed playback")
    return true
  }

  func cancel() {
    timer?.invalidate()
    timer = nil
    let cancelled = operation
    operation = nil
    retryRestoration()
    if let cancelled, !restore(cancelled) {
      deferredRestorations[cancelled.player.bundleIdentifier] = cancelled
    }
    updateRecoveryTimer()
  }

  func retryRestoration() {
    for (key, pending) in deferredRestorations {
      if restore(pending) { deferredRestorations.removeValue(forKey: key) }
    }
    updateRecoveryTimer()
  }

  private func updateRecoveryTimer() {
    guard !deferredRestorations.isEmpty else {
      recoveryTimer?.invalidate()
      recoveryTimer = nil
      return
    }
    guard recoveryTimer == nil else { return }
    recoveryTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      self?.retryRestoration()
    }
  }

  private func begin(_ player: ScriptableMediaPlayer, identity: String, original: Int,
                     from: Int, to: Int, valid: @escaping () -> Bool,
                     cancelled: @escaping () -> Void, completion: @escaping () -> Void) {
    operation = Operation(player: player, identity: identity, original: original,
                          from: from, to: to, lastVolume: from,
                          started: ProcessInfo.processInfo.systemUptime,
                          valid: valid, cancelled: cancelled, completion: completion)
    let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.step() }
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func step() {
    // AppleScript can pump the main run loop while awaiting a reply.
    guard !stepping, !commandInFlight, var current = operation else { return }
    stepping = true
    defer {
      stepping = false
      onStepFinished?()
    }
    var elapsed = ProcessInfo.processInfo.systemUptime - current.started
    let valid = current.valid()
    guard operation?.id == current.id else { return }
    guard valid else {
      logger.notice("Fade canceled: playback context changed")
      cancel(); current.cancelled(); return
    }
    if current.waitingForPlayback {
      let ready = current.ready()
      guard operation?.id == current.id else { return }
      guard ready else {
        if elapsed > 3 {
          logger.notice("Fade-in canceled: playback confirmation timed out")
          cancel()
        }
        return
      }
      current.waitingForPlayback = false
      current.started = ProcessInfo.processInfo.systemUptime
      elapsed = 0
      operation = current
      logger.notice("Playback confirmed; starting half-second fade-in")
    } else if current.to > 0 {
      let ready = current.ready()
      guard operation?.id == current.id else { return }
      if !ready { cancel(); return }
    }
    // A callback may have canceled/replaced the operation during an Apple event.
    guard operation?.id == current.id else { return }
    // A changed slider belongs to the user. Stop fading and leave it alone.
    let observed = playback.volume(current.player)
    guard operation?.id == current.id else { return }
    guard let observedVolume = observed else {
      cancel(); current.cancelled(); return
    }
    guard observedVolume == current.lastVolume else {
      finish(current, restoreVolume: false)
      return
    }
    let fraction = min(1, elapsed / 0.5)
    let volume = Int((Double(current.from) + Double(current.to - current.from) * fraction).rounded())
    if volume != current.lastVolume {
      let written = playback.setVolume(current.player, volume)
      guard operation?.id == current.id else { return }
      guard written else {
        finish(current, restoreVolume: true)
        return
      }
      current.lastVolume = volume
      current.frames += 1
      guard operation?.id == current.id else { return }
      operation = current
    }
    if fraction >= 1 { finish(current, restoreVolume: true) }
  }

  private func finish(_ current: Operation, restoreVolume: Bool) {
    timer?.invalidate()
    timer = nil
    // Keep the lowered volume until pause confirmation; Music can take a
    // moment to acknowledge pause. Restoring sooner creates an audible jump.
    let waitingForPause = restoreVolume && current.to == 0
    operation = waitingForPause ? current : nil
    logger.notice("Fade finished: rising=\(current.to > 0), volume steps=\(current.frames)")
    current.completion()
    if restoreVolume && !waitingForPause && !restore(current) {
      deferredRestorations[current.player.bundleIdentifier] = current
      updateRecoveryTimer()
    }
  }

  // False means access/read/write is temporarily unavailable; retain our
  // original level until access returns. User edits and process changes end ownership.
  private func restore(_ current: Operation) -> Bool {
    guard playback.isRunning(current.player) else { return true }
    guard playback.hasAutomationPermission(current.player),
          let identity = playback.identity(current.player) else { return false }
    guard identity.split(separator: ":").first == current.identity.split(separator: ":").first else { return true }
    guard let volume = playback.volume(current.player) else { return false }
    guard volume == current.lastVolume else { return true }
    return playback.setVolume(current.player, current.original)
  }

  private struct Operation {
    let id = UUID()
    var frames = 0
    var waitingForPlayback = false
    var ready: () -> Bool = { true }
    var player: ScriptableMediaPlayer
    var identity: String
    var original: Int
    var from: Int
    var to: Int
    var lastVolume: Int
    var started: TimeInterval
    var valid: () -> Bool
    var cancelled: () -> Void
    var completion: () -> Void
  }
}
