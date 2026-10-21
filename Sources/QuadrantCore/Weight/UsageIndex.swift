import Foundation

/// Decayed usage score per path, with roll-up (R1.1–R1.3).
///
/// Built once from the raw usage events at a fixed `asOf` time. Each event is worth 1 and halves every
/// `halfLifeDays` (30). A node's score is its own events plus every descendant's events, summed by path
/// prefix. No disk scan is needed because the events already carry full paths.
public struct UsageIndex: Sendable {
    public static let halfLifeDays: Double = 30

    public let asOf: Date
    /// Rolled-up score: the path's own events plus all descendants' events.
    private let rolled: [NodePath: Double]

    public init(events: [UsageEvent], asOf: Date) {
        var rolled: [NodePath: Double] = [:]
        for event in events {
            let score = Self.decayed(from: event.occurredAt, to: asOf)
            var cursor: NodePath? = event.path
            while let path = cursor {
                rolled[path, default: 0] += score
                cursor = path.parent
            }
        }
        self.asOf = asOf
        self.rolled = rolled
    }

    public static let empty = UsageIndex(events: [], asOf: Date(timeIntervalSince1970: 0))

    /// Usage score of `path` including all descendants. Unknown paths score 0.
    public func score(of path: NodePath) -> Double { rolled[path] ?? 0 }

    /// One event's worth after decay: `0.5 ^ (days / 30)`. Events in the future count as full value.
    static func decayed(from occurredAt: Date, to now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(occurredAt)) / 86_400
        return pow(0.5, days / halfLifeDays)
    }
}
