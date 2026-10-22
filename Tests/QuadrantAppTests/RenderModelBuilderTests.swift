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
        #expect(top?.stars.items.map(\.path) == [np("/r/top/Alpha/Docs")])
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
        let floating = render(state, cache: cache).quadrants[.top]?.floating.items.map(\.path)
        #expect(floating == [np("/r/top/Alpha/Docs/spec.md")])
    }

    @Test func filterModeListsMatchesWithEdge() {
        var state = baseState()
        state.filterText = "spec"
        state.lens.isOpen = true
        let model = render(state)
        #expect(model.filterText == "spec")
        #expect(model.lens?.mode == .filter(query: "spec"))
        #expect(model.lens?.rows == [LensRow(path: np("/r/top/Alpha/Docs/spec.md"), kind: .file, edge: .top)])
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
}
