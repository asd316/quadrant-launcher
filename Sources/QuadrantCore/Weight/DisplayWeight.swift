import Foundation

/// A node with its computed display weight.
public struct WeightedNode: Hashable, Sendable {
    public var node: FolderNode
    public var weight: Double

    public init(node: FolderNode, weight: Double) {
        self.node = node
        self.weight = weight
    }
}

/// Display weight, ordering and star brightness (R1.2, R1.4, R1.5).
public enum DisplayWeight {
    public static let recencyHalfLifeDays: Double = 7

    /// Recency bonus: `1 × 0.5 ^ (days since the node's own modifiedAt / 7)`. Not rolled up.
    public static func recency(modifiedAt: Date, now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(modifiedAt)) / 86_400
        return pow(0.5, days / recencyHalfLifeDays)
    }

    /// `weight = rolled-up usage + own recency`.
    public static func weight(of node: FolderNode, usage: UsageIndex, now: Date) -> Double {
        usage.score(of: node.path) + recency(modifiedAt: node.modifiedAt, now: now)
    }

    /// Weight descending; ties by name in Finder order (`第2周` before `第10周`), then by path for determinism.
    public static func rank(_ nodes: [FolderNode], usage: UsageIndex, now: Date) -> [WeightedNode] {
        nodes
            .map { WeightedNode(node: $0, weight: weight(of: $0, usage: usage, now: now)) }
            .sorted { lhs, rhs in
                if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
                switch lhs.node.name.localizedStandardCompare(rhs.node.name) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: return lhs.node.path < rhs.node.path
                }
            }
    }

    /// `0.25 + 0.75 × weight / maxWeight`. A group whose max weight is 0 gets 0.25 everywhere.
    public static func brightness(weight: Double, maxWeight: Double) -> Double {
        guard maxWeight > 0 else { return 0.25 }
        return 0.25 + 0.75 * min(1, max(0, weight / maxWeight))
    }

    /// Pinned nodes first, ordered by `markedAt` ascending (then name), outside weight (R3.2).
    /// Returns the pinned nodes and the remaining unpinned nodes (rank order not applied to the rest).
    static func splitPinned(
        _ nodes: [FolderNode], marks: [NodePath: MarkRecord]
    ) -> (pinned: [FolderNode], rest: [FolderNode]) {
        var pinned: [(FolderNode, Date)] = []
        var rest: [FolderNode] = []
        for node in nodes {
            if let mark = marks[node.path], mark.mark == .pinned {
                pinned.append((node, mark.markedAt))
            } else {
                rest.append(node)
            }
        }
        pinned.sort { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0.name.localizedStandardCompare(rhs.0.name) == .orderedAscending
        }
        return (pinned.map(\.0), rest)
    }
}
