import Foundation
import KeepAliveCore

/// Owns the hold stack, the audio engine, and the control server, and keeps the
/// engine running exactly while the stack is non-empty. A periodic sweep drops
/// expired holds.
@MainActor
@Observable
final class AppController {
  let stack = HoldStack()
  let defaultMinutes: Double = 8 * 60

  private let engine = KeepAliveEngine()
  private var server: ControlServer?
  private var sweepTimer: Timer?

  init() {
    server = ControlServer(stack: stack, defaultMinutes: defaultMinutes) { [weak self] in
      self?.reconcile()
    }
    server?.start()

    sweepTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        if self.stack.sweep() { self.reconcile() }
      }
    }
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

  func remainingText() -> String {
    guard let next = stack.nextExpiry else { return "" }
    let seconds = max(0, Int(next - Date().timeIntervalSince1970))
    return " · \(seconds / 3600)h \((seconds % 3600) / 60)m left"
  }

  private func reconcile() {
    if stack.active { engine.start() } else { engine.stop() }
  }
}
