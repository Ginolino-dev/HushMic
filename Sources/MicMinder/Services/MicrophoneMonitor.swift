import CoreAudio
import Foundation

protocol MicrophoneMonitoring: AnyObject {
  var onChange: ((MicrophoneSnapshot) -> Void)? { get set }
  func start()
  func stop()
  func refresh()
}

final class MicrophoneMonitor: MicrophoneMonitoring {
  var onChange: ((MicrophoneSnapshot) -> Void)?

  private let queue = DispatchQueue(label: "dev.ginolino.MicMinder.microphone")
  private var deviceListeners: [RegisteredAudioListener] = []
  private var processListeners: [RegisteredAudioListener] = []
  private var systemListeners: [RegisteredAudioListener] = []
  private var processInputDevices: [AudioObjectID: [AudioDeviceID]] = [:]
  private var inputDeviceNames: [AudioDeviceID: String] = [:]
  private var lastSnapshot: MicrophoneSnapshot?
  private var activityError: LocalizedMessage?
  private var processErrors: [AudioObjectID: LocalizedMessage] = [:]
  private var listenerErrors: [AudioObjectID: LocalizedMessage] = [:]
  private var systemObservationError: LocalizedMessage?
  private var isStarted = false

  deinit {
    stop()
  }

  func start() {
    queue.async { [weak self] in
      guard let self, !self.isStarted else {
        return
      }

      self.isStarted = true
      self.installSystemListeners()
      self.rebuildDeviceListeners()
      self.rebuildProcessListeners()
      self.publishSnapshot()
    }
  }

  func stop() {
    queue.sync {
      processInputDevices.removeAll()
      processErrors.removeAll()
      listenerErrors.removeAll()
      activityError = nil
      systemObservationError = nil
      inputDeviceNames.removeAll()
      lastSnapshot = nil
      removeListeners(&deviceListeners)
      removeListeners(&processListeners)
      removeListeners(&systemListeners)
      isStarted = false
    }
  }

  func refresh() {
    queue.async { [weak self] in
      self?.installSystemListeners()
      self?.rebuildDeviceListeners()
      self?.rebuildProcessListeners()
      self?.refreshAllProcessActivity()
      self?.publishSnapshot()
    }
  }

  private func installSystemListeners() {
    guard isStarted else { return }
    systemObservationError = nil
    let addresses = [CoreAudioDeviceQuery.devicesAddress(), CoreAudioDeviceQuery.processListAddress()]
    for originalAddress in addresses {
      guard !systemListeners.contains(where: { $0.address.mSelector == originalAddress.mSelector }) else {
        continue
      }
      var address = originalAddress
      let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        guard let self, self.isStarted else { return }
        if originalAddress.mSelector == CoreAudioDeviceQuery.devicesAddress().mSelector {
          self.rebuildDeviceListeners()
          self.refreshAllProcessActivity()
        } else {
          self.rebuildProcessListeners()
        }
        self.publishSnapshot()
      }
      let status = AudioObjectAddPropertyListenerBlock(
        CoreAudioDeviceQuery.systemObject, &address, queue, block
      )
      if status == noErr {
        systemListeners.append(RegisteredAudioListener(
          objectID: CoreAudioDeviceQuery.systemObject, address: address, block: block
        ))
      } else {
        systemObservationError = .coreAudioError(.key("coreaudio.observe_activity"), status)
      }
    }
  }

  private func rebuildDeviceListeners() {
    guard isStarted else {
      return
    }

    removeListeners(&deviceListeners)

    guard let devices = try? CoreAudioDeviceQuery.inputDevices() else {
      return
    }

    inputDeviceNames = Dictionary(uniqueKeysWithValues: devices.map {
      ($0, CoreAudioDeviceQuery.deviceName($0))
    })

    for device in devices {
      var runningAddress = CoreAudioDeviceQuery.runningAddress()
      let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.refreshAllProcessActivity()
        self?.publishSnapshot()
      }

      let status = AudioObjectAddPropertyListenerBlock(device, &runningAddress, queue, block)
      guard status == noErr else {
        continue
      }

      deviceListeners.append(
        RegisteredAudioListener(
          objectID: AudioObjectID(device),
          address: runningAddress,
          block: block
        )
      )
    }
  }

  private func rebuildProcessListeners() {
    guard isStarted else { return }
    do {
      let processes = try CoreAudioDeviceQuery.processObjectIDs()
      let currentIDs = Set(processes)
      var stale = processListeners.filter { !currentIDs.contains($0.objectID) }
      removeListeners(&stale)
      processListeners.removeAll { !currentIDs.contains($0.objectID) }
      processInputDevices = processInputDevices.filter { currentIDs.contains($0.key) }
      processErrors = processErrors.filter { currentIDs.contains($0.key) }
      listenerErrors = listenerErrors.filter { currentIDs.contains($0.key) }
      activityError = nil
      for process in processes {
        let isNew = processInputDevices[process] == nil
        if isNew { processInputDevices[process] = [] }
        listenerErrors[process] = nil
        // A change from one process only reads that process's input activity.
        // Device changes are also observed while an input stream stays running.
        for originalAddress in [CoreAudioDeviceQuery.processInputRunningAddress(),
                                CoreAudioDeviceQuery.processInputDevicesAddress()] {
          guard !processListeners.contains(where: {
            $0.objectID == process && $0.address.mSelector == originalAddress.mSelector
              && $0.address.mScope == originalAddress.mScope
          }) else { continue }
          var address = originalAddress
          let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.refreshProcessActivity(process)
            self?.publishSnapshot()
          }
          let status = AudioObjectAddPropertyListenerBlock(process, &address, queue, block)
          if status == noErr {
            processListeners.append(RegisteredAudioListener(
              objectID: process, address: address, block: block
            ))
          } else {
            listenerErrors[process] = .coreAudioError(.key("coreaudio.observe_activity"), status)
          }
        }
        if isNew { refreshProcessActivity(process) }
      }
    } catch {
      activityError = errorMessage(error)
    }
  }

  private func refreshProcessActivity(_ process: AudioObjectID) {
    // Ignore callbacks already queued for an audio process removed by macOS.
    guard isStarted, processInputDevices[process] != nil else { return }
    do {
      processInputDevices[process] = try CoreAudioDeviceQuery.activeInputDeviceIDs(for: [process])
      processErrors[process] = nil
    } catch {
      processErrors[process] = errorMessage(error)
    }
  }

  private func refreshAllProcessActivity() {
    for process in Array(processInputDevices.keys) {
      refreshProcessActivity(process)
    }
  }

  private func errorMessage(_ error: Error) -> LocalizedMessage {
    (error as? CoreAudioError)?.localizedMessage ?? .raw(error.localizedDescription)
  }

  private func publishSnapshot() {
    guard isStarted else { return }
    let activeIDs = Set(processInputDevices.values.flatMap { $0 }).sorted()
    let error = systemObservationError ?? activityError
      ?? listenerErrors.keys.sorted().first.flatMap { listenerErrors[$0] }
      ?? processErrors.keys.sorted().first.flatMap { processErrors[$0] }
    let snapshot = MicrophoneSnapshot(
      isActive: error == nil && !activeIDs.isEmpty,
      activeDeviceNames: activeIDs.map { inputDeviceNames[$0] ?? CoreAudioDeviceQuery.deviceName($0) },
      inputDeviceNames: inputDeviceNames.keys.sorted().compactMap { inputDeviceNames[$0] },
      errorMessage: error
    )
    guard snapshot != lastSnapshot else { return }
    lastSnapshot = snapshot
    onChange?(snapshot)
  }

  private func removeListeners(_ listeners: inout [RegisteredAudioListener]) {
    for listener in listeners {
      var address = listener.address
      AudioObjectRemovePropertyListenerBlock(
        listener.objectID,
        &address,
        queue,
        listener.block
      )
    }

    listeners.removeAll()
  }
}

private struct RegisteredAudioListener {
  var objectID: AudioObjectID
  var address: AudioObjectPropertyAddress
  var block: AudioObjectPropertyListenerBlock
}
