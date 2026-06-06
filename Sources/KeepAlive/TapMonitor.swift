import CoreAudio
import Foundation

/// Measures the level of system audio coming from **other apps** via a Core Audio
/// process tap (macOS 14.4+), so the keep-alive tone can mute itself over real
/// playback instead of buzzing under it.
///
/// Opt-in: creating the tap requires the user to grant system-audio capture
/// permission, so it's only started when the user enables "Monitor audio". Our own
/// process is excluded (our keep-alive tone must not count as playback), and the
/// meter high-passes as a backstop against our sub-bass leaking in.
///
/// Fail-safe: if the tap can't be created or isn't authorized, `isRunning` stays
/// false and `level` reads 0, so callers never suppress — the keep-alive simply
/// behaves as always-on (today's behavior).
@MainActor
final class TapMonitor {
  private var tapID = AudioObjectID(kAudioObjectUnknown)
  private var aggID = AudioObjectID(kAudioObjectUnknown)
  private var procID: AudioDeviceIOProcID?
  private let meter = Meter()
  private(set) var isRunning = false

  /// Current RMS level of other apps' output (0 when stopped/unavailable).
  var level: Float { meter.level }

  func start() {
    guard !isRunning else { return }
    if create() {
      isRunning = true
      Log.line("audio monitor: tap started")
    } else {
      teardown()
      Log.line("audio monitor: unavailable (not authorized?) — keep-alive stays always-on")
    }
  }

  func stop() {
    guard isRunning else { return }
    teardown()
    isRunning = false
    meter.level = 0
    Log.line("audio monitor: tap stopped")
  }

  /// Rebuild the tap (e.g. once our keep-alive engine starts) so its exclude-self
  /// list picks up our now-present audio process — guaranteeing our own tone is never
  /// measured as playback. No-op if monitoring isn't running.
  func restart() {
    guard isRunning else { return }
    teardown()
    isRunning = false
    meter.level = 0
    start()
  }

  // MARK: - Setup

  private func create() -> Bool {
    let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: excludeSelf())
    desc.name = "Keep Sound Alive Monitor"
    desc.isPrivate = true
    desc.muteBehavior = .unmuted  // observe only — never silence the real output

    guard AudioHardwareCreateProcessTap(desc, &tapID) == noErr, tapID != kAudioObjectUnknown,
      let tapUID = stringProperty(tapID, kAudioTapPropertyUID),
      let outUID = defaultOutputUID()
    else { return false }

    // A tap-only aggregate has no clock and never pulls; the default output device is
    // the *main* (clock) device, while the sub-device list stays empty so we read the
    // tap stream (not a real device's input) as the IOProc's input.
    let aggregate: [String: Any] = [
      kAudioAggregateDeviceNameKey: "Keep Sound Alive Monitor",
      kAudioAggregateDeviceUIDKey: "org.hersey.keepalive.monitor",
      kAudioAggregateDeviceMainSubDeviceKey: outUID,
      kAudioAggregateDeviceIsPrivateKey: true,
      kAudioAggregateDeviceIsStackedKey: false,
      kAudioAggregateDeviceTapAutoStartKey: true,
      kAudioAggregateDeviceSubDeviceListKey: [],
      kAudioAggregateDeviceTapListKey: [
        [kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: tapUID]
      ],
    ]
    guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggID) == noErr,
      aggID != kAudioObjectUnknown
    else { return false }

    let m = meter
    let block: AudioDeviceIOBlock = { @Sendable _, input, _, _, _ in m.consume(input) }
    guard
      AudioDeviceCreateIOProcIDWithBlock(
        &procID, aggID, DispatchQueue(label: "org.hersey.keepalive.tap"), block) == noErr,
      procID != nil, AudioDeviceStart(aggID, procID) == noErr
    else { return false }

    return true
  }

  private func teardown() {
    if let procID, aggID != kAudioObjectUnknown {
      AudioDeviceStop(aggID, procID)
      AudioDeviceDestroyIOProcID(aggID, procID)
    }
    procID = nil
    if aggID != kAudioObjectUnknown {
      AudioHardwareDestroyAggregateDevice(aggID)
      aggID = kAudioObjectUnknown
    }
    if tapID != kAudioObjectUnknown {
      AudioHardwareDestroyProcessTap(tapID)
      tapID = kAudioObjectUnknown
    }
  }

  // MARK: - Property helpers

  /// Our own process's audio object, so the tap excludes our keep-alive tone.
  private func excludeSelf() -> [AudioObjectID] {
    var pid = getpid()
    var addr = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
    var obj = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = withUnsafeMutablePointer(to: &pid) {
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &addr,
        UInt32(MemoryLayout<pid_t>.size), $0, &size, &obj)
    }
    return (status == noErr && obj != kAudioObjectUnknown) ? [obj] : []
  }

  private func defaultOutputUID() -> CFString? {
    var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
    var dev = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    guard
      AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)
        == noErr
    else { return nil }
    return stringProperty(dev, kAudioDevicePropertyDeviceUID)
  }

  private func stringProperty(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector)
    -> CFString?
  {
    var addr = address(selector)
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let ok = withUnsafeMutablePointer(to: &value) {
      AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, $0) == noErr
    }
    return ok ? value : nil
  }

  private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
  }
}

/// Lock-free RMS meter: written on the realtime IO thread, read on the main thread
/// (a benign Float race — we only need an approximate level). A one-pole high-pass
/// (~150 Hz at 48 kHz) strips very low frequencies so our own ~20 Hz keep-alive tone
/// can't register as playback even if exclusion ever misses.
private final class Meter: @unchecked Sendable {
  var level: Float = 0
  private var hpX: Float = 0
  private var hpY: Float = 0
  private let hpCoeff: Float = 0.98

  func consume(_ input: UnsafePointer<AudioBufferList>) {
    let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
    var sum: Float = 0
    var count = 0
    var x = hpX
    var y = hpY
    for buffer in abl {
      guard let data = buffer.mData else { continue }
      let n = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
      let samples = data.assumingMemoryBound(to: Float.self)
      for i in 0..<n {
        let s = samples[i]
        y = hpCoeff * (y + s - x)
        x = s
        sum += y * y
      }
      count += n
    }
    hpX = x
    hpY = y
    if count > 0 { level = (sum / Float(count)).squareRoot() }
  }
}
