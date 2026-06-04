import AVFoundation

/// Plays a continuous, inaudible tone to the default output so a Bluetooth device
/// (AirPods Max, soundbar) doesn't idle-disconnect. Follows the default output as
/// it changes (e.g. AirPods connecting) by reconfiguring on a config-change.
@MainActor
final class KeepAliveEngine {
  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private var running = false
  // True during a periodic refresh's brief pause, so the health check doesn't
  // restart playback out from under it.
  private var refreshing = false

  init() {
    engine.attach(player)
    connect()

    NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.handleConfigChange() }
    }
  }

  func start() {
    guard !running else { return }
    running = true
    play()
  }

  func stop() {
    guard running else { return }
    running = false
    player.stop()
    engine.stop()
  }

  /// If we should be playing but aren't (a device-change left the engine running
  /// but silent, or it stopped), restart. Called periodically — the Bluetooth
  /// route renegotiates often, so this is the safety net that keeps the tone alive.
  func healthCheck() {
    guard running, !refreshing else { return }
    if !engine.isRunning || !player.isPlaying {
      Log.line("health check: engine not playing — restarting")
      play()
    }
  }

  /// Periodic stream reset for the buzz that develops after many hours of continuous
  /// playback. Goes through the shared settle-then-restart path.
  func refresh() {
    pauseThenRestart(reason: "periodic refresh")
  }

  /// Stop, let the Bluetooth stream settle ~5s, then rewire to the current output
  /// and restart. The multi-second gap is required: testing showed an *immediate*
  /// restart leaves the buzz (the stream/route needs time to reset) while a ~5s gap
  /// clears it — still far below the idle-disconnect threshold, so the link holds.
  /// A `refreshing` guard coalesces overlapping triggers and keeps the health check
  /// from restarting playback mid-pause.
  private func pauseThenRestart(reason: String) {
    guard running, !refreshing else { return }
    refreshing = true
    Log.line("\(reason): ~5s pause to reset the audio stream")
    player.stop()
    engine.stop()

    Task { @MainActor in
      try? await Task.sleep(for: .seconds(5))
      refreshing = false
      if running {
        connect()  // rewire to the (possibly new) output format
        play()
        Log.line("\(reason): resumed")
      }
    }
  }

  // MARK: - Internals

  private func connect() {
    let format = engine.mainMixerNode.outputFormat(forBus: 0)
    engine.connect(player, to: engine.mainMixerNode, format: format)
  }

  private func play() {
    guard running else { return }
    let format = engine.mainMixerNode.outputFormat(forBus: 0)
    guard let buffer = Self.inaudibleBuffer(format: format) else { return }

    do {
      if !engine.isRunning { try engine.start() }
      player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
      player.play()
    } catch {
      Log.line("engine start failed: \(error.localizedDescription)")
    }
  }

  /// The default output device / format changed (a volume change can trigger a BT
  /// codec renegotiation here). Settle, then rewire and restart — an immediate
  /// restart can leave a buzz, so this goes through the same pause path.
  private func handleConfigChange() {
    pauseThenRestart(reason: "output reconfiguration")
  }

  /// Exactly 1 second of a 20 Hz sine at 0.05 amplitude — matching a tone
  /// generator proven to keep Bluetooth speakers/soundbars awake. 20 Hz is at the
  /// bottom of hearing (near-inaudible, a faint rumble at most on a sub), and —
  /// unlike a near-ultrasonic tone — it survives Bluetooth codec high-frequency
  /// roll-off, so the device actually "sees" audio. 1s = exactly 20 cycles, so
  /// the looped buffer is seamless (no pulsing).
  private static func inaudibleBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let frames = AVAudioFrameCount(format.sampleRate)
    guard frames > 0,
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
    else { return nil }
    buffer.frameLength = frames

    let amplitude: Float = 0.05
    let frequency = 20.0
    let sampleRate = format.sampleRate

    if let channels = buffer.floatChannelData {
      for ch in 0..<Int(format.channelCount) {
        for i in 0..<Int(frames) {
          channels[ch][i] = amplitude * Float(sin(2.0 * .pi * frequency * Double(i) / sampleRate))
        }
      }
    }
    return buffer
  }
}
