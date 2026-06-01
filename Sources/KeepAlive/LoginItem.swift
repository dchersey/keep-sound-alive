import ServiceManagement

/// Registers this menu-bar app as a macOS login item via the modern SMAppService
/// API (no helper bundle). The panel toggle reads/writes this.
enum LoginItem {
  static var isEnabled: Bool {
    SMAppService.mainApp.status == .enabled
  }

  /// Returns the new enabled-state after attempting the change.
  @discardableResult
  static func setEnabled(_ enabled: Bool) -> Bool {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      Log.line("login item toggle failed: \(error)")
    }
    return isEnabled
  }
}
