import Foundation
import QuadrantCore
import QuadrantSystem
import QuadrantUI
import Testing

@testable import QuadrantApp

@MainActor
@Suite struct AppModelTests {
    private func makeTree() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("qa-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: base.appendingPathComponent("Alpha/Docs"), withIntermediateDirectories: true)
        try fm.createDirectory(at: base.appendingPathComponent("Beta"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: base.appendingPathComponent("Alpha/note.txt"))
        return base
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    @Test func setRootScansPersistsAndFocusRendersStars() async throws {
        let base = try makeTree()
        let dbURL = FileManager.default.temporaryDirectory.appendingPathComponent("qa-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: base)
            try? FileManager.default.removeItem(at: dbURL)
        }
        let store = try SQLiteStore(url: dbURL)
        let model = AppModel(store: store, messageDuration: .milliseconds(100))
        model.setRoot(.top, to: NodePath(base.path))
        #expect(await waitUntil { model.render.quadrants[.top]?.status == .ready })
        #expect(try store.load().roots[.top] == NodePath(base.path))

        model.dispatch(.summon)
        let alpha = NodePath(base.path).appending("Alpha")
        model.handle(.clickBranch(.top, alpha))
        #expect(model.render.quadrants[.top]?.branches.items.first(where: { $0.path == alpha })?.isFocused == true)
        #expect(try store.all().contains { $0.action == .focusBranch && $0.path == alpha })

        // Typing filters; the first match is selected so Return can act on it.
        model.dispatch(.setFilter("note"))
        #expect(model.render.lens?.rows.count == 1)
        #expect(model.render.keyboardSelection == alpha.appending("note.txt"))
    }

    @Test func cloudDrillLoadsADeeperFolderAndItsFiles() async throws {
        let base = try makeTree()
        let docs = base.appendingPathComponent("Alpha/Docs")
        try Data("spec".utf8).write(to: docs.appendingPathComponent("spec.md"))
        let dbURL = FileManager.default.temporaryDirectory.appendingPathComponent("qa-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: base)
            try? FileManager.default.removeItem(at: dbURL)
        }
        let model = AppModel(store: try SQLiteStore(url: dbURL), messageDuration: .milliseconds(100))
        model.setRoot(.top, to: NodePath(base.path))
        #expect(await waitUntil { model.render.quadrants[.top]?.status == .ready })
        model.dispatch(.summon)
        model.handle(.starCapacityMeasured(.top, 16))
        model.dispatch(.drillCloud(.top, folder: NodePath(docs.path)))
        #expect(await waitUntil {
            let stars = model.render.quadrants[.top]?.stars
            return stars?.branch == NodePath(docs.path) && stars?.isLoading == false
        })
        let stars = model.render.quadrants[.top]?.stars
        #expect(stars?.items.contains { $0.name == "spec.md" && $0.kind == .file } == true)
    }

    @Test func rejectionShowsMessageThenClears() async throws {
        let model = AppModel(store: nil, messageDuration: .milliseconds(100))
        model.dispatch(.summon)
        model.dispatch(.paste(items: [], target: .stash))
        #expect(model.render.message == "剪贴板里没有可用的文件或路径")
        #expect(await waitUntil { model.render.message == nil })
    }

    @Test func escapeCascadeClosesOnToggle() {
        let model = AppModel(store: nil)
        model.togglePanel()
        #expect(model.state.display == .full)
        model.dispatch(.setFilter("a"))
        model.togglePanel()
        #expect(model.state.display == .closed)
    }

    @Test func keysAreIgnoredWhileClosed() {
        let model = AppModel(store: nil)
        #expect(model.handle(key: KeyInput(key: .letter("A"), text: "a")) == false)
        model.togglePanel()
        #expect(model.handle(key: KeyInput(key: .letter("A"), text: "a")) == true)
        #expect(model.render.filterText == "a")
    }

    @Test func launcherSignalShowsPanelWithoutTogglingItClosed() {
        let model = AppModel(store: nil)
        let window = FakeWindow()
        model.window = window
        model.showPanel()
        #expect(model.state.display == .full)
        #expect(window.calls.contains("restoreFull"))
        model.showPanel()
        #expect(model.state.display == .full)
        #expect(window.calls.last == "front")
    }
}

@MainActor
final class FakeWindow: PanelWindowControlling {
    var calls: [String] = []
    func restoreFull() { calls.append("restoreFull") }
    func enterHalfHidden() { calls.append("half") }
    func hide() { calls.append("hide") }
    func stepBehind() { calls.append("behind") }
    func bringToFront() { calls.append("front") }
}

@MainActor
@Suite struct FinderOpenTests {
    @Test func folderOpenStepsBehindAndKeepsPanelFull() {
        let model = AppModel(store: nil, openURL: { _ in }, revealURL: { _ in })
        let window = FakeWindow()
        model.window = window
        model.togglePanel()
        model.handle(.doubleClick(np("/tmp"), .folder))
        #expect(model.state.display == .full)
        #expect(model.isBehindFinder)
        #expect(window.calls.contains("behind"))
        // Second summon brings it back; the next one closes it.
        model.togglePanel()
        #expect(window.calls.last == "front")
        #expect(model.state.display == .full)
        model.togglePanel()
        #expect(model.state.display == .closed)
    }

    @Test func fileOpenClosesPanel() {
        let model = AppModel(store: nil, openURL: { _ in }, revealURL: { _ in })
        model.window = FakeWindow()
        model.togglePanel()
        model.dispatch(.open(np("/nonexistent-file-for-test.txt")))
        #expect(model.state.display == .closed)
    }
}
