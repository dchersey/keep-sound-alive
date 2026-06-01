import AVFoundation

/// Plays a continuous, inaudible tone to the default output so a Bluetooth device
/// (AirPods Max, soundbar) doesn't idle-disconnect. Follows the default output as
/// it changes (e.g. AirPods connecting) by reconfiguring on a config-change.
@MainActor
final class KeepAliveEngine {
  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private var running = false

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

  /// The default output device changed — rewire to it and restart if active.
  private func handleConfigChange() {
    guard running else { return }
    player.stop()
    engine.stop()
    connect()
    play()
    Log.line("reconfigured for output change")
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
