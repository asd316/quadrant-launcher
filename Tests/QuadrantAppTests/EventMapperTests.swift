import QuadrantCore
import QuadrantUI
import Testing

@testable import QuadrantApp

@Suite struct EventMapperTests {
    private func map(_ event: UIEvent, _ state: PanelState? = nil, capacity: [Edge: Int] = [.top: 3]) -> [String] {
        describe(EventMapper.commands(for: event, in: mapping(state ?? baseState(), capacity: capacity)))
    }

    @Test func simpleEventsMapOneToOne() {
        let alpha = np("/r/top/Alpha")
        #expect(map(.clickBranch(.top, alpha)) == ["focusBranch(top,/r/top/Alpha)"])
        #expect(map(.clickStar(.top, alpha)) == ["clickStar(top,/r/top/Alpha)"])
        #expect(map(.openLens(.top, folder: alpha)) == ["openLens(top,/r/top/Alpha)"])
        #expect(map(.select(alpha)) == ["select(/r/top/Alpha)"])
        #expect(map(.copyPath(alpha)) == ["copyPath(/r/top/Alpha)"])
        #expect(map(.stashRemove(alpha)) == ["stashRemove(/r/top/Alpha)"])
        #expect(map(.revealInFinder(alpha)) == ["reveal(/r/top/Alpha)"])
        #expect(map(.dragBegan(alpha, .folder)) == ["beginDrag(/r/top/Alpha)"])
        #expect(map(.dragEnded(.stash)) == ["endDrag(stash)"])
        #expect(map(.starCapacityMeasured(.top, 7)) == ["starCapacity(top,7)"])
        #expect(map(.hideBranch(.top, alpha)) == ["hide(/r/top/Alpha)"])
        #expect(map(.unpinFolder(alpha)) == ["unpin(/r/top/Alpha)"])
        #expect(map(.pinSlot(.top, np("/r/top/readme.txt"))) == ["pinSlot(top,/r/top/readme.txt)"])
    }

    @Test func backgroundClickClosesOnlyTheLens() {
        var state = baseState()
        #expect(map(.backgroundClicked, state) == [])
        state.lens.isOpen = true
        state.lens.edge = .top
        state.lens.folders[.top] = np("/r/top/Alpha")
        #expect(map(.backgroundClicked, state) == ["dismissLens"])
        state.filterText = "no"
        #expect(map(.backgroundClicked, state) == ["setFilter()", "dismissLens"])
    }

    @Test func doubleClickFileOpens() {
        #expect(map(.doubleClick(np("/r/top/readme.txt"), .file)) == ["open(/r/top/readme.txt)"])
    }

    @Test func doubleClickFolderOpensInFinderWithoutCoreClose() {
        var state = baseState()
        state.lens.isOpen = true
        state.lens.edge = .top
        state.lens.folders[.top] = np("/r/top/Alpha")
        #expect(map(.doubleClick(np("/r/top/Alpha/Docs"), .folder), state) == ["openFolder(/r/top/Alpha/Docs)"])
    }

    @Test func revealGoesToApp() {
        #expect(map(.revealInFinder(np("/r/top/readme.txt"))) == ["reveal(/r/top/readme.txt)"])
    }

    @Test func externalDropOnStashStashesExistingPathsWithKinds() {
        var ctx = mapping(baseState())
        ctx.kindOf = { $0.raw == "/gone" ? nil : ($0.raw.hasSuffix(".txt") ? .file : .folder) }
        let cmds = EventMapper.commands(for: .externalDrop([np("/a/x.txt"), np("/gone"), np("/a/dir")], on: .stash), in: ctx)
        #expect(describe(cmds) == ["stashAdd(/a/x.txt)", "stashAdd(/a/dir)"])
    }

    @Test func externalDropOnShelfPinsSlotPerPath() {
        var ctx = mapping(baseState())
        ctx.kindOf = { $0.raw.hasSuffix(".txt") ? .file : .folder }
        let cmds = EventMapper.commands(for: .externalDrop([np("/a/x.txt"), np("/a/dir")], on: .pinnedShelf(.left)), in: ctx)
        #expect(describe(cmds) == ["pinSlot(left,/a/x.txt)", "pinSlot(left,/a/dir)"])
        if case .intent(.pinSlot(_, _, let kind)) = cmds[1] { #expect(kind == .folder) } else { Issue.record("not pinSlot") }
    }

    @Test func singleLensEnterStillEntersLens() {
        #expect(map(.lensEnter(np("/r/top/Alpha/Docs"))) == ["lensEnter(/r/top/Alpha/Docs)"])
    }


    @Test func pinnedShelfDropReachesCore() {
        #expect(map(.dragEnded(.pinnedShelf(.left))) == ["endDrag(pinnedShelf(QuadrantCore.Edge.left))"])
    }

    @Test func lensBackWithoutTargetGoesOneLevel() {
        #expect(map(.lensBack(to: nil)) == ["lensBack"])
    }

    @Test func lensBackToCrumbRepeatsUntilThere() {
        var state = baseState()
        state.lens.isOpen = true
        state.lens.edge = .top
        state.lens.folders[.top] = np("/r/top/Alpha/Docs/deep/er")
        #expect(map(.lensBack(to: np("/r/top/Alpha")), state) == Array(repeating: "lensBack", count: 3))
        #expect(map(.lensBack(to: np("/r/top/Alpha/Docs/deep/er")), state) == [])
        #expect(map(.lensBack(to: np("/elsewhere")), state) == [])
    }

    @Test func showAllBranchesUnhidesOnlyThatRootsBranches() {
        var state = baseState()
        state.persistent.marks[np("/r/top/Beta")] = MarkRecord(path: np("/r/top/Beta"), mark: .hidden, markedAt: fxNow)
        state.persistent.marks[np("/r/top/Alpha/Docs")] = MarkRecord(path: np("/r/top/Alpha/Docs"), mark: .hidden, markedAt: fxNow)
        state.persistent.marks[np("/other/X")] = MarkRecord(path: np("/other/X"), mark: .hidden, markedAt: fxNow)
        #expect(map(.showAllBranches(.top), state) == ["unhide(/r/top/Beta)"])
    }

    @Test func pinBranchCountsAgainstBranchCapacity() {
        var state = baseState()
        state.persistent.marks[np("/r/top/Alpha")] = MarkRecord(path: np("/r/top/Alpha"), mark: .pinned, markedAt: fxNow)
        #expect(map(.pinFolder(.top, np("/r/top/Beta")), state) == ["pin(/r/top/Beta,1/4)"])
    }

    @Test func pinStarCountsAgainstMeasuredStarCapacity() {
        #expect(map(.pinFolder(.top, np("/r/top/Alpha/Docs")), capacity: [.top: 5]) == ["pin(/r/top/Alpha/Docs,0/5)"])
    }
}
