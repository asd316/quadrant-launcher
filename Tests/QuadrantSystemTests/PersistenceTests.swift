import Foundation
import GRDB
import QuadrantCore
import Testing
@testable import QuadrantSystem

private func withTempDir<T>(_ body: (URL) throws -> T) throws -> T {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("quadrant-persist-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    return try body(dir)
}

private func t(_ n: Double) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + n) }

@Suite struct PersistenceTests {
    @Test func freshFileMigratesAndLoadsEmpty() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("sub/state.sqlite")
            let store = try SQLiteStore(url: url)
            #expect(FileManager.default.fileExists(atPath: url.path))
            #expect(!store.didResetAfterCorruption)
            #expect(try store.load() == PersistentState())
            #expect(try store.all().isEmpty)
            // Reopening an already migrated file is fine and keeps data.
            try store.apply([.setRoot(.top, NodePath("/a"))])
            let again = try SQLiteStore(url: url)
            #expect(try again.load().roots[.top] == NodePath("/a"))
        }
    }

    @Test func roundTripsEveryMutation() throws {
        try withTempDir { dir in
            let store = try SQLiteStore(url: dir.appendingPathComponent("s.sqlite"))
            let mark = MarkRecord(path: NodePath("/r/a"), mark: .pinned, markedAt: t(1))
            let stash = [
                StashItem(targetPath: NodePath("/f/1"), kind: .file, addedAt: t(1)),
                StashItem(targetPath: NodePath("/f/2"), kind: .folder, addedAt: t(2)),
            ]
            let top = [
                PinnedSlot(edge: .top, targetPath: NodePath("/p/1"), addedAt: t(1)),
                PinnedSlot(edge: .top, targetPath: NodePath("/p/2"), addedAt: t(2)),
            ]
            try store.apply([
                .setRoot(.left, NodePath("/root")),
                .setMark(mark),
                .setFocus(root: NodePath("/root"), branch: NodePath("/root/b")),
                .setDrillPath(l3: NodePath("/root/b/c"), deep: NodePath("/root/b/c/d/e")),
                .setStash(stash),
                .setPinnedSlots(.top, top),
            ])
            let state = try store.load()
            #expect(state.roots == [.left: NodePath("/root")])
            #expect(state.marks == [NodePath("/r/a"): mark])
            #expect(state.focus == [NodePath("/root"): NodePath("/root/b")])
            #expect(state.drillPaths == [NodePath("/root/b/c"): NodePath("/root/b/c/d/e")])
            #expect(state.stash == stash)
            #expect(state.pinnedSlots == top)

            // Overwrites, clears and replacements.
            let hidden = MarkRecord(path: NodePath("/r/a"), mark: .hidden, markedAt: t(5))
            try store.apply([
                .setMark(hidden),
                .setFocus(root: NodePath("/root"), branch: NodePath("/root/x")),
                .setDrillPath(l3: NodePath("/root/b/c"), deep: NodePath("/root/b/c/z")),
                .setStash([stash[1]]),
                .setPinnedSlots(.bottom, [PinnedSlot(edge: .bottom, targetPath: NodePath("/p/9"), addedAt: t(3))]),
                .setPinnedSlots(.top, [top[1]]),
            ])
            var next = try store.load()
            #expect(next.marks[NodePath("/r/a")] == hidden)
            #expect(next.focus[NodePath("/root")] == NodePath("/root/x"))
            #expect(next.drillPaths[NodePath("/root/b/c")] == NodePath("/root/b/c/z"))
            #expect(next.stash == [stash[1]])
            #expect(next.pinnedSlots.filter { $0.edge == .top } == [top[1]])
            #expect(next.pinnedSlots.filter { $0.edge == .bottom }.count == 1)

            try store.apply([.clearMark(NodePath("/r/a")), .setRoot(.left, nil), .setStash([]), .setPinnedSlots(.top, [])])
            next = try store.load()
            #expect(next.marks.isEmpty)
            #expect(next.roots.isEmpty)
            #expect(next.stash.isEmpty)
            #expect(next.pinnedSlots.map(\.edge) == [.bottom])
        }
    }

    @Test func stashAndPinnedKeepGivenOrderNotPathOrder() throws {
        try withTempDir { dir in
            let store = try SQLiteStore(url: dir.appendingPathComponent("s.sqlite"))
            let stash = [
                StashItem(targetPath: NodePath("/z"), kind: .file, addedAt: t(1)),
                StashItem(targetPath: NodePath("/a"), kind: .file, addedAt: t(2)),
            ]
            try store.apply([.setStash(stash)])
            #expect(try store.load().stash == stash)
        }
    }

    @Test func applyIsAtomic() throws {
        try withTempDir { dir in
            let store = try SQLiteStore(url: dir.appendingPathComponent("s.sqlite"))
            let dup = StashItem(targetPath: NodePath("/dup"), kind: .file, addedAt: t(1))
            #expect(throws: (any Error).self) {
                try store.apply([
                    .setRoot(.top, NodePath("/should-roll-back")),
                    .setMark(MarkRecord(path: NodePath("/m"), mark: .hidden, markedAt: t(1))),
                    .setStash([dup, dup]),  // violates "a path appears at most once"
                ])
            }
            #expect(try store.load() == PersistentState())
        }
    }

    @Test func usageAppendsInOrder() throws {
        try withTempDir { dir in
            let store = try SQLiteStore(url: dir.appendingPathComponent("s.sqlite"))
            let events = UsageAction.allCases.enumerated().map { i, action in
                UsageEvent(path: NodePath("/u/\(i % 2)"), action: action, occurredAt: t(Double(10 - i)))
            }
            for e in events { try store.append(e) }
            try store.append(events[0])  // duplicates are kept: append-only
            #expect(try store.all() == events + [events[0]])
        }
    }

    @Test func corruptFileIsMovedAsideAndReset() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("state.sqlite")
            try Data(repeating: 0x41, count: 4096).write(to: url)
            let store = try SQLiteStore(url: url)
            #expect(store.didResetAfterCorruption)
            #expect(try store.load() == PersistentState())
            let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            #expect(names.contains { $0.hasPrefix("state.corrupt-") && $0.hasSuffix(".sqlite") })
            // The new database works.
            try store.append(UsageEvent(path: NodePath("/x"), action: .open, occurredAt: t(0)))
            #expect(try store.all().count == 1)
            // Reopening is a normal open, not another reset.
            #expect(!(try SQLiteStore(url: url)).didResetAfterCorruption)
        }
    }

    @Test func r5_3_switchingRootKeepsOldStateByPath() throws {
        try withTempDir { dir in
            let store = try SQLiteStore(url: dir.appendingPathComponent("s.sqlite"))
            let old = NodePath("/old"), new = NodePath("/new")
            let mark = MarkRecord(path: NodePath("/old/a"), mark: .hidden, markedAt: t(1))
            try store.apply([
                .setRoot(.top, old),
                .setMark(mark),
                .setFocus(root: old, branch: NodePath("/old/b")),
                .setDrillPath(l3: NodePath("/old/b/c"), deep: NodePath("/old/b/c/d")),
            ])
            try store.append(UsageEvent(path: NodePath("/old/b"), action: .focusBranch, occurredAt: t(1)))

            try store.apply([.setRoot(.top, new)])
            var state = try store.load()
            #expect(state.roots[.top] == new)
            #expect(state.focus[old] == NodePath("/old/b"))
            #expect(state.marks[NodePath("/old/a")] == mark)
            #expect(state.drillPaths[NodePath("/old/b/c")] == NodePath("/old/b/c/d"))
            #expect(try store.all().count == 1)

            try store.apply([.setRoot(.top, old)])
            state = try store.load()
            #expect(state.roots[.top] == old)
            #expect(state.focus[old] == NodePath("/old/b"))
        }
    }

    @Test func defaultURLIsInApplicationSupport() {
        #expect(SQLiteStore.defaultURL.path.hasSuffix("/Library/Application Support/QuadrantLauncher/state.sqlite"))
    }
}
