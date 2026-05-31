import Foundation
import Observation

/// A LIFO stack of "holds" that keep audio alive. Each hold has its own expiry.
/// Audio should play while the stack is non-empty. Callers are stateless: push on
/// start, pop on end; a hold also drops off when its timer expires. Pure model —
/// the engine + menu observe it; a timer calls `sweep` periodically.
@MainActor
@Observable
public final class HoldStack {
  // Each hold is its absolute expiry time (seconds since 1970).
  private var expiries: [TimeInterval] = []

  public init() {}

  public var active: Bool { !expiries.isEmpty }
  public var count: Int { expiries.count }
  public var nextExpiry: TimeInterval? { expiries.min() }

  /// Push a hold lasting `minutes` from `now`.
  public func push(minutes: Double, now: TimeInterval = Date().timeIntervalSince1970) {
    expiries.append(now + minutes * 60)
  }

  /// Pop the most recently pushed hold (LIFO). No-op when empty.
  public func pop() {
    if !expiries.isEmpty { expiries.removeLast() }
  }

  /// Drop any holds whose timer has expired. Returns whether anything changed.
  @discardableResult
  public func sweep(now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
    let before = expiries.count
    expiries.removeAll { $0 <= now }
    return expiries.count != before
  }
}
