import Foundation
import QuadrantCore
import Testing
@testable import QuadrantSystem

/// Builds root/{a.txt,.hidden,.hiddenDir/x, L2/{f2.txt,loop->root, L3/{f3.txt, L4/{f4.txt, L5/f5.txt}}}}.
private struct TempTree {
    let base: URL
    var root: NodePath { NodePath(base.appendingPathComponent("root").path) }

    init() throws {
        let fm = FileManager.default
        base = fm.temporaryDirectory.appendingPathComponent("ql-fs-\(UUID().uuidString)")
        let rootURL = base.appendingPathComponent("root")
        let l5 = rootURL.appendingPathComponent("L2/L3/L4/L5")
        try fm.createDirectory(at: l5, withIntermediateDirectories: true)
        try fm.createDirectory(at: rootURL.appendingPathComponent(".hiddenDir"), withIntermediateDirectories: true)
        for file in ["a.txt", ".hidden", ".hiddenDir/x", "L2/f2.txt", "L2/.h2", "L2/L3/f3.txt", "L2/L3/L4/f4.txt", "L2/L3/L4/L5/f5.txt"] {
            try Data("x".utf8).write(to: rootURL.appendingPathComponent(file))
        }
        try fm.createSymbolicLink(atPath: rootURL.appendingPathComponent("L2/loop").path, withDestinationPath: rootURL.path)
    }

    func remove() { try? FileManager.default.removeItem(at: base) }
}

@Test func snapshotStopsAtL3AndKeepsDirectFiles() async throws {
    let tree = try TempTree()
    defer { tree.remove() }
    let snapshot = try await FileSystemFolderSource().snapshot(root: tree.root)

    let root = snapshot.root
    #expect(root.path == tree.root)
    #expect(root.files.map(\.name) == ["a.txt"])
    #expect(root.folders.map(\.name) == ["L2"])

    let l2 = try #require(root.folders.first)
    #expect(l2.files.map(\.name) == ["f2.txt"])
    let l3 = try #require(l2.folders.first { $0.name == "L3" })
    #expect(l3.files.map(\.name) == ["f3.txt"])
    #expect(l3.folders.isEmpty)  // L4 is not in the snapshot
    #expect(snapshot.node(at: tree.root.appending("L2/L3/L4")) == nil)
    #expect(snapshot.node(at: tree.root.appending("L2/L3/f3.txt"))?.kind == .file)
    #expect(l3.files[0].modifiedAt > Date.distantPast)
}

@Test func snapshotSkipsDotNames() async throws {
    let tree = try TempTree()
    defer { tree.remove() }
    let snapshot = try await FileSystemFolderSource().snapshot(root: tree.root)
    let names = snapshot.root.children.map(\.name) + (snapshot.root.folders.first?.children.map(\.name) ?? [])
    #expect(!names.contains { $0.hasPrefix(".") })
}

@Test func snapshotIncludesSymlinkButDoesNotDescend() async throws {
    let tree = try TempTree()
    defer { tree.remove() }
    let snapshot = try await FileSystemFolderSource().snapshot(root: tree.root)
    let loop = try #require(snapshot.node(at: tree.root.appending("L2/loop")))
    #expect(loop.isSymlink)
    #expect(loop.kind == .folder)
    #expect(loop.children.isEmpty)
    #expect(snapshot.root.folders.first?.children.filter(\.isSymlink).count == 1)
}

@Test func snapshotThrowsWhenRootMissing() async throws {
    let missing = NodePath("/tmp/ql-does-not-exist-\(UUID().uuidString)")
    await #expect(throws: FolderSourceError.folderMissing(missing)) {
        try await FileSystemFolderSource().snapshot(root: missing)
    }
}

@Test func childrenOfDeepFolderListsDirectChildrenOnly() async throws {
    let tree = try TempTree()
    defer { tree.remove() }
    let l5 = tree.root.appending("L2/L3/L4/L5")
    let kids = try await FileSystemFolderSource().children(of: l5)
    #expect(kids.map(\.name) == ["f5.txt"])
    let l4 = try await FileSystemFolderSource().children(of: tree.root.appending("L2/L3/L4"))
    #expect(l4.map(\.name) == ["L5", "f4.txt"])
    #expect(l4.first?.children.isEmpty == true)
    await #expect(throws: FolderSourceError.self) {
        try await FileSystemFolderSource().children(of: tree.root.appending("nope"))
    }
}

@Test func existsReportsFiles() throws {
    let tree = try TempTree()
    defer { tree.remove() }
    let source = FileSystemFolderSource()
    #expect(source.exists(tree.root.appending("L2/L3/f3.txt")))
    #expect(source.exists(tree.root.appending("L2")))
    #expect(!source.exists(tree.root.appending("L2/missing")))
}

@Test func changesEmitsAfterCreatingFile() async throws {
    let tree = try TempTree()
    defer { tree.remove() }
    let source = FileSystemFolderSource()
    let stream = source.changes(under: [tree.root])
    let created = tree.base.appendingPathComponent("root/L2/new-file.txt")

    let result = await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            for await paths in stream where paths.contains(where: { $0.name == "new-file.txt" }) {
                return true
            }
            return false
        }
        group.addTask {
            // Stream startup is asynchronous; keep touching the file until the event arrives.
            for attempt in 0..<40 {
                try? await Task.sleep(for: .milliseconds(150))
                try? Data("\(attempt)".utf8).write(to: created)
            }
            return false
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(5))
            return false
        }
        let first = await group.next() ?? false
        group.cancelAll()
        return first
    }
    #expect(result)
}

@Test func changesStopsWhenConsumerCancels() async throws {
    let tree = try TempTree()
    defer { tree.remove() }
    let stream = FileSystemFolderSource().changes(under: [tree.root])
    let consumer = Task { for await _ in stream {} }
    try await Task.sleep(for: .milliseconds(200))
    consumer.cancel()
    await consumer.value  // returns only if the iterator ended on cancel
}

@Test func changesWithNoRootsFinishes() async {
    var count = 0
    for await _ in FileSystemFolderSource().changes(under: []) { count += 1 }
    #expect(count == 0)
}

/// Validation › 大文件夹扫描速度. Runs only with QL_SCAN_BENCH=<folder>, read-only.
@Test(.enabled(if: ProcessInfo.processInfo.environment["QL_SCAN_BENCH"] != nil))
func scanTimingOfRealFolder() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["QL_SCAN_BENCH"])
    let source = FileSystemFolderSource()
    var timings: [Double] = []
    var count = 0
    for _ in 0..<3 {
        let start = ContinuousClock.now
        let snapshot = try await source.snapshot(root: NodePath(path))
        let elapsed = ContinuousClock.now - start
        timings.append(Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)
        func total(_ n: FolderNode) -> Int { 1 + n.children.reduce(0) { $0 + total($1) } }
        count = total(snapshot.root)
    }
    print("SCAN_TIMING nodes=\(count) runs_ms=\(timings.map { String(format: "%.1f", $0) })")
}
