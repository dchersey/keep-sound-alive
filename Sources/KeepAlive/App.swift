import SwiftUI

@main
struct KeepAliveApp: App {
  @State private var controller = AppController()

  var body: some Scene {
    MenuBarExtra {
      PanelView(controller: controller)
    } label: {
      Image(systemName: controller.stack.active ? "speaker.wave.2.fill" : "speaker.slash")
    }
    .menuBarExtraStyle(.window)
  }
}
