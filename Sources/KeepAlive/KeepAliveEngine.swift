import AVFoundation

/// Plays a continuous, near-inaudible **stochastic** sub-bass signal to the default
/// output so a Bluetooth device (AirPods Max, soundbar) doesn't idle-disconnect.
///
/// A constant 20 Hz tone proved insufficient: some devices' idle detectors ignore an
/// unchanging signal and disconnect anyway, and a sustained single frequency
/// resonated into an audible buzz after hours. Instead we render a sine whose
/// frequency random-walks (~18–45 Hz) and whose amplitude wobbles low, plus
/// occasional brief low "ticks" — varied enough to read as real audio (defeating
/// idle detection) and to avoid resonance, yet low and low-frequency enough to stay
/// near-inaudible and survive Bluetooth codec high-frequency roll-off. Follows the
/// default output as it changes by rebuilding on a configuration change.
@MainActor
final class KeepAliveEngine {
  private let engine = AVAudioEngine()
  private var source: AVAudioSourceNode?
  private var running = false
  private let gen = Generator()

  init() {
    NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.handleConfigChange() }
    }
  }

  func start() {
    guard !running else { return }
    running = true
    rebuild()
  }

  func stop() {
    guard running else { return }
    running = false
    teardown()
  }

  /// Safety net (called periodically): if a device-change churn left the engine
  /// stopped, bring it back.
  func healthCheck() {
    guard running else { return }
    if !engine.isRunning {
      Log.line("health check: engine not running — restarting")
      rebuild()
    }
  }

  // MARK: - Internals

  /// The default output device/format changed — rebuild against the new output.
  private func handleConfigChange() {
    guard running else { return }
    rebuild()
    Log.line("reconfigured for output change")
  }

  /// (Re)build the source node for the current output format and start the engine.
  private func rebuild() {
    teardown()

    let outFormat = engine.mainMixerNode.outputFormat(forBus: 0)
    let sampleRate = outFormat.sampleRate > 0 ? outFormat.sampleRate : 44_100
    gen.sampleRate = sampleRate

    // Standard deinterleaved float: the render block writes one buffer per channel.
    guard
      let format = AVAudioFormat(
        standardFormatWithSampleRate: sampleRate, channels: max(outFormat.channelCount, 1))
    else { return }

    let g = gen
    // @Sendable so the render block is NON-isolated: AVAudioSourceNode invokes it on
    // the realtime audio thread, and a main-actor-inherited closure would trap in
    // Swift's executor isolation check (swift_task_checkIsolated → SIGTRAP).
    let render: AVAudioSourceNodeRenderBlock = { @Sendable _, _, frameCount, abl in
      g.render(frameCount: frameCount, abl: abl)
      return noErr
    }
    let node = AVAudioSourceNode(format: format, renderBlock: render)
    engine.attach(node)
    engine.connect(node, to: engine.mainMixerNode, format: format)
    source = node

    do {
      try engine.start()
    } catch {
      Log.line("engine start failed: \(error.localizedDescription)")
    }
  }

  private func teardown() {
    engine.stop()
    if let source {
      engine.detach(source)
      self.source = nil
    }
  }
}

/// Real-time generator for the keep-alive signal.
///
/// Strategy: a **steady 20 Hz** tone — below a soundbar's reproduction range, so it
/// stays inaudible even if the device's auto-gain ramps it — pulsed **intermittently
/// (60 s on / 20 s off)**. The 20 s gap is under the soundbar's ~30 s idle timeout
/// (so it never disconnects) and keeps the auto-gain from acclimating to a constant
/// tone. On/off transitions glide the amplitude (no clicks); phase is wrapped.
///
/// All state is mutated only on the audio render thread; `sampleRate` is set on the
/// main thread while the engine is stopped (rebuild() tears down first), so there's
/// no concurrent access — hence `@unchecked Sendable`. The render path allocates
/// nothing and takes no locks.
private final class Generator: @unchecked Sendable {
  var sampleRate: Double = 44_100

  // Tunable — adjust from real-world results.
  private let toneFreq = 20.0  // Hz — below the soundbar's dynamic range → inaudible
  private let toneAmp = 0.05  // level during the "on" window
  private let onSecs = 60.0  // tone duration
  private let offSecs = 20.0  // silence (< the ~30 s soundbar idle timeout)
  private let ampGlide = 0.0008  // per-sample amplitude glide (~28 ms; click-free)

  private var elapsed = 0  // frames since (re)start
  private var phase = 0.0
  private var amp = 0.0  // current amplitude (starts muted → fades in)

  func render(frameCount: AVAudioFrameCount, abl: UnsafeMutablePointer<AudioBufferList>) {
    let buffers = UnsafeMutableAudioBufferListPointer(abl)
    let n = Int(frameCount)
    let sr = sampleRate
    let twoPi = 2.0 * Double.pi

    let onFrames = Int(onSecs * sr)
    let period = max(onFrames + Int(offSecs * sr), 1)

    for i in 0..<n {
      let on = (elapsed % period) < onFrames  // 60 s on, 20 s off
      elapsed += 1

      let target = on ? toneAmp : 0.0
      amp += (target - amp) * ampGlide

      phase += twoPi * toneFreq / sr
      if phase >= twoPi { phase -= twoPi }
      let v = Float(amp * sin(phase))

      for b in 0..<buffers.count {
        if let data = buffers[b].mData {
          data.assumingMemoryBound(to: Float.self)[i] = v
        }
      }
    }
  }
}
