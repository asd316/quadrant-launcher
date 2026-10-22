import Foundation
import QuadrantCore
import Synchronization
import Testing
@testable import QuadrantSystem

/// A temp folder for one test. `remove()` deletes it.
private struct CopySandbox {
    let base: URL

    init() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ql-copy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    func path(_ relative: String) -> NodePath { NodePath(base.appendingPathComponent(relative).path) }

    func write(_ relative: String, _ content: String) throws {
        let url = base.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
    }

    func mkdir(_ relative: String) throws {
        try FileManager.default.createDirectory(at: base.appendingPathComponent(relative), withIntermediateDirectories: true)
    }

    func read(_ relative: String) throws -> String {
        try String(contentsOf: base.appendingPathComponent(relative), encoding: .utf8)
    }

    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: base.appendingPathComponent(relative).path)
    }

    func children(of relative: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: base.appendingPathComponent(relative).path).sorted()
    }

    func setPermissions(_ relative: String, _ mode: Int) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: mode], ofItemAtPath: base.appendingPathComponent(relative).path
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: base)
    }
}

@Suite struct CopyNamingTests {
    @Test func r8_5_nameWithExtensionGetsNumberBeforeExtension() {
        #expect(FileCopier.uniqueName(for: "报告.pdf", kind: .file) { _ in false } == "报告.pdf")
        #expect(FileCopier.uniqueName(for: "报告.pdf", kind: .file) { $0 == "报告.pdf" } == "报告 2.pdf")
        #expect(FileCopier.uniqueName(for: "报告.pdf", kind: .file) { ["报告.pdf", "报告 2.pdf"].contains($0) } == "报告 3.pdf")
    }

    @Test func r8_5_nameWithoutExtensionAppendsNumber() {
        #expect(FileCopier.uniqueName(for: "README", kind: .file) { $0 == "README" } == "README 2")
    }

    @Test func r8_5_folderNameWithDotIsNotSplit() {
        #expect(FileCopier.uniqueName(for: "资料", kind: .folder) { $0 == "资料" } == "资料 2")
        #expect(FileCopier.uniqueName(for: "v1.2", kind: .folder) { $0 == "v1.2" } == "v1.2 2")
    }

    @Test func r8_5_dotfileHasNoExtension() {
        #expect(FileCopier.uniqueName(for: ".env", kind: .file) { $0 == ".env" } == ".env 2")
    }

    @Test func r8_5_existingNumberedNameIsSkipped() {
        let taken: Set<String> = ["x", "x 2"]
        #expect(FileCopier.uniqueName(for: "x", kind: .file) { taken.contains($0) } == "x 3")
        #expect(FileCopier.uniqueName(for: "x.txt", kind: .file) { $0 == "x.txt" || $0 == "x 2.txt" } == "x 3.txt")
    }
}

@Suite struct CopyFileCopierTests {
    @Test func r8_2_copiesFileIntoFolderAndKeepsSource() async throws {
        let sandbox = try CopySandbox()
        defer { sandbox.remove() }
        try sandbox.write("src/a.txt", "alpha")
        try sandbox.mkdir("dst")

        let created = try await FileCopier().copy(sources: [sandbox.path("src/a.txt")], into: sandbox.path("dst"))

        #expect(created == [sandbox.path("dst/a.txt")])
        #expect(try sandbox.read("dst/a.txt") == "alpha")
        #expect(try sandbox.read("src/a.txt") == "alpha")
    }

    @Test func r8_5_collisionChainNeverOverwrites() async throws {
        let sandbox = try CopySandbox()
        defer { sandbox.remove() }
        try sandbox.write("src/报告.pdf", "new")
        try sandbox.write("dst/报告.pdf", "old")
        try sandbox.write("dst/报告 2.pdf", "older")

        let created = try await FileCopier().copy(sources: [sandbox.path("src/报告.pdf")], into: sandbox.path("dst"))

        #expect(created == [sandbox.path("dst/报告 3.pdf")])
        #expect(try sandbox.read("dst/报告.pdf") == "old")
        #expect(try sandbox.read("dst/报告 2.pdf") == "older")
        #expect(try sandbox.read("dst/报告 3.pdf") == "new")
    }

    @Test func r8_5_folderCollisionGetsSuffix() async throws {
        let sandbox = try CopySandbox()
        defer { sandbox.remove() }
        try sandbox.write("src/资料/inner.txt", "x")
        try sandbox.mkdir("dst/资料")

        let created = try await FileCopier().copy(sources: [sandbox.path("src/资料")], into: sandbox.path("dst"))

        #expect(created == [sandbox.path("dst/资料 2")])
        #expect(try sandbox.read("dst/资料 2/inner.txt") == "x")
    }

    @Test func r8_2_folderIsCopiedRecursively() async throws {
        let sandbox = try CopySandbox()
        defer { sandbox.remove() }
        try sandbox.write("src/tree/a.txt", "a")
        try sandbox.write("src/tree/deep/b.txt", "b")
        try sandbox.mkdir("dst")

        _ = try await FileCopier().copy(sources: [sandbox.path("src/tree")], into: sandbox.path("dst"))

        #expect(try sandbox.read("dst/tree/a.txt") == "a")
        #expect(try sandbox.read("dst/tree/deep/b.txt") == "b")
        #expect(try sandbox.read("src/tree/deep/b.txt") == "b")
    }

    @Test func r8_6_rejectsDestinationInsideSourceBeforeCopying() async throws {
        let sandbox = try CopySandbox()
        defer { sandbox.remove() }
        try sandbox.write("A/file.txt", "f")
        try sandbox.mkdir("A/B")

        // A file source is fine, but folder A contains the destination, so nothing may be copied.
        let sources = [sandbox.path("A/file.txt"), sandbox.path("A")]
        var thrown: FileCopyError?
        do {
            _ = try await FileCopier().copy(sources: sources, into: sandbox.path("A/B"))
        } catch let error as FileCopyError {
            thrown = error
        }
        #expect(thrown == .destinationInsideSource(sandbox.path("A/B")))
        #expect(try sandbox.children(of: "A/B").isEmpty)
    }

    @Test func r8_6_rejectsCopyIntoSelf() async throws {
        let sandbox = try CopySandbox()
        defer { sandbox.remove() }
        try sandbox.mkdir("A")

        var thrown: FileCopyError?
        do {
            _ = try await FileCopier().copy(sources: [sandbox.path("A")], into: sandbox.path("A"))
        } catch let error as FileCopyError {
            thrown = error
        }
        #expect(thrown == .destinationInsideSource(sandbox.path("A")))
    }

    @Test func r8_7_failureRemovesPartialCopyAndKeepsEarlierOnes() async throws {
        let sandbox = try CopySandbox()
        defer {
            try? sandbox.setPermissions("src/locked.txt", 0o644)
            sandbox.remove()
        }
        try sandbox.write("src/a_ok.txt", "a")
        try sandbox.write("src/locked.txt", "secret")
        try sandbox.write("src/z_ok.txt", "z")
        try sandbox.mkdir("dst")
        try sandbox.setPermissions("src/locked.txt", 0o000)

        let sources = [sandbox.path("src/a_ok.txt"), sandbox.path("src/locked.txt"), sandbox.path("src/z_ok.txt")]
        var thrown: FileCopyError?
        do {
            _ = try await FileCopier().copy(sources: sources, into: sandbox.path("dst"))
        } catch let error as FileCopyError {
            thrown = error
        }

        guard case .copyFailed(let item, _) = try #require(thrown) else {
            Issue.record("expected copyFailed, got \(String(describing: thrown))")
            return
        }
        #expect(item == sandbox.path("src/locked.txt"))
        #expect(try sandbox.children(of: "dst") == ["a_ok.txt"])
        #expect(try sandbox.read("dst/a_ok.txt") == "a")
        // Sources are untouched.
        try sandbox.setPermissions("src/locked.txt", 0o644)
        #expect(try sandbox.read("src/locked.txt") == "secret")
        #expect(try sandbox.read("src/a_ok.txt") == "a")
        #expect(try sandbox.read("src/z_ok.txt") == "z")
    }

    @Test func r8_7_failedFolderCopyIsRemovedCompletely() async throws {
        let sandbox = try CopySandbox()
        defer {
            try? sandbox.setPermissions("src/pkg/locked.txt", 0o644)
            sandbox.remove()
        }
        try sandbox.write("src/pkg/ok.txt", "ok")
        try sandbox.write("src/pkg/locked.txt", "secret")
        try sandbox.mkdir("dst")
        try sandbox.setPermissions("src/pkg/locked.txt", 0o000)

        var thrown: FileCopyError?
        do {
            _ = try await FileCopier().copy(sources: [sandbox.path("src/pkg")], into: sandbox.path("dst"))
        } catch let error as FileCopyError {
            thrown = error
        }

        guard case .copyFailed = try #require(thrown) else {
            Issue.record("expected copyFailed, got \(String(describing: thrown))")
            return
        }
        #expect(try sandbox.children(of: "dst").isEmpty)
        #expect(try sandbox.read("src/pkg/ok.txt") == "ok")
    }

    @Test func r8_7_progressReachesOneAndCountsItems() async throws {
        let sandbox = try CopySandbox()
        defer { sandbox.remove() }
        try sandbox.write("src/1.txt", "1")
        try sandbox.write("src/2.txt", "2")
        try sandbox.write("src/3.txt", "3")
        try sandbox.mkdir("dst")

        let reported = Mutex<[Double]>([])
        _ = try await FileCopier().copy(
            sources: ["1.txt", "2.txt", "3.txt"].map { sandbox.path("src/\($0)") },
            into: sandbox.path("dst")
        ) { fraction in
            reported.withLock { $0.append(fraction) }
        }

        let values = reported.withLock { $0 }
        #expect(values.count == 3)
        #expect(values.last == 1.0)
        #expect(values == values.sorted())
    }
}
