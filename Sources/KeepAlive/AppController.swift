import Foundation
import KeepAliveCore

/// Owns the hold stack, the audio engine, and the control server, and keeps the
/// engine running exactly while the stack is non-empty. A periodic sweep drops
/// expired holds.
///
/// Optionally (opt-in via `monitorAudio`) it watches the system output level with a
/// `TapMonitor` and mutes the keep-alive tone whenever other audio is playing — that
/// already keeps the device awake, and our tone would otherwise buzz under it.
@MainActor
@Observable
final class AppController {
  let stack = HoldStack()
  let defaultMinutes: Double = 8 * 60
  private(set) var monitorAudio: Bool

  private let engine = KeepAliveEngine()
  private let tap = TapMonitor()
  private var server: ControlServer?
  private var sweepTimer: Timer?
  private var monitorTimer: Timer?

  private var suppressed = false
  private var loudUntil = 0.0
  private var aboveSince = 0.0
  private var engineActive = false
  // Tunables (from measured levels: true silence ~0.00005, our own tone ~0.003 after
  // exclusion + high-pass, music/voice 0.02–0.18). Mute only after the level stays
  // above threshold for `onsetSeconds` (ignores momentary system dings), and keep
  // muted for `holdSeconds` after it goes quiet (bridges track gaps).
  private let playThreshold: Float = 0.01
  private let onsetSeconds = 0.6
  private let holdSeconds = 1.5

  init() {
    monitorAudio = UserDefaults.standard.bool(forKey: "monitorAudioDevice")

    server = ControlServer(stack: stack, defaultMinutes: defaultMinutes) { [weak self] in
      self?.reconcile()
    }
    server?.start()

    sweepTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        if self.stack.sweep() { self.reconcile() }
        // Safety net: re-establish playback if a device-change churn silently
        // stopped it (otherwise the device idle-disconnects unnoticed).
        self.engine.healthCheck()
      }
    }

    // Drives the mute-over-other-audio logic (a no-op when monitoring is off).
    monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.updateSuppression() }
    }

    if monitorAudio { tap.start() }
    reconcile()

    // First launch: add to login items so it autostarts. Afterward the menu
    // toggle controls it (and a manual removal in System Settings sticks).
    let defaults = UserDefaults.standard
    if !defaults.bool(forKey: "loginConfigured") {
      LoginItem.setEnabled(true)
      defaults.set(true, forKey: "loginConfigured")
      Log.line("first launch — login item enabled: \(LoginItem.isEnabled)")
    }
  }

  /// Menu toggle: turn off (pop a hold) if on, else push a manual hold.
  func toggle() {
    if stack.active { stack.pop() } else { stack.push(minutes: defaultMinutes) }
    reconcile()
  }

  /// Settings toggle: enable/disable muting the keep-alive over other audio. Enabling
  /// starts the tap, which prompts for system-audio permission the first time.
  func setMonitorAudio(_ on: Bool) {
    monitorAudio = on
    UserDefaults.standard.set(on, forKey: "monitorAudioDevice")
    if on {
      tap.start()
    } else {
      tap.stop()
      applySuppressed(false)
    }
  }

  func remainingText() -> String {
    guard let next = stack.nextExpiry else { return "" }
    let seconds = max(0, Int(next - Date().timeIntervalSince1970))
    return " · \(seconds / 3600)h \((seconds % 3600) / 60)m left"
  }

  private func reconcile() {
    let active = stack.active
    if active { engine.start() } else { engine.stop() }
    // When our tone starts, rebuild the tap so it excludes our (now-present) audio
    // process — our own keep-alive can never read as "other audio."
    if active && !engineActive && monitorAudio { tap.restart() }
    engineActive = active
  }

  /// Mute the keep-alive tone while other audio is playing; resume it in silence.
  /// No-op (never suppresses) unless monitoring is on and the tap is authorized.
  private func updateSuppression() {
    guard monitorAudio, tap.isRunning else {
      applySuppressed(false)
      return
    }
    let now = Date().timeIntervalSince1970
    if tap.level > playThreshold {
      if aboveSince == 0 { aboveSince = now }
      if now - aboveSince >= onsetSeconds { loudUntil = now + holdSeconds }
    } else {
      aboveSince = 0
    }
    applySuppressed(now < loudUntil)
  }

  private func applySuppressed(_ value: Bool) {
    if value != suppressed {
      suppressed = value
      Log.line(value ? "other audio playing — muting keep-alive" : "silence — keep-alive resumed")
    }
    engine.setSuppressed(value)
  }
}
