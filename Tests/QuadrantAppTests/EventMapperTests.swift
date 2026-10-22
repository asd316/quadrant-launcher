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

    @Test func doubleClickFileOpens() {
        #expect(map(.doubleClick(np("/r/top/readme.txt"), .file)) == ["open(/r/top/readme.txt)"])
    }

    @Test func doubleClickFolderOpensInFinderEvenWithLensOpen() {
        var state = baseState()
        state.lens.isOpen = true
        state.lens.edge = .top
        state.lens.folders[.top] = np("/r/top/Alpha")
        #expect(map(.doubleClick(np("/r/top/Alpha/Docs"), .folder), state) == ["open(/r/top/Alpha/Docs)"])
        #expect(map(.doubleClick(np("/r/top/Alpha"), .folder)) == ["open(/r/top/Alpha)"])
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
