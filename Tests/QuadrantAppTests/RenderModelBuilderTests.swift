import Foundation
import QuadrantCore
import QuadrantUI
import Testing

@testable import QuadrantApp

@Suite struct RenderModelBuilderTests {
    @Test func browseModeHasNoLensAndShowsFocusedBranchContent() {
        let model = render(baseState())
        #expect(model.lens == nil)
        let top = model.quadrants[.top]
        #expect(top?.status == .ready)
        #expect(top?.stars.branch == np("/r/top/Alpha"))
        #expect(Set(top?.stars.items.map(\.path) ?? []) == [
            np("/r/top/Alpha/Docs"), np("/r/top/Alpha/note.txt"),
        ])
        #expect(top?.stars.items.contains { $0.kind == .file } == true)
        #expect(top?.floating.items.map(\.path) == [np("/r/top/Alpha/note.txt")])
        #expect(model.quadrants[.bottom]?.status == .empty)
    }

    @Test func folderLensFromSnapshotHasCrumbsFromRootToFolder() {
        var state = baseState()
        state.lens.isOpen = true
        state.lens.edge = .top
        state.lens.folders[.top] = np("/r/top/Alpha")
        let lens = render(state).lens
        #expect(lens?.mode == .folder(edge: .top, crumbs: [np("/r/top"), np("/r/top/Alpha")]))
        #expect(Set(lens?.rows.map(\.path) ?? []) == [np("/r/top/Alpha/Docs"), np("/r/top/Alpha/note.txt")])
        #expect(lens?.isLoading == false)
    }

    @Test func rootLensListsEverythingInThatLevel() {
        var state = baseState()
        state.lens.isOpen = true
        state.lens.edge = .top
        state.lens.folders[.top] = np("/r/top")
        state.lens.floor = np("/r/top")
        let lens = render(state).lens
        #expect(lens?.mode == .folder(edge: .top, crumbs: [np("/r/top")]))
        #expect(Set(lens?.rows.map(\.path) ?? []) == [
            np("/r/top/Alpha"), np("/r/top/Beta"), np("/r/top/readme.txt"),
        ])
    }

    @Test func deepFolderIsLoadingUntilCacheArrives() {
        var state = baseState()
        state.lens.isOpen = true
        state.lens.edge = .top
        state.lens.folders[.top] = np("/r/top/Alpha/Docs")
        let loading = render(state).lens
        #expect(loading?.isLoading == true)
        #expect(loading?.rows.isEmpty == true)

        let cache = [np("/r/top/Alpha/Docs"): [file("/r/top/Alpha/Docs/spec.md"), folder("/r/top/Alpha/Docs/sub")]]
        let loaded = render(state, cache: cache).lens
        #expect(loaded?.isLoading == false)
        #expect(Set(loaded?.rows.map(\.path) ?? []) == [np("/r/top/Alpha/Docs/spec.md"), np("/r/top/Alpha/Docs/sub")])
        #expect(loaded?.mode == .folder(edge: .top, crumbs: [np("/r/top"), np("/r/top/Alpha"), np("/r/top/Alpha/Docs")]))
    }

    @Test func lensFolderDrivesFloatingSlotsWhileOpen() {
        var state = baseState()
        state.lens.isOpen = true
        state.lens.edge = .top
        state.lens.folders[.top] = np("/r/top/Alpha/Docs")
        let cache = [np("/r/top/Alpha/Docs"): [file("/r/top/Alpha/Docs/spec.md")]]
        let top = render(state, cache: cache).quadrants[.top]
        #expect(top?.floating.items.map(\.path) == [np("/r/top/Alpha/Docs/spec.md")])
        #expect(top?.currentFolder == np("/r/top/Alpha/Docs"))
    }

    @Test func floatingKeepsLastLensFolderAfterLensCloses() {
        var state = baseState()
        state.lens.edge = nil
        state.lens.isOpen = false
        state.lens.folders[.top] = np("/r/top/Alpha/Docs")
        let cache = [np("/r/top/Alpha/Docs"): [file("/r/top/Alpha/Docs/spec.md")]]
        let model = render(state, cache: cache)
        #expect(model.lens == nil)
        #expect(model.quadrants[.top]?.currentFolder == np("/r/top/Alpha/Docs"))
        #expect(model.quadrants[.top]?.floating.items.map(\.path) == [np("/r/top/Alpha/Docs/spec.md")])
    }

    @Test func focusedBranchIsCurrentFolderWithoutLens() {
        #expect(render(baseState()).quadrants[.top]?.currentFolder == np("/r/top/Alpha"))
    }

    @Test func rootFolderShowsFoldersAndFiles() {
        var state = baseState()
        state.lens.edge = .top
        state.lens.folders[.top] = np("/r/top")
        let stars = render(state).quadrants[.top]?.stars
        #expect(stars?.branch == np("/r/top"))
        #expect(stars?.items.count == 3)
        #expect(stars?.items.contains { $0.kind == .folder } == true)
        #expect(stars?.items.contains { $0.kind == .file } == true)
    }

    @Test func filterModeListsMatchesWithEdge() {
        var state = baseState()
        state.filterText = "spec"
        state.lens.isOpen = true
        let model = render(state)
        #expect(model.filterText == "spec")
        #expect(model.lens?.mode == .filter(query: "spec"))
        #expect(model.lens?.rows == [LensRow(path: np("/r/top/Alpha/Docs/spec.md"), kind: .file, edge: .top, modifiedAt: fxNow)])
    }

    @Test func filterWithoutMatchHasEmptyRows() {
        var state = baseState()
        state.filterText = "zzz"
        state.lens.isOpen = true
        #expect(render(state).lens?.rows.isEmpty == true)
    }

    @Test func stashSlotMarksBrokenAndCopyProgressShowsOnlyWhileCopying() {
        var state = baseState()
        state.persistent.stash = [StashItem(targetPath: np("/definitely/missing.txt"), kind: .file, addedAt: fxNow)]
        var input = renderInputs(state: state)
        input.exists = .only([])
        input.copyProgress = 0.4
        #expect(RenderModelBuilder.build(input).stash.first?.isBroken == true)
        #expect(RenderModelBuilder.build(input).copyProgress == nil)
        state = reduce(state, .paste(items: [PasteItem(np("/a/x.txt"), kind: .file)], target: .folder(np("/r/top/Beta"))), now: fxNow).0
        #expect(!state.copies.isEmpty)
        input.state = state
        #expect(RenderModelBuilder.build(input).copyProgress == 0.4)
    }

    @Test func crumbsAndDepth() {
        #expect(RenderModelBuilder.crumbs(root: np("/r/top"), folder: np("/r/top")) == [np("/r/top")])
        #expect(RenderModelBuilder.crumbs(root: np("/r/top"), folder: np("/x/y")) == [np("/x/y")])
        #expect(RenderModelBuilder.depth(of: np("/r/top/a/b"), below: np("/r/top")) == 2)
    }

    @Test func halfHiddenAndSelectionAreCarried() {
        var state = baseState()
        state.display = .halfHidden
        let model = render(state, selection: np("/r/top/Beta"))
        #expect(model.isHalfHidden)
        #expect(model.keyboardSelection == np("/r/top/Beta"))
    }

    @Test func lensRowsCarryDateAndSize() {
        var state = baseState()
        state.lens.isOpen = true
        state.lens.edge = .top
        state.lens.folders[.top] = np("/r/top/Alpha/Docs")
        let when = Date(timeIntervalSince1970: 1_500_000)
        let cache = [np("/r/top/Alpha/Docs"): [
            FolderNode(path: np("/r/top/Alpha/Docs/a.md"), kind: .file, modifiedAt: when, size: 42)]]
        let row = render(state, cache: cache).lens?.rows.first
        #expect(row?.modifiedAt == when)
        #expect(row?.size == 42)
    }

    @Test func filterRowsCarryDate() {
        var state = baseState()
        state.filterText = "spec"
        state.lens.isOpen = true
        #expect(render(state).lens?.rows.first?.modifiedAt == fxNow)
    }
}
