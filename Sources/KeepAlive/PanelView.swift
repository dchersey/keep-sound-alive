import AppKit
import SwiftUI

struct PanelView: View {
  let controller: AppController
  @State private var launchAtLogin = LoginItem.isEnabled

  var body: some View {
    let stack = controller.stack

    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Keep Audio Awake").font(.headline)
        Spacer()
        Text(stack.active ? "ON" : "off")
          .font(.caption.bold())
          .foregroundStyle(stack.active ? .green : .secondary)
      }

      if stack.active {
        Text("\(stack.count) hold\(stack.count == 1 ? "" : "s")\(controller.remainingText())")
          .font(.caption).foregroundStyle(.secondary)
      } else {
        Text("idle — plays silent audio to keep your output device awake")
          .font(.caption2).foregroundStyle(.tertiary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Button(stack.active ? "Turn off" : "Turn on (8h)") { controller.toggle() }
        .buttonStyle(.bordered)

      Divider()

      Toggle("Mute when other audio plays", isOn: Binding(
        get: { controller.monitorAudio },
        set: { controller.setMonitorAudio($0) }))
        .toggleStyle(.checkbox)
        .font(.caption)
      Text("Watches the audio output so the keep-alive tone goes silent while music or video is playing. Asks for audio permission the first time.")
        .font(.caption2).foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)

      HStack {
        Toggle("Launch at Login", isOn: $launchAtLogin)
          .toggleStyle(.checkbox)
          .font(.caption)
          .onChange(of: launchAtLogin) { _, newValue in
            launchAtLogin = LoginItem.setEnabled(newValue)
          }
        Spacer()
        Button("Quit") { NSApplication.shared.terminate(nil) }
          .buttonStyle(.bordered).controlSize(.small)
      }
    }
    .padding(14)
    .frame(width: 250)
  }
}
