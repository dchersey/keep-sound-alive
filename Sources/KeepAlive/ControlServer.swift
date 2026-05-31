import Foundation
import KeepAliveCore
import Network

/// Minimal localhost HTTP control API (no dependencies). Generic — it only knows
/// about the hold stack, not about any particular caller.
///
///   POST /on   {minutes?}  -> push a hold        -> {ok, holds}
///   POST /off              -> pop a hold (LIFO)   -> {ok, holds}
///   GET  /status           -> {on, holds, next_expiry}
@MainActor
final class ControlServer {
  private var listener: NWListener?
  private let stack: HoldStack
  private let defaultMinutes: Double
  private let onChange: () -> Void

  init(stack: HoldStack, defaultMinutes: Double, onChange: @escaping () -> Void) {
    self.stack = stack
    self.defaultMinutes = defaultMinutes
    self.onChange = onChange
  }

  func start(port: UInt16 = 4041) {
    let params = NWParameters.tcp
    params.allowLocalEndpointReuse = true
    params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)

    guard let listener = try? NWListener(using: params) else {
      Log.line("control server failed to bind :\(port)")
      return
    }
    self.listener = listener
    listener.newConnectionHandler = { [weak self] conn in
      conn.start(queue: .main)
      MainActor.assumeIsolated { self?.receive(conn) }
    }
    listener.start(queue: .main)
    Log.line("control server on 127.0.0.1:\(port)")
  }

  private func receive(_ conn: NWConnection) {
    conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
      guard let self else {
        conn.cancel()
        return
      }
      let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
      let (status, body) = MainActor.assumeIsolated { self.route(request) }
      let response =
        "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\n"
        + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
      conn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
    }
  }

  private func route(_ request: String) -> (String, String) {
    let firstLine =
      request.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false)
      .first.map(String.init) ?? ""
    let tokens = firstLine.split(separator: " ")
    guard tokens.count >= 2 else { return ("400 Bad Request", #"{"error":"bad request"}"#) }

    let method = String(tokens[0])
    let path = String(tokens[1].split(separator: "?").first ?? tokens[1])

    switch (method, path) {
    case ("POST", "/on"):
      stack.push(minutes: parseMinutes(request) ?? defaultMinutes)
      onChange()
      return ("200 OK", #"{"ok":true,"holds":\#(stack.count)}"#)
    case ("POST", "/off"):
      stack.pop()
      onChange()
      return ("200 OK", #"{"ok":true,"holds":\#(stack.count)}"#)
    case ("GET", "/status"):
      let next = stack.nextExpiry.map { String($0) } ?? "null"
      return ("200 OK", #"{"on":\#(stack.active),"holds":\#(stack.count),"next_expiry":\#(next)}"#)
    default:
      return ("404 Not Found", #"{"error":"not found"}"#)
    }
  }

  // Crude scan for `"minutes": N` in the body — enough for a control API.
  private func parseMinutes(_ request: String) -> Double? {
    guard let range = request.range(of: "\"minutes\"") else { return nil }
    let digits = request[range.upperBound...]
      .drop { !"0123456789.".contains($0) }
      .prefix { "0123456789.".contains($0) }
    return Double(digits)
  }
}
