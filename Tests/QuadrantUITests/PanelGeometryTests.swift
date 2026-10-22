import CoreGraphics
import Foundation
import QuadrantCore
import Testing

@testable import QuadrantCore
@testable import QuadrantUI

private let screens = [CGSize(width: 1440, height: 900), CGSize(width: 1920, height: 1080)]

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
        let root = NodePath("/r/\(edge.rawValue)")
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
        all.append(Element(edge: edge, name: "title", rect: g.titleRect(edge: edge, width: PanelGeometry.titleWidth(projection)), mustBeInWedge: true))
        all.append(Element(edge: edge, name: "shelf", rect: g.shelfRect(edge: edge, slotCount: 11), mustBeInWedge: true))
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
