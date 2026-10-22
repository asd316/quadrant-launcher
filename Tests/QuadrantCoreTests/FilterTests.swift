import Foundation
import Testing
@testable import QuadrantCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func node(_ path: String, _ kind: NodeKind = .folder, _ children: [FolderNode] = []) -> FolderNode {
    FolderNode(path: NodePath(path), kind: kind, modifiedAt: now.addingTimeInterval(-86_400 * 365), children: children)
}

@Test func l6_filterMatchesNamesAcrossQuadrantsRankedByWeight() {
    let left = FolderSnapshot(root: node("/k", .folder, [node("/k/Grid笔记", .folder, [node("/k/Grid笔记/grid.md", .file)])]))
    let top = FolderSnapshot(root: node("/d", .folder, [node("/d/grid-paper.pdf", .file), node("/d/other", .folder)]))
    let usage = UsageIndex(events: [UsageEvent(path: NodePath("/d/grid-paper.pdf"), action: .open, occurredAt: now)], asOf: now)
    let result = Filter.matches("GRID", in: [.left: left, .top: top], usage: usage, now: now)
    #expect(result.map(\.node.path.raw) == ["/d/grid-paper.pdf", "/k/Grid笔记", "/k/Grid笔记/grid.md"])
    #expect(result.first?.edge == .top)
}

@Test func l6_emptyQueryMatchesNothing() {
    let top = FolderSnapshot(root: node("/d", .folder, [node("/d/a", .file)]))
    #expect(Filter.matches("  ", in: [.top: top], usage: .empty, now: now).isEmpty)
}
