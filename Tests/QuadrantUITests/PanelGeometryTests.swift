import CoreGraphics
import Foundation
import QuadrantCore
import Testing

@testable import QuadrantCore
@testable import QuadrantUI

private let screens = [CGSize(width: 1440, height: 900), CGSize(width: 1920, height: 1080), CGSize(width: 1920, height: 1050)]

/// Every pill at max width, focused pill with badge, "+n" present, long title, full shelf.
private func worstCase() -> [Edge: EdgeProjection] {
    var result: [Edge: EdgeProjection] = [:]
    for edge in Edge.allCases {
        let capacity = Capacity.branches(on: edge)
        let long = String(repeating: "W", count: 60)
        let items = (0..<capacity).map { index in
            BranchItem(
                path: NodePath("/r/\(edge.rawValue)/\(long)\(index)"), name: long + "\(index)", weight: 1,
                isPinned: false, isFocused: index == 0)
        }
        let root = NodePath("/r/\(long)\(edge.rawValue)")
        result[edge] = EdgeProjection(
            edge: edge, root: root, status: .ready,
            branches: BranchesResult(items: items, truncatedCount: 9, hiddenCount: 3),
            stars: StarsResult(branch: items[0].path, items: [], truncatedCount: 5),
            floating: FloatingResult(items: [], truncatedCount: 0),
            pinnedSlots: [])
    }
    return result
}

private struct Element {
    var edge: Edge
    var name: String
    var rect: CGRect
    var mustBeInWedge: Bool
}

private func elements(size: CGSize) -> [Element] {
    let g = PanelGeometry(size: size)
    let quadrants = worstCase()
    var all: [Element] = []
    for edge in Edge.allCases {
        guard let projection = quadrants[edge] else { continue }
        all.append(Element(edge: edge, name: "branches", rect: g.branchRect(edge: edge, projection: projection), mustBeInWedge: true))
        all.append(Element(edge: edge, name: "root", rect: g.rootRect(edge: edge), mustBeInWedge: true))
        all.append(Element(edge: edge, name: "shelf", rect: g.shelfRect(edge: edge), mustBeInWedge: true))
        for text in ["点击一个分支目录，显示它的星点", "没有子文件夹"] {
            let rect = g.hintRect(edge: edge, quadrants: quadrants, textWidth: estimatedTextWidth(text, size: 12))
            all.append(Element(edge: edge, name: "hint", rect: rect, mustBeInWedge: true))
        }
    }
    all.append(Element(edge: .top, name: "stash", rect: g.stashRect, mustBeInWedge: false))
    return all
}

@Test(arguments: screens)
func noElementsOverlapAnotherEdgesElements(size: CGSize) {
    let all = elements(size: size)
    for i in all.indices {
        for j in all.indices where j > i {
            let a = all[i], b = all[j]
            // The two hint variants never show together.
            if a.name == "hint" && b.name == "hint" && a.edge == b.edge { continue }
            #expect(!a.rect.intersects(b.rect), "\(a.edge) \(a.name) overlaps \(b.edge) \(b.name) at \(size)")
        }
    }
}

@Test(arguments: screens)
func elementsStayInsideTheirWedgeAndOnScreen(size: CGSize) {
    for element in elements(size: size) where element.mustBeInWedge {
        let f = element.rect
        let corners = [
            CGPoint(x: f.minX, y: f.minY), CGPoint(x: f.maxX, y: f.minY),
            CGPoint(x: f.minX, y: f.maxY), CGPoint(x: f.maxX, y: f.maxY),
        ]
        for corner in corners {
            #expect(
                StarfieldLayout.isInside(corner, edge: element.edge, size: size, inset: 0),
                "\(element.edge) \(element.name) crosses a diagonal at \(size)")
        }
        #expect(f.minX >= 0 && f.minY >= 0 && f.maxX <= size.width && f.maxY <= size.height, "\(element.edge) \(element.name) off screen at \(size)")
    }
}

@Test func pillLabelWidthIsCapped() {
    #expect(PanelGeometry.pillWidth(name: String(repeating: "W", count: 80), hasBadge: false) <= 128 + 20)
}

@Test func rootEntriesSurroundTheStash() {
    let g = PanelGeometry(size: screens[2])
    #expect(g.rootRect(edge: .top).maxY < g.stashRect.minY)
    #expect(g.rootRect(edge: .bottom).minY > g.stashRect.maxY)
    #expect(g.rootRect(edge: .left).maxX < g.stashRect.minX)
    #expect(g.rootRect(edge: .right).minX > g.stashRect.maxX)
}

private func projection(_ edge: Edge, names: [String], more: Int = 0, focusedBadge: Bool = false) -> EdgeProjection {
    let items = names.enumerated().map { index, name in
        BranchItem(path: NodePath("/r/\(name)"), name: name, weight: 1, isPinned: false, isFocused: index == 0)
    }
    return EdgeProjection(
        edge: edge, root: NodePath("/r"), status: .ready,
        branches: BranchesResult(items: items, truncatedCount: more, hiddenCount: 0),
        stars: StarsResult(branch: items.first?.path, items: [], truncatedCount: focusedBadge ? 3 : 0),
        floating: FloatingResult(items: [], truncatedCount: 0), pinnedSlots: [])
}

@Test(arguments: screens)
func branchAnchorsDoNotDependOnLabelWidths(size: CGSize) {
    let g = PanelGeometry(size: size)
    for edge in Edge.allCases {
        let n = Capacity.branches(on: edge)
        let short = g.branchRect(edge: edge, projection: projection(edge, names: (0..<n).map { _ in "a" }))
        let long = g.branchRect(edge: edge, projection: projection(edge, names: (0..<n).map { _ in String(repeating: "W", count: 50) }, more: 5, focusedBadge: true))
        switch edge {
        case .top, .bottom:
            #expect(abs(short.midX - long.midX) < 0.001)
            #expect(short.minY == long.minY)
        case .left:
            #expect(abs(short.maxX - long.maxX) < 0.001)
            #expect(abs(short.minY + short.height / 2 - (long.minY + long.height / 2)) < 0.001)
        case .right:
            #expect(abs(short.minX - long.minX) < 0.001)
            #expect(abs(short.minY + short.height / 2 - (long.minY + long.height / 2)) < 0.001)
        }
    }
}

@Test(arguments: screens)
func starsStayOnTheOuterSideOfTheBranchGroup(size: CGSize) {
    let g = PanelGeometry(size: size)
    let quadrants = worstCase()
    for edge in Edge.allCases {
        let slots = StarfieldLayout.slots(
            edge: edge, size: size, exclusions: g.starExclusions(edge: edge, quadrants: quadrants),
            origin: g.starOrigin(edge: edge))
        #expect(!slots.isEmpty)
        let group = g.branchRect(edge: edge, projection: quadrants[edge]!)
        let origin = g.starOrigin(edge: edge)
        for slot in slots {
            let f = slot.frame
            switch edge {
            case .top: #expect(f.maxY <= origin.y && f.maxY < group.minY)
            case .bottom: #expect(f.minY >= origin.y && f.minY > group.maxY)
            case .left: #expect(f.maxX <= origin.x && f.maxX < group.minX)
            case .right: #expect(f.minX >= origin.x && f.minX > group.maxX)
            }
        }
        // Nearest slots first, measured from the branch group's outer edge.
        #expect(zip(slots, slots.dropFirst()).allSatisfy { $0.distance <= $1.distance })
    }
}

@Test(arguments: screens)
func dropZonesCoverStashAndPinnedSections(size: CGSize) {
    var model = PanelRenderModel(quadrants: worstCase())
    model.quadrants[.bottom] = EdgeProjection(
        edge: .bottom, root: nil, status: .empty,
        branches: BranchesResult(items: [], truncatedCount: 0, hiddenCount: 0), stars: .empty,
        floating: .empty, pinnedSlots: [])
    let zones = PanelLayout.dropZoneRects(size: size, model: model)
    #expect(zones[.stash] == PanelGeometry(size: size).stashRect)
    #expect(zones[.pinnedShelf(.bottom)] == nil)
    for edge in [Edge.top, .left, .right] {
        let rect = try! #require(zones[.pinnedShelf(edge)])
        let shelf = PanelGeometry(size: size).shelfRect(edge: edge)
        #expect(shelf.contains(rect))
        #expect(!rect.intersects(PanelGeometry(size: size).stashRect))
    }
}
