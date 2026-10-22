import Foundation
import QuadrantCore
import Testing
@testable import QuadrantSystem

/// A temp folder with one file and one folder. The test removes it.
private struct ClipboardSandbox {
    let base: URL
    var file: URL { base.appendingPathComponent("a.txt") }
    var folder: URL { base.appendingPathComponent("资料", isDirectory: true) }

    init() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ql-clip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: file)
    }

    func remove() {
        try? FileManager.default.removeItem(at: base)
    }
}

@Suite struct CopyClipboardPathsTests {
    @Test func r8_4_mergesFileURLsAndTextInOrderWithoutDuplicates() throws {
        let sandbox = try ClipboardSandbox()
        defer { sandbox.remove() }
        let text = "\(sandbox.folder.path)\n  \(sandbox.file.path)  \n\(sandbox.file.path)\r\n"

        let result = ClipboardPaths.resolve(
            fileURLs: [sandbox.file, sandbox.folder],
            text: text,
            exists: { FileManager.default.fileExists(atPath: $0) }
        )

        #expect(result.map(\.0) == [NodePath(sandbox.file.path), NodePath(sandbox.folder.path)])
        #expect(result.map(\.1) == [.file, .folder])
    }

    @Test func r8_4_dropsPathsThatDoNotExist() {
        let result = ClipboardPaths.resolve(
            fileURLs: [],
            text: "/fake/a\n/fake/missing",
            exists: { $0 == "/fake/a" }
        )
        #expect(result.map(\.0) == [NodePath("/fake/a")])
    }

    @Test func r8_4_ignoresBlankAndRelativeLinesAndNonFileURLs() {
        let result = ClipboardPaths.resolve(
            fileURLs: [URL(string: "https://example.com/x")!],
            text: "relative/path\n\n   \nhello world\n/fake/a\r\n",
            exists: { _ in true }
        )
        #expect(result.map(\.0) == [NodePath("/fake/a")])
    }

    @Test func r8_4_tildeLinesExpandToHome() {
        let result = ClipboardPaths.resolve(
            fileURLs: [],
            text: "~/zz-copy-test-not-real",
            exists: { _ in true }
        )
        #expect(result.map(\.0) == [NodePath(NSHomeDirectory() + "/zz-copy-test-not-real")])
    }

    @Test func r8_4_nothingUsableGivesEmptyResult() {
        let result = ClipboardPaths.resolve(fileURLs: [], text: "plain words\n", exists: { _ in true })
        #expect(result.isEmpty)
        #expect(ClipboardPaths.resolve(fileURLs: [], text: nil, exists: { _ in true }).isEmpty)
    }
}
