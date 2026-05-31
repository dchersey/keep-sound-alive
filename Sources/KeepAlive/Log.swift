import Foundation

/// Minimal file logger (the app is a menu-bar agent with no console).
/// Appends to ~/Library/Logs/keep-alive.log.
enum Log {
  private static let url = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/keep-alive.log")

  static func line(_ message: String) {
    let entry = "\(Date()) \(message)\n"
    guard let data = entry.data(using: .utf8) else { return }
    if let handle = try? FileHandle(forWritingTo: url) {
      defer { try? handle.close() }
      handle.seekToEndOfFile()
      handle.write(data)
    } else {
      try? data.write(to: url)
    }
  }
}
