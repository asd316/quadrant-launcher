import Foundation
import Testing
@testable import QuadrantCore

// R1.1 usage events
@Suite struct ReducerUsageTests {
    @Test func r1_1_focusBranchRecordsFolder() {
        let root = p("/r"), b = p("/r/a")
        let s = fullPanel(PersistentState(roots: [.top: root]))
        let (n, fx) = run(s, .focusBranch(.top, branch: b))
        #expect(usageEvents(fx) == [UsageEvent(path: b, action: .focusBranch, occurredAt: t1)])
        #expect(n.persistent.focus[root] == b)
    }

    @Test func r1_1_clickStarRecordsOpenStar() {
        let s = fullPanel(PersistentState(roots: [.top: p("/r")]))
        let (_, fx) = run(s, .clickStar(.top, star: p("/r/a/x")))
        #expect(usageEvents(fx) == [UsageEvent(path: p("/r/a/x"), action: .openStar, occurredAt: t1)])
    }

    @Test func r1_1_lensEnterRecordsEnterFolder() {
        var s = fullPanel(PersistentState(roots: [.top: p("/r")]))
        (s, _) = run(s, .clickStar(.top, star: p("/r/a/x")))
        let (_, fx) = run(s, .lensEnter(p("/r/a/x/y")))
        #expect(usageEvents(fx) == [UsageEvent(path: p("/r/a/x/y"), action: .enterFolder, occurredAt: t1)])
    }

    @Test func r1_1_copyOpenDragStashRecordOnFile() {
        let f = p("/r/f.txt")
        #expect(usageEvents(run(fullPanel(), .copyPath(f)).1).map(\.action) == [.copyPath])
        #expect(usageEvents(run(fullPanel(), .open(f)).1).map(\.action) == [.open])
        #expect(usageEvents(run(fullPanel(), .stashAdd(f, kind: .file)).1).map(\.action) == [.stash])
        var s = fullPanel()
        (s, _) = run(s, .beginDrag(f, kind: .file))
        #expect(usageEvents(run(s, .endDrag(.otherApp)).1).map(\.action) == [.dragOut])
    }

    @Test func r1_1_cancelledDragRecordsNothing() {
        var s = fullPanel()
        (s, _) = run(s, .beginDrag(p("/f"), kind: .file))
        #expect(usageEvents(run(s, .endDrag(.cancelled)).1).isEmpty)
    }
}

// R3 marks
@Suite struct ReducerMarkTests {
    let a = p("/r/a")

    @Test func r3_1_hideAndUnhide() {
        let (h, fx) = run(fullPanel(), .hide(a))
        #expect(h.persistent.marks[a] == MarkRecord(path: a, mark: .hidden, markedAt: t1))
        #expect(mutations(fx) == [.setMark(MarkRecord(path: a, mark: .hidden, markedAt: t1))])
        let (u, fx2) = run(h, .unhide(a))
        #expect(u.persistent.marks[a] == nil)
        #expect(mutations(fx2) == [.clearMark(a)])
    }

    @Test func r3_2_pinAndUnpin() {
        let (s, fx) = run(fullPanel(), .pin(a, region: PinRegion(pinnedCount: 0, capacity: 4)))
        #expect(s.persistent.marks[a]?.mark == .pinned)
        #expect(mutations(fx) == [.setMark(MarkRecord(path: a, mark: .pinned, markedAt: t1))])
        let (u, _) = run(s, .unpin(a))
        #expect(u.persistent.marks[a] == nil)
    }

    @Test func r3_3_pinRejectedWhenRegionFull() {
        let (s, fx) = run(fullPanel(), .pin(a, region: PinRegion(pinnedCount: 4, capacity: 4)))
        #expect(s.persistent.marks[a] == nil)
        #expect(fx == [.showRejection(.pinsFull(capacity: 4))])
    }

    @Test func r3_3_fullRejectionKeepsHiddenMark() {
        var s = fullPanel()
        (s, _) = run(s, .hide(a))
        let (n, fx) = run(s, .pin(a, region: PinRegion(pinnedCount: 6, capacity: 6)))
        #expect(n.persistent.marks[a]?.mark == .hidden)
        #expect(fx == [.showRejection(.pinsFull(capacity: 6))])
    }

    @Test func r3_4_pinHiddenRestoresThenPins() {
        var s = fullPanel()
        (s, _) = run(s, .hide(a))
        let (n, fx) = run(s, .pin(a, region: PinRegion(pinnedCount: 0, capacity: 4)))
        #expect(n.persistent.marks[a]?.mark == .pinned)
        #expect(mutations(fx) == [.clearMark(a), .setMark(MarkRecord(path: a, mark: .pinned, markedAt: t1))])
    }

    @Test func r3_4_hidePinnedUnpinsThenHides() {
        var s = fullPanel()
        (s, _) = run(s, .pin(a, region: PinRegion(pinnedCount: 0, capacity: 4)), at: t0)
        let (n, fx) = run(s, .hide(a))
        #expect(n.persistent.marks[a]?.mark == .hidden)
        #expect(mutations(fx) == [.clearMark(a), .setMark(MarkRecord(path: a, mark: .hidden, markedAt: t1))])
    }
}

// R4 stash and pinned slots
@Suite struct ReducerKeepAtHandTests {
    @Test func r4_1_stashEvictsOldest() {
        let s = fullPanel(PersistentState(stash: [stashItem("/1", t0), stashItem("/2", t0), stashItem("/3", t0)]))
        let (n, fx) = run(s, .stashAdd(p("/4"), kind: .file))
        #expect(n.persistent.stash.map(\.targetPath) == [p("/2"), p("/3"), p("/4")])
        #expect(mutations(fx) == [.setStash(n.persistent.stash)])
    }

    @Test func r4_1_stashReaddRefreshesInsteadOfDuplicating() {
        let s = fullPanel(PersistentState(stash: [stashItem("/1", t0), stashItem("/2", t0), stashItem("/3", t0)]))
        let (n, _) = run(s, .stashAdd(p("/1"), kind: .file))
        #expect(n.persistent.stash.map(\.targetPath) == [p("/2"), p("/3"), p("/1")])
        #expect(n.persistent.stash.last?.addedAt == t1)
    }

    @Test func r4_1_stashRemove() {
        let s = fullPanel(PersistentState(stash: [stashItem("/1", t0), stashItem("/2", t0)]))
        let (n, _) = run(s, .stashRemove(p("/1")))
        #expect(n.persistent.stash.map(\.targetPath) == [p("/2")])
    }

    @Test func r4_2_stashSurvivesClose() {
        var s = fullPanel()
        (s, _) = run(s, .stashAdd(p("/1"), kind: .file))
        (s, _) = run(s, .escape)
        #expect(s.display == .closed)
        #expect(s.persistent.stash.count == 1)
    }

    @Test func r4_3_pinnedSlotsRejectWhenFull() {
        let slots = (1...5).map { PinnedSlot(edge: .top, targetPath: p("/f\($0)"), addedAt: t0) }
        let s = fullPanel(PersistentState(pinnedSlots: slots))
        let (n, fx) = run(s, .pinSlot(.top, p("/new"), kind: .file))
        #expect(n.persistent.pinnedSlots == slots)
        #expect(fx == [.showRejection(.pinnedSlotsFull(.top, capacity: 5))])
    }

    @Test func r4_3_pinnedSlotsLimitIsPerEdge() {
        let slots = (1...5).map { PinnedSlot(edge: .top, targetPath: p("/f\($0)"), addedAt: t0) }
        let s = fullPanel(PersistentState(pinnedSlots: slots))
        let (n, fx) = run(s, .pinSlot(.left, p("/new"), kind: .file))
        #expect(n.persistent.pinnedSlots.count == 6)
        #expect(mutations(fx) == [.setPinnedSlots(.left, [PinnedSlot(edge: .left, targetPath: p("/new"), addedAt: t1)])])
    }

    @Test func r4_3_pinnedSlotsFilesOnlyAndUnpin() {
        let (_, fx) = run(fullPanel(), .pinSlot(.top, p("/dir"), kind: .folder))
        #expect(fx == [.showRejection(.pinnedSlotsFilesOnly)])
        var s = fullPanel()
        (s, _) = run(s, .pinSlot(.top, p("/f"), kind: .file))
        (s, _) = run(s, .pinSlot(.top, p("/f"), kind: .file))
        #expect(s.persistent.pinnedSlots.count == 1)
        (s, _) = run(s, .unpinSlot(.top, p("/f")))
        #expect(s.persistent.pinnedSlots.isEmpty)
    }

    @Test func r4_4_brokenItemsStillCount() {
        // Core stores no validity: a path that no longer exists on disk is just another row.
        let slots = (1...5).map { PinnedSlot(edge: .top, targetPath: p("/gone/f\($0)"), addedAt: t0) }
        let (_, fx) = run(fullPanel(PersistentState(pinnedSlots: slots)), .pinSlot(.top, p("/ok"), kind: .file))
        #expect(fx == [.showRejection(.pinnedSlotsFull(.top, capacity: 5))])
    }

    @Test func r4_4_stashEvictsOldestEvenIfNewerOnesAreBroken() {
        // /1 is oldest and valid, /2 is broken: /1 goes, the broken /2 stays.
        let s = fullPanel(PersistentState(stash: [stashItem("/1", t0), stashItem("/gone/2", t0), stashItem("/3", t0)]))
        let (n, _) = run(s, .stashAdd(p("/4"), kind: .file))
        #expect(n.persistent.stash.map(\.targetPath) == [p("/gone/2"), p("/3"), p("/4")])
    }
}

// R5, R6
@Suite struct ReducerMemoryTests {
    let root = p("/r")

    @Test func r5_1_focusKeyedByRootPath() {
        let s = fullPanel(PersistentState(roots: [.top: root]))
        let (n, fx) = run(s, .focusBranch(.top, branch: p("/r/a")))
        #expect(n.persistent.focus == [root: p("/r/a")])
        #expect(mutations(fx) == [.setFocus(root: root, branch: p("/r/a"))])
    }

    @Test func r5_2_drillPathKeyedByL3() {
        var s = fullPanel(PersistentState(roots: [.top: root]))
        (s, _) = run(s, .clickStar(.top, star: p("/r/a/x")))
        let (n, fx) = run(s, .lensEnter(p("/r/a/x/y")))
        #expect(n.persistent.drillPaths == [p("/r/a/x"): p("/r/a/x/y")])
        #expect(mutations(fx) == [.setDrillPath(l3: p("/r/a/x"), deep: p("/r/a/x/y"))])
        // reopening goes straight to the remembered place
        var again = n
        (again, _) = run(again, .dismissLens)
        let (o, fx2) = run(again, .clickStar(.top, star: p("/r/a/x")))
        #expect(o.lens.folders[.top] == p("/r/a/x/y"))
        #expect(fx2.contains(.loadChildren(p("/r/a/x/y"))))
    }

    @Test func r5_2_lensBackUpdatesDrillPathAndStopsAtStar() {
        var s = fullPanel(PersistentState(roots: [.top: root]))
        (s, _) = run(s, .clickStar(.top, star: p("/r/a/x")))
        (s, _) = run(s, .lensEnter(p("/r/a/x/y")))
        (s, _) = run(s, .lensBack)
        #expect(s.lens.folders[.top] == p("/r/a/x"))
        #expect(s.persistent.drillPaths[p("/r/a/x")] == p("/r/a/x"))
        let (n, fx) = run(s, .lensBack)
        #expect(n == s && fx.isEmpty)
    }

    @Test func r5_3_switchingRootKeepsOldState() {
        let old = p("/old")
        var s = fullPanel(PersistentState(roots: [.top: old], focus: [old: p("/old/a")],
                                          drillPaths: [p("/old/a/x"): p("/old/a/x/y")]))
        (s, _) = run(s, .hide(p("/old/b")))
        let (n, fx) = run(s, .setRoot(.top, p("/new")))
        #expect(n.persistent.roots[.top] == p("/new"))
        #expect(n.persistent.focus[old] == p("/old/a"))
        #expect(n.persistent.drillPaths[p("/old/a/x")] == p("/old/a/x/y"))
        #expect(n.persistent.marks[p("/old/b")] != nil)
        #expect(mutations(fx) == [.setRoot(.top, p("/new"))])
        // switching back restores focus lookup by path
        let (b, _) = run(n, .setRoot(.top, old))
        #expect(b.persistent.focus[b.persistent.roots[.top]!] == p("/old/a"))
    }

    @Test func r5_3_clearRoot() {
        let (n, fx) = run(fullPanel(PersistentState(roots: [.top: root])), .setRoot(.top, nil))
        #expect(n.persistent.roots[.top] == nil)
        #expect(mutations(fx) == [.setRoot(.top, nil)])
    }

    @Test func r2_6_focusBranchBecomesCurrentFolder() {
        let s = fullPanel(PersistentState(roots: [.top: root]))
        let (n, _) = run(s, .focusBranch(.top, branch: p("/r/a")))
        #expect(n.lens.folders[.top] == p("/r/a"))
    }

    @Test func r2_6_lensCloseKeepsCurrentFolder() {
        var s = fullPanel(PersistentState(roots: [.top: root]))
        let star = p("/r/a/x")
        (s, _) = run(s, .clickStar(.top, star: star))
        (s, _) = run(s, .lensEnter(p("/r/a/x/y")))
        (s, _) = run(s, .lensBack)
        #expect(s.lens.folders[.top] == star)
        (s, _) = run(s, .escape) // closes the lens, not the panel
        #expect(!s.lens.isOpen && s.display == .full)
        #expect(s.lens.folders[.top] == star)
    }

    @Test func r2_6_focusBranchLeavesOldLensFolder() {
        var s = fullPanel(PersistentState(roots: [.top: root]))
        (s, _) = run(s, .clickStar(.top, star: p("/r/a/x")))
        #expect(s.lens.isOpen)
        let (n, _) = run(s, .focusBranch(.top, branch: p("/r/b")))
        #expect(!n.lens.isOpen)
        #expect(n.lens.folders[.top] == p("/r/b"))
    }

    @Test func r6_2_drillPathFallsBackToExistingAncestor() {
        let l3 = p("/r/a/x")
        let s = fullPanel(PersistentState(roots: [.top: root], drillPaths: [l3: p("/r/a/x/y/z")]))
        let existence = PathExistence.only([l3, p("/r/a/x/y")])
        let (n, fx) = run(s, .clickStar(.top, star: l3, existence: existence))
        #expect(n.lens.folders[.top] == p("/r/a/x/y"))
        #expect(fx.contains(.loadChildren(p("/r/a/x/y"))))
        // the stored record is not rewritten (Data-Model: fallback is display-time only)
        #expect(n.persistent.drillPaths[l3] == p("/r/a/x/y/z"))
        #expect(mutations(fx).isEmpty)
    }

    @Test func r6_2_fallsBackToStarWhenNothingElseExists() {
        let l3 = p("/r/a/x")
        let s = fullPanel(PersistentState(roots: [.top: root], drillPaths: [l3: p("/r/a/x/y")]))
        let (n, _) = run(s, .clickStar(.top, star: l3, existence: .only([])))
        #expect(n.lens.folders[.top] == l3)
    }

    @Test func r6_3_missingRootIsReportedNotReplaced() {
        let s = fullPanel(PersistentState(roots: [.top: root]))
        let (n, fx) = run(s, .reportRootMissing(.top, true))
        #expect(n.missingRoots == [.top])
        #expect(n.persistent.roots[.top] == root)
        #expect(fx.isEmpty)
        // quadrant is inert while missing
        let (f, fx2) = run(n, .focusBranch(.top, branch: p("/r/a")))
        #expect(f == n && fx2.isEmpty)
        // reconfiguring clears it
        let (c, _) = run(n, .setRoot(.top, p("/other")))
        #expect(c.missingRoots.isEmpty)
        let (back, _) = run(n, .reportRootMissing(.top, false))
        #expect(back.missingRoots.isEmpty)
    }
}

// R7 and keyboard
@Suite struct ReducerPanelTests {
    @Test func summonOpensClosedPanel() {
        let (n, fx) = run(PanelState(), .summon)
        #expect(n.display == .full)
        #expect(fx == [.restoreFull])
    }

    @Test func r7_1_copyClosesPanel() {
        let (n, fx) = run(fullPanel(), .copyPath(p("/f")))
        #expect(n.display == .closed)
        #expect(fx == [
            .recordUsage(UsageEvent(path: p("/f"), action: .copyPath, occurredAt: t1)),
            .copyToPasteboard(p("/f")), .closePanel,
        ])
    }

    @Test func r7_2_dragStartEntersHalfHidden() {
        let (n, fx) = run(fullPanel(), .beginDrag(p("/f"), kind: .file))
        #expect(n.display == .halfHidden)
        #expect(fx == [.enterHalfHidden])
    }

    @Test func r7_3_dropOnOtherAppCloses() {
        var s = fullPanel()
        (s, _) = run(s, .beginDrag(p("/f"), kind: .file))
        let (n, fx) = run(s, .endDrag(.otherApp))
        #expect(n.display == .closed)
        #expect(fx.contains(.closePanel))
    }

    @Test func r7_3_dropOnStashRestoresFullWithLens() {
        var s = fullPanel(PersistentState(roots: [.top: p("/r")]))
        (s, _) = run(s, .clickStar(.top, star: p("/r/a/x")))
        (s, _) = run(s, .crossNavigate(.left))
        let before = s
        (s, _) = run(s, .beginDrag(p("/r/a/x/f"), kind: .file))
        let (n, fx) = run(s, .endDrag(.stash))
        #expect(n.display == .full)
        #expect(n.lens == before.lens)
        #expect(n.region == before.region)
        #expect(n.persistent.stash.map(\.targetPath) == [p("/r/a/x/f")])
        #expect(fx.last == .restoreFull)
        #expect(mutations(fx).count == 1)
    }

    @Test func r7_3_dropOnPinnedShelfPinsFileAndRestores() {
        var s = fullPanel()
        (s, _) = run(s, .beginDrag(p("/r/a/f.pdf"), kind: .file))
        let (n, fx) = run(s, .endDrag(.pinnedShelf(.left)))
        #expect(n.display == .full)
        #expect(n.persistent.pinnedSlots.map(\.targetPath) == [p("/r/a/f.pdf")])
        #expect(n.persistent.pinnedSlots.first?.edge == .left)
        #expect(fx.contains(.restoreFull))
    }

    @Test func r7_4_folderOnPinnedShelfIsRejectedAndRestores() {
        var s = fullPanel()
        (s, _) = run(s, .beginDrag(p("/r/a"), kind: .folder))
        let (n, fx) = run(s, .endDrag(.pinnedShelf(.top)))
        #expect(n.display == .full)
        #expect(n.persistent.pinnedSlots.isEmpty)
        #expect(fx.contains(.showRejection(.pinnedSlotsFilesOnly)))
    }

    @Test func r7_3_cancelRestoresPreDragState() {
        var s = fullPanel()
        (s, _) = run(s, .setFilter("abc"))
        let before = s
        (s, _) = run(s, .beginDrag(p("/f"), kind: .file))
        let (n, fx) = run(s, .endDrag(.cancelled))
        #expect(n == before)
        #expect(fx == [.restoreFull])
    }

    @Test func r7_4_dropOnQuadrantIsCancel() {
        var s = fullPanel()
        (s, _) = run(s, .beginDrag(p("/f"), kind: .folder))
        let (a, fa) = run(s, .endDrag(.quadrant(.left)))
        let (b, fb) = run(s, .endDrag(.cancelled))
        #expect(a == b && fa == fb)
        #expect(a.persistent == PersistentState())
    }

    @Test func r7_5_escClearsFilterThenLensThenPanel() {
        var s = fullPanel(PersistentState(roots: [.top: p("/r")]))
        (s, _) = run(s, .clickStar(.top, star: p("/r/a/x")))
        (s, _) = run(s, .setFilter("q"))
        (s, _) = run(s, .escape)
        #expect(s.filterText.isEmpty && s.lens.isOpen && s.display == .full)
        (s, _) = run(s, .escape)
        #expect(!s.lens.isOpen && s.display == .full)
        let (n, fx) = run(s, .escape)
        #expect(n.display == .closed)
        #expect(fx == [.closePanel])
    }

    @Test func r7_5_escFromFilterWithLensClosedReturnsToBrowse() {
        var s = fullPanel()
        (s, _) = run(s, .setFilter("q"))
        #expect(s.lens.isOpen)
        (s, _) = run(s, .escape)
        #expect(!s.lens.isOpen && s.filterText.isEmpty && s.display == .full)
    }

    @Test func r7_6_openClosesPanel() {
        let (n, fx) = run(fullPanel(), .open(p("/f")))
        #expect(n.display == .closed)
        #expect(fx == [
            .recordUsage(UsageEvent(path: p("/f"), action: .open, occurredAt: t1)),
            .openWithDefaultApp(p("/f")), .closePanel,
        ])
    }

    @Test func crossNav_jumpTable() {
        let table: [(KeyboardRegion, Direction, KeyboardRegion)] = [
            (.center, .up, .top), (.center, .down, .bottom), (.center, .left, .left), (.center, .right, .right),
            (.top, .up, .top), (.top, .down, .center), (.top, .left, .left), (.top, .right, .right),
            (.bottom, .up, .center), (.bottom, .down, .bottom), (.bottom, .left, .left), (.bottom, .right, .right),
            (.left, .up, .top), (.left, .down, .bottom), (.left, .left, .left), (.left, .right, .center),
            (.right, .up, .top), (.right, .down, .bottom), (.right, .left, .center), (.right, .right, .right),
        ]
        for (from, dir, to) in table {
            var s = fullPanel()
            s.region = from
            let (n, fx) = run(s, .crossNavigate(dir))
            #expect(n.region == to, "\(from) \(dir)")
            #expect(fx.isEmpty)
        }
    }

    @Test func crossNav_regionSurvivesCloseAndReopen() {
        var s = fullPanel()
        (s, _) = run(s, .crossNavigate(.right))
        (s, _) = run(s, .escape)
        (s, _) = run(s, .summon)
        #expect(s.region == .right)
    }

    @Test func ignoredWhileClosed() {
        let (n, fx) = run(PanelState(), .copyPath(p("/f")))
        #expect(n == PanelState() && fx.isEmpty)
    }
}

// R8 paste and copy
@Suite struct ReducerPasteTests {
    let dest = p("/r/a")
    let f1 = PasteItem(p("/x/one.pdf"), kind: .file)
    let f2 = PasteItem(p("/x/dir"), kind: .folder)

    @Test func r8_1_copyNodeWritesPasteboardKeepsPanelOpenNoUsage() {
        let (n, fx) = run(fullPanel(), .copyNode(p("/x/one.pdf"), kind: .file))
        #expect(fx == [.writeNodeToPasteboard(p("/x/one.pdf"), kind: .file)])
        #expect(n.display == .full)
        #expect(usageEvents(fx).isEmpty)
    }

    @Test func r8_2_pasteOnFolderEmitsCopyToKeepsPanelOpen() {
        let (n, fx) = run(fullPanel(), .paste(items: [f1, f2], target: .folder(dest)))
        #expect(fx == [.copyTo(sources: [f1.path, f2.path], destination: dest)])
        #expect(n.display == .full)
        #expect(n.persistent.stash.isEmpty)
    }

    @Test func r8_3_pasteToStashAddsInOrderAndEvicts() {
        let old = (1...3).map { stashItem("/s/\($0)", t0.addingTimeInterval(Double($0))) }
        let s = fullPanel(PersistentState(stash: old))
        let (n, fx) = run(s, .paste(items: [f1, f2], target: .stash))
        #expect(n.persistent.stash.map(\.targetPath) == [p("/s/3"), f1.path, f2.path]) // R4.1: oldest evicted
        #expect(usageEvents(fx).map(\.action) == [.stash, .stash])
        #expect(!fx.contains { if case .copyTo = $0 { true } else { false } })
    }

    @Test func r8_4_emptyPasteRejectedForBothTargets() {
        for target in [PasteTarget.stash, .folder(dest)] {
            let (n, fx) = run(fullPanel(), .paste(items: [], target: target))
            #expect(fx == [.showRejection(.clipboardEmpty)])
            #expect(n.persistent.stash.isEmpty)
            #expect(n.copies.isEmpty)
        }
    }

    @Test func r8_6_pasteIntoItselfOrDescendantRejectedCopiesNothing() {
        let parent = PasteItem(p("/r"), kind: .folder)
        let same = PasteItem(dest, kind: .folder)
        for bad in [parent, same] {
            let (n, fx) = run(fullPanel(), .paste(items: [f1, bad], target: .folder(dest)))
            #expect(fx == [.showRejection(.copyIntoItself)])
            #expect(n.copies.isEmpty)
        }
    }

    @Test func r8_6_siblingWithSharedPrefixIsNotAncestor() {
        let (_, fx) = run(fullPanel(), .paste(items: [PasteItem(p("/r/a b"), kind: .folder)], target: .folder(dest)))
        #expect(fx == [.copyTo(sources: [p("/r/a b")], destination: dest)])
    }

    @Test func r8_7_progressTrackedUntilFinished() {
        let (n, _) = run(fullPanel(), .paste(items: [f1], target: .folder(dest)))
        #expect(n.copies == [CopyJob(sources: [f1.path], destination: dest)])
        let (done, _) = run(n, .copyFinished(destination: dest, result: .success(copiedNames: ["one.pdf"])))
        #expect(done.copies.isEmpty)
    }

    @Test func r8_7_successShowsNoticeWithFolderName() {
        let (_, fx) = run(fullPanel(), .copyFinished(destination: dest, result: .success(copiedNames: ["one.pdf"])))
        #expect(fx.contains(.showNotice(.copiedTo(folderName: "a"))))
    }

    @Test func r8_7_failureShowsReasonClearsProgressNoUsage() {
        let (n, _) = run(fullPanel(), .paste(items: [f1], target: .folder(dest)))
        let (done, fx) = run(n, .copyFinished(destination: dest, result: .failure(reason: "磁盘已满")))
        #expect(fx == [.showNotice(.copyFailed(reason: "磁盘已满"))])
        #expect(done.copies.isEmpty)
    }

    @Test func r8_8_successRecordsCopyToOnDestination() {
        let (_, fx) = run(fullPanel(), .copyFinished(destination: dest, result: .success(copiedNames: ["x"])))
        #expect(usageEvents(fx) == [UsageEvent(path: dest, action: .copyTo, occurredAt: t1)])
    }

    @Test func r8_8_finishedAfterPanelClosedStillRecords() {
        let (_, fx) = run(PanelState(), .copyFinished(destination: dest, result: .success(copiedNames: ["x"])))
        #expect(usageEvents(fx).map(\.action) == [.copyTo])
    }
}
