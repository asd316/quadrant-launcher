import Foundation
import QuadrantCore

/// Default root folders for a first run (no roots stored). Only folders that exist are used.
enum FirstRunSeed {
    static func roots(home: String, exists: (String) -> Bool) -> [Edge: NodePath] {
        let candidates: [(Edge, String)] = [
            (.top, home + "/Downloads"),
            (.bottom, home + "/Desktop"),
            (.right, home + "/Documents"),
            (.left, home + "/Documents/Notes"),
        ]
        var result: [Edge: NodePath] = [:]
        for (edge, path) in candidates where exists(path) { result[edge] = NodePath(path) }
        return result
    }
}
