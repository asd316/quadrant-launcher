import Foundation
import Testing

@testable import QuadrantCore

private typealias F = Fixture

@Test func r1_1_everyActionIsWorthOne() {
    let events = UsageAction.allCases.map { F.event("/a/f", $0) }
    #expect(abs(F.index(events).score(of: NodePath("/a/f")) - Double(UsageAction.allCases.count)) < 1e-9)
}

@Test func r1_3_halfLifeHalvesScore() {
    let index = F.index([F.event("/a/f", daysAgo: 30)])
    #expect(abs(index.score(of: NodePath("/a/f")) - 0.5) < 1e-9)
}

@Test func r1_3_olderEventsCountLess() {
    let index = F.index([F.event("/a/new", daysAgo: 1), F.event("/a/old", daysAgo: 90)])
    #expect(index.score(of: NodePath("/a/new")) > 0.97)
    #expect(abs(index.score(of: NodePath("/a/old")) - 0.125) < 1e-9)
}

@Test func r1_2_usageRollsUpToEveryAncestor() {
    // Glossary clicked 4 times lights up quadrant-file-launcher and 0-projects.
    let glossary = "\(F.launcher)/00-project-context/Glossary（术语表）.md"
    let events = (0..<4).map { _ in F.event(glossary, .copyPath) }
    let index = F.index(events)
    for ancestor in [glossary, "\(F.launcher)/00-project-context", F.launcher, F.workbench, F.kbRoot] {
        #expect(abs(index.score(of: NodePath(ancestor)) - 4) < 1e-9)
    }
    #expect(index.score(of: NodePath("\(F.workbench)/Photo Archive")) == 0)
}

@Test func r1_2_rollUpSumsOwnAndDescendantEvents() {
    let index = F.index([
        F.event("/a/b"), F.event("/a/b/c"), F.event("/a/b/c/d.md", .open), F.event("/a/x/y.md", .open),
    ])
    #expect(abs(index.score(of: NodePath("/a/b")) - 3) < 1e-9)
    #expect(abs(index.score(of: NodePath("/a/b/c")) - 2) < 1e-9)
    #expect(abs(index.score(of: NodePath("/a")) - 4) < 1e-9)
}

@Test func r1_2_rollUpIsPathPrefixNotStringPrefix() {
    let index = F.index([F.event("/a/bc/file.md", .open)])
    #expect(index.score(of: NodePath("/a/b")) == 0)
}

@Test func r1_2_recencyHalvesEverySevenDays() {
    #expect(abs(DisplayWeight.recency(modifiedAt: F.now, now: F.now) - 1) < 1e-9)
    #expect(abs(DisplayWeight.recency(modifiedAt: F.ago(days: 7), now: F.now) - 0.5) < 1e-9)
    #expect(abs(DisplayWeight.recency(modifiedAt: F.ago(days: 14), now: F.now) - 0.25) < 1e-9)
}

@Test func r1_2_weightIsUsagePlusRecency() {
    let node = F.folder("/a/b", modified: F.ago(days: 7))
    let index = F.index([F.event("/a/b/c.md", .open), F.event("/a/b", daysAgo: 30)])
    #expect(abs(DisplayWeight.weight(of: node, usage: index, now: F.now) - (1.5 + 0.5)) < 1e-9)
}

@Test func r1_2_recencyIsNotRolledUp() {
    // The parent is old; its child file was edited today. The parent gains nothing.
    let child = F.file("/a/b/new.md", modified: F.now)
    let parent = F.folder("/a/b", modified: F.old, [child])
    let weight = DisplayWeight.weight(of: parent, usage: F.index([]), now: F.now)
    #expect(weight < 1e-6)
    #expect(DisplayWeight.weight(of: child, usage: F.index([]), now: F.now) > 0.99)
}

@Test func r1_4_rankSortsByWeightDescending() {
    let nodes = ["a", "b", "c"].map { F.folder("/r/\($0)") }
    let index = F.index([F.event("/r/c"), F.event("/r/c"), F.event("/r/b")])
    let ranked = DisplayWeight.rank(nodes, usage: index, now: F.now)
    #expect(ranked.map(\.node.name) == ["c", "b", "a"])
}

@Test func r1_5_coldStartUsesRecencyOnly() {
    let recent = F.folder("/r/recent", modified: F.ago(days: 1))
    let stale = F.folder("/r/stale", modified: F.ago(days: 60))
    let ranked = DisplayWeight.rank([stale, recent], usage: F.index([]), now: F.now)
    #expect(ranked.map(\.node.name) == ["recent", "stale"])
}

@Test func r1_5_tiesSortByFinderOrder() {
    let names = ["第10周", "第2周", "第1周", "第6周"]
    let nodes = names.map { F.folder("/Downloads/课程/\($0)") }
    let ranked = DisplayWeight.rank(nodes, usage: F.index([]), now: F.now)
    #expect(ranked.map(\.node.name) == ["第1周", "第2周", "第6周", "第10周"])
}

@Test func r1_5_equalWeightGivesEqualBrightness() {
    let weights = [0.8, 0.8]
    let bright = weights.map { DisplayWeight.brightness(weight: $0, maxWeight: 0.8) }
    #expect(bright == [1, 1])
}

@Test func r1_4_brightnessFormula() {
    #expect(DisplayWeight.brightness(weight: 4, maxWeight: 4) == 1)
    #expect(abs(DisplayWeight.brightness(weight: 2, maxWeight: 4) - 0.625) < 1e-9)
    #expect(abs(DisplayWeight.brightness(weight: 0, maxWeight: 4) - 0.25) < 1e-9)
}

@Test func r1_4_allZeroGroupGetsMinimumBrightness() {
    #expect(DisplayWeight.brightness(weight: 0, maxWeight: 0) == 0.25)
}
