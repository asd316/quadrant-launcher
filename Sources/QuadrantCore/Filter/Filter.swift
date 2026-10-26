import Foundation

/// Type-to-filter (L6): matches node names in every quadrant's snapshot.
public enum Filter {
    public struct Match: Hashable, Sendable {
        public var edge: Edge
        public var node: FolderNode
    }

    /// Case- and width-insensitive substring match on names, ranked by display weight (R1.4).
    /// Searches the snapshots only (L1–L3 and their direct files); deeper levels are reached through the lens.
    public static func matches(
        _ query: String,
        in snapshots: [Edge: FolderSnapshot],
        usage: UsageIndex,
        now: Date,
        limit: Int = 50
    ) -> [Match] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        var found: [NodePath: Match] = [:]
        for edge in Edge.allCases {
            guard let root = snapshots[edge]?.root else { continue }
            var stack = root.children
            while let node = stack.popLast() {
                if node.name.range(of: needle, options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive]) != nil,
                   found[node.path] == nil {
                    found[node.path] = Match(edge: edge, node: node)
                }
                stack.append(contentsOf: node.children)
            }
        }
        let ranked = DisplayWeight.rank(found.values.map(\.node), usage: usage, now: now)
        return ranked.prefix(limit).compactMap { found[$0.node.path] }
    }
}
