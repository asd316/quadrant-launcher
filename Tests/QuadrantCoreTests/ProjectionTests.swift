import Foundation
import Testing

@testable import QuadrantCore

private typealias F = Fixture

private func mark(_ path: String, _ kind: FolderMark, at days: Double = 1) -> (NodePath, MarkRecord) {
    let p = NodePath(path)
    return (p, MarkRecord(path: p, mark: kind, markedAt: F.ago(days: days)))
}

private func state(
    roots: [Edge: String] = [:], marks: [(NodePath, MarkRecord)] = [], focus: [String: String] = [:],
    drill: [String: String] = [:], pinnedSlots: [PinnedSlot] = []
) -> PersistentState {
    PersistentState(
        roots: roots.mapValues { NodePath($0) },
        marks: Dictionary(uniqueKeysWithValues: marks),
        focus: Dictionary(uniqueKeysWithValues: focus.map { (NodePath($0.key), NodePath($0.value)) }),
        drillPaths: Dictionary(uniqueKeysWithValues: drill.map { (NodePath($0.key), NodePath($0.value)) }),
        pinnedSlots: pinnedSlots)
}

private func projectLeft(
    _ s: PersistentState, events: [UsageEvent] = [], starCapacity: Int = 32,
    current: String? = nil, children: [FolderNode]? = nil
) -> EdgeProjection {
    Projection.project(
        edge: .left, state: s,
        input: EdgeInput(
            snapshot: F.knowledgeBase, starCapacity: starCapacity, currentFolder: current.map { NodePath($0) },
            currentFolderChildren: children),
        usage: F.index(events), now: F.now, exists: { _ in false })
}

private let leftState = state(roots: [.left: F.kbRoot])

// MARK: Branches

@Test func r2_1_leftRightShowSixBranchesAndRestIsTruncated() {
    let result = projectLeft(leftState).branches
    #expect(result.items.count == 6)
    #expect(result.truncatedCount == 4)
}

@Test func r2_1_topBottomShowFourBranches() {
    let result = Projection.project(
        edge: .top, state: state(roots: [.top: F.downloads]),
        input: EdgeInput(snapshot: F.downloadsSnapshot, starCapacity: 10),
        usage: F.index([]), now: F.now, exists: { _ in false }
    ).branches
    #expect(result.items.count == 4)
    #expect(result.truncatedCount == 4)  // 8 branches, 4 shown
}

@Test func r2_1_highestWeightGoesInTheMiddle() {
    let events = (0..<5).map { _ in F.event("\(F.kbRoot)/todo") } + [F.event("\(F.kbRoot)/AI-chats")]
    let result = projectLeft(leftState, events: events).branches
    #expect(result.items[0].name == "todo")
    #expect(result.items[1].name == "AI-chats")
    // Six slots: rank 0 at slot index 2 (the middle), rank 1 at 3, rank 2 at 1.
    let visual = result.visualOrder.map(\.name)
    #expect(visual[2] == "todo")
    #expect(visual[3] == "AI-chats")
}

@Test func r2_1_centerOutArrangement() {
    #expect(CenterOut.arrange([0, 1, 2, 3]) == [2, 0, 1, 3])
    #expect(CenterOut.arrange([0, 1, 2, 3, 4, 5]) == [4, 2, 0, 1, 3, 5])
    #expect(CenterOut.arrange([0, 1, 2]) == [2, 0, 1])
    #expect(CenterOut.arrange([0]) == [0])
    #expect(CenterOut.arrange([Int]()) == [])
}

@Test func r1_4_branchesSortedByWeightThenFinderName() {
    // Cold start with equal mtimes: names decide, in Finder order.
    let result = projectLeft(leftState).branches
    let names = result.items.map(\.name)
    #expect(names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
}

@Test func r2_2_focusedBranchIsFlagged() {
    let s = state(roots: [.left: F.kbRoot], focus: [F.kbRoot: F.workbench])
    let items = projectLeft(s).branches.items
    #expect(items.filter(\.isFocused).map(\.name) == ["0-projects"])
}

@Test func r3_1_hiddenBranchesAreExcludedAndDoNotConsumeCapacity() {
    let hidden = ["todo", "H-sharing", "F-guides"].map { mark("\(F.kbRoot)/\($0)", .hidden) }
    let result = projectLeft(state(roots: [.left: F.kbRoot], marks: hidden)).branches
    #expect(result.hiddenCount == 3)
    #expect(result.items.count == 6)  // 7 visible, 6 fit
    #expect(result.truncatedCount == 1)
    #expect(!result.items.map(\.name).contains("todo"))
}

@Test func r3_1_hiddenCountIsZeroWithoutMarks() {
    #expect(projectLeft(leftState).branches.hiddenCount == 0)
}

@Test func r3_2_pinnedBranchAlwaysShownFirstOrderedByMarkTime() {
    // Both pinned branches have zero usage; a heavily used branch must not push them out.
    let marks = [
        mark("\(F.kbRoot)/H-sharing", .pinned, at: 1), mark("\(F.kbRoot)/1-background", .pinned, at: 5),
    ]
    let events = (0..<9).map { _ in F.event("\(F.kbRoot)/todo") }
    let items = projectLeft(state(roots: [.left: F.kbRoot], marks: marks), events: events).branches.items
    #expect(items.prefix(2).map(\.name) == ["1-background", "H-sharing"])
    #expect(items.prefix(2).allSatisfy { $0.isPinned })
    #expect(items[2].name == "todo")
    #expect(items.count == 6)
}

@Test func r2_3_pinnedTakePlacesFirstThenWeightFillsTheRest() {
    let marks = ["todo", "H-sharing", "1-background", "2-research"].map { mark("\(F.kbRoot)/\($0)", .pinned) }
    let events = (0..<3).map { _ in F.event("\(F.kbRoot)/AI-chats") } + [F.event("\(F.kbRoot)/3-methods")]
    let result = projectLeft(state(roots: [.left: F.kbRoot], marks: marks), events: events).branches
    #expect(result.items.count == 6)
    #expect(result.items.filter(\.isPinned).count == 4)
    #expect(result.items.suffix(2).map(\.name) == ["AI-chats", "3-methods"])
    #expect(result.truncatedCount == 4)
}

@Test func r3_3_pinnedAtCapacityLeavesNoRoomAndEverythingElseIsTruncated() {
    let marks = ["todo", "H-sharing", "1-background", "2-research", "AI-chats", "3-methods"]
        .map { mark("\(F.kbRoot)/\($0)", .pinned) }
    let result = projectLeft(state(roots: [.left: F.kbRoot], marks: marks)).branches
    #expect(result.items.count == 6)
    #expect(result.items.allSatisfy { $0.isPinned })
    #expect(result.truncatedCount == 4)
}

@Test func r3_3_pinnedOverCapacityIsClampedNeverExceedsDisplayLimit() {
    // Corrupt state: 5 pinned on a 4-slot edge. Display still respects the limit.
    let marks = ["截图", "发票", "临时", "数据导出", "字体"].map { mark("\(F.downloads)/\($0)", .pinned) }
    let result = Projection.project(
        edge: .top, state: state(roots: [.top: F.downloads], marks: marks),
        input: EdgeInput(snapshot: F.downloadsSnapshot, starCapacity: 5),
        usage: F.index([]), now: F.now, exists: { _ in false }
    ).branches
    #expect(result.items.count == 4)
}

// MARK: Stars

private let wbState = state(roots: [.left: F.kbRoot], focus: [F.kbRoot: F.workbench])

@Test func r2_2_noFocusMeansNoStars() {
    let stars = projectLeft(leftState).stars
    #expect(stars.items.isEmpty)
    #expect(stars.branch == nil)
}

@Test func r2_2_starsComeFromFocusedBranchOnly() {
    let stars = projectLeft(wbState, starCapacity: 100).stars
    #expect(stars.branch == NodePath(F.workbench))
    #expect(stars.items.count == 37)
    #expect(stars.truncatedCount == 0)
    #expect(stars.items.allSatisfy { $0.path.raw.hasPrefix(F.workbench + "/") })
}

@Test func r2_2_edgesAreIndependent() {
    let both = state(
        roots: [.left: F.kbRoot, .top: F.downloads],
        focus: [F.kbRoot: F.workbench, F.downloads: "\(F.downloads)/论文"])
    let result = Projection.project(
        state: both,
        inputs: [
            .left: EdgeInput(snapshot: F.knowledgeBase, starCapacity: 32),
            .top: EdgeInput(snapshot: F.downloadsSnapshot, starCapacity: 10),
        ],
        usage: F.index([]), now: F.now, exists: { _ in false })
    #expect(result[.left]?.stars.branch == NodePath(F.workbench))
    #expect(result[.top]?.stars.items.map(\.name).sorted() == ["已读", "待读"])
    #expect(result[.right]?.isEmpty == true)
}

@Test func r2_2_focusedBranchWithoutSubfoldersHasNoStars() {
    let s = state(roots: [.top: F.downloads], focus: [F.downloads: "\(F.downloads)/安装包"])
    let result = Projection.project(
        edge: .top, state: s, input: EdgeInput(snapshot: F.downloadsSnapshot, starCapacity: 10),
        usage: F.index([]), now: F.now, exists: { _ in false })
    #expect(result.stars.items.isEmpty)
    #expect(result.stars.branch == NodePath("\(F.downloads)/安装包"))
}

@Test func r2_3_starsBeyondCapacityAreTruncatedByWeight() {
    // 37 L3 folders, 32 fit: 5 are cut. The two used ones must survive.
    let events = [F.event("\(F.workbench)/project-33"), F.event("\(F.workbench)/project-20", daysAgo: 10)]
    let stars = projectLeft(wbState, events: events, starCapacity: 32).stars
    #expect(stars.items.count == 32)
    #expect(stars.truncatedCount == 5)
    let names = stars.items.map(\.name)
    #expect(names.prefix(2) == ["project-33", "project-20"])
}

@Test func r1_5_starTiesSortByFinderOrderAndShareBrightness() {
    let stars = projectLeft(wbState, starCapacity: 100).stars.items
    #expect(stars.map(\.name).prefix(4) == ["budget-app", "habit-tracker", "Photo Archive", "project-01"].sorted {
        $0.localizedStandardCompare($1) == .orderedAscending
    }.prefix(4))
    #expect(Set(stars.map { $0.brightness }).count == 1)  // equal weight, equal brightness
}

@Test func r1_2_starBrightnessFollowsRolledUpUsage() {
    // Deep usage under quadrant-file-launcher lights the star up (roll-up), others stay at the minimum.
    let deep = "\(F.launcher)/00-project-context/Glossary（术语表）.md"
    let events = (0..<4).map { _ in F.event(deep, .copyPath) } + [F.event("\(F.workbench)/Photo Archive")]
    let stars = projectLeft(wbState, events: events).stars.items
    let launcher = stars.first { $0.name == "quadrant-file-launcher" }
    let material = stars.first { $0.name == "Photo Archive" }
    let filler = stars.first { $0.name == "project-05" }
    #expect(launcher?.brightness == 1)
    #expect(abs((material?.brightness ?? 0) - 0.4375) < 1e-9)
    #expect(filler?.brightness == 0.25)
}

@Test func r2_2_starHasDrillPathFlag() {
    let s = state(
        roots: [.left: F.kbRoot], focus: [F.kbRoot: F.workbench],
        drill: [F.launcher: "\(F.launcher)/00-project-context"])
    let stars = projectLeft(s, starCapacity: 100).stars.items
    #expect(stars.first { $0.name == "quadrant-file-launcher" }?.hasDrillPath == true)
    #expect(stars.filter(\.hasDrillPath).count == 1)
}

@Test func r3_2_pinnedStarsAreNeverTruncated() {
    let pinned = mark("\(F.workbench)/project-33", .pinned)
    let busy = (0..<5).map { _ in F.event("\(F.workbench)/project-01") }
    let s = state(roots: [.left: F.kbRoot], marks: [pinned], focus: [F.kbRoot: F.workbench])
    let stars = projectLeft(s, events: busy, starCapacity: 3).stars
    #expect(stars.items.map(\.name).first == "project-33")
    #expect(stars.items.first?.isPinned == true)
    #expect(stars.items.count == 3)
    #expect(stars.truncatedCount == 34)
}

@Test func r3_3_pinnedStarsAtCapacityLeaveNoRoom() {
    let marks = ["project-01", "project-02"].map { mark("\(F.workbench)/\($0)", .pinned) }
    let s = state(roots: [.left: F.kbRoot], marks: marks, focus: [F.kbRoot: F.workbench])
    let stars = projectLeft(s, events: [F.event("\(F.workbench)/project-09")], starCapacity: 2).stars
    #expect(stars.items.allSatisfy { $0.isPinned })
    #expect(stars.items.count == 2)
}

// MARK: Floating slots

private let papers = "\(F.downloads)/论文"

private func projectTop(_ s: PersistentState, events: [UsageEvent] = [], current: String?, children: [FolderNode]? = nil)
    -> EdgeProjection
{
    Projection.project(
        edge: .top, state: s,
        input: EdgeInput(
            snapshot: F.downloadsSnapshot, starCapacity: 10, currentFolder: current.map { NodePath($0) },
            currentFolderChildren: children),
        usage: F.index(events), now: F.now, exists: { _ in false })
}

private let topState = state(roots: [.top: F.downloads])

@Test func r2_5_floatingShowsTopFiveDirectFilesAndCountsTheRest() {
    let floating = projectTop(topState, current: papers).floating
    #expect(floating.items.count == 5)
    #expect(floating.truncatedCount == 35)
    #expect(floating.items.allSatisfy { $0.name.hasPrefix("paper-") })
}

@Test func r2_5_floatingOrderedByWeight() {
    let events = [F.event("\(papers)/paper-40.pdf", .open), F.event("\(papers)/paper-40.pdf", .open), F.event("\(papers)/paper-12.pdf", .open)]
    let floating = projectTop(topState, events: events, current: papers).floating
    #expect(floating.items.prefix(2).map(\.name) == ["paper-40.pdf", "paper-12.pdf"])
}

@Test func r2_5_floatingUsesRecencyOnColdStart() {
    let current = F.folder("/x", [F.file("/x/a.txt"), F.file("/x/b.txt", modified: F.ago(days: 1))])
    let floating = Projection.projectFloating(
        input: EdgeInput(snapshot: nil, starCapacity: 0, currentFolder: NodePath("/x"), currentFolderChildren: current.children),
        usage: F.index([]), now: F.now)
    #expect(floating.items.map(\.name) == ["b.txt", "a.txt"])
}

@Test func r2_5_floatingEmptyWhenFolderHasNoDirectFiles() {
    let floating = projectTop(topState, current: "\(F.downloads)/课程").floating
    #expect(floating == .empty)
}

@Test func r2_5_floatingIgnoresSubfolders() {
    // 论文 has 2 subfolders and 40 files; subfolders never take floating slots.
    let floating = projectTop(topState, current: papers).floating
    #expect(!floating.items.contains { $0.name == "已读" || $0.name == "待读" })
}

@Test func r2_5_floatingEmptyWithoutCurrentFolder() {
    #expect(projectTop(topState, current: nil).floating == .empty)
}

@Test func r2_5_floatingShowsFewerThanFiveWithoutTruncation() {
    let floating = projectTop(topState, current: "\(F.downloads)/安装包").floating
    #expect(floating.items.count == 3)
    #expect(floating.truncatedCount == 0)
}

@Test func r2_5_floatingForFolderDeeperThanSnapshotUsesProvidedChildren() {
    let deep = "\(F.launcher)/00-project-context"
    let files = [F.file("\(deep)/Context.md"), F.file("\(deep)/Glossary.md")]
    let result = projectLeft(leftState, current: deep, children: files + [F.folder("\(deep)/sub")]).floating
    #expect(Set(result.items.map(\.name)) == ["Context.md", "Glossary.md"])
    // Without provided children a folder beyond the snapshot yields nothing.
    #expect(projectLeft(leftState, current: deep).floating == .empty)
}

// MARK: Pinned slots

private func slot(_ edge: Edge, _ path: String, days: Double) -> PinnedSlot {
    PinnedSlot(edge: edge, targetPath: NodePath(path), addedAt: F.ago(days: days))
}

@Test func r6_1_pinnedSlotBrokenWhenMissingFromSnapshotAndDisk() {
    let s = state(
        roots: [.top: F.downloads],
        pinnedSlots: [
            slot(.top, "\(F.downloads)/报价单.xlsx", days: 3),
            slot(.top, "\(F.downloads)/已删除.pdf", days: 2),
        ])
    let items = Projection.projectPinnedSlots(
        edge: .top, state: s, snapshot: F.downloadsSnapshot, exists: { _ in false })
    #expect(items.map(\.isBroken) == [false, true])
    #expect(items.map(\.name) == ["报价单.xlsx", "已删除.pdf"])
}

@Test func r6_1_pinnedSlotDeeperThanSnapshotUsesExistsClosure() {
    let alive = "\(F.launcher)/00-project-context/Context.md"
    let gone = "\(F.launcher)/00-project-context/Gone.md"
    let s = state(roots: [.left: F.kbRoot], pinnedSlots: [slot(.left, alive, days: 2), slot(.left, gone, days: 1)])
    let result = Projection.project(
        edge: .left, state: s, input: EdgeInput(snapshot: F.knowledgeBase, starCapacity: 5),
        usage: F.index([]), now: F.now, exists: { $0.raw == alive })
    #expect(result.pinnedSlots.map(\.isBroken) == [false, true])
}

@Test func r4_3_pinnedSlotsFollowTheEdgeAndKeepInsertionOrder() {
    let s = state(
        roots: [.left: F.kbRoot, .top: F.downloads],
        pinnedSlots: [
            slot(.left, "\(F.launcher)/AGENTS.md", days: 1), slot(.top, "\(F.downloads)/报价单.xlsx", days: 5),
            slot(.left, "\(F.launcher)/b.md", days: 9),
        ])
    let left = Projection.project(
        edge: .left, state: s, input: EdgeInput(snapshot: F.knowledgeBase, starCapacity: 5),
        usage: F.index([]), now: F.now, exists: { _ in true })
    #expect(left.pinnedSlots.map(\.name) == ["b.md", "AGENTS.md"])
}

@Test func r4_3_pinnedSlotsCoexistWithFloatingSlots() {
    let s = state(
        roots: [.top: F.downloads], pinnedSlots: [slot(.top, "\(F.downloads)/报价单.xlsx", days: 1)])
    let result = projectTop(s, current: papers)
    #expect(result.pinnedSlots.count == 1)
    #expect(result.floating.items.count == 5)
}

@Test func r4_3_pinnedSlotsAreCappedAtFivePerEdge() {
    let slots = (0..<7).map { slot(.top, "\(F.downloads)/f\($0).pdf", days: Double(10 - $0)) }
    let result = projectTop(state(roots: [.top: F.downloads], pinnedSlots: slots), current: nil)
    #expect(result.pinnedSlots.count == 5)
}

// MARK: Empty and unavailable quadrants

@Test func emptyQuadrantGivesExplicitEmptyResult() {
    let result = Projection.project(
        edge: .bottom, state: PersistentState(), input: EdgeInput(snapshot: nil, starCapacity: 20),
        usage: F.index([]), now: F.now, exists: { _ in true })
    #expect(result.isEmpty)
    #expect(result.root == nil)
    #expect(result.branches.items.isEmpty)
    #expect(result.stars == .empty)
    #expect(result.floating == .empty)
    #expect(result.pinnedSlots.isEmpty)
}

@Test func r6_3_rootWithoutSnapshotIsUnavailableNotEmpty() {
    let s = state(roots: [.bottom: "/Users/demo/Desktop"])
    let result = Projection.project(
        edge: .bottom, state: s, input: EdgeInput(snapshot: nil, starCapacity: 20),
        usage: F.index([]), now: F.now, exists: { _ in false })
    #expect(result.status == .rootUnavailable)
    #expect(result.root == NodePath("/Users/demo/Desktop"))
    #expect(!result.isEmpty)
}

@Test func projectAllCoversEveryEdge() {
    let result = Projection.project(
        state: leftState, inputs: [.left: EdgeInput(snapshot: F.knowledgeBase, starCapacity: 5)],
        usage: F.index([]), now: F.now, exists: { _ in false })
    #expect(Set(result.keys) == Set(Edge.allCases))
    #expect(result[.left]?.status == .ready)
}
