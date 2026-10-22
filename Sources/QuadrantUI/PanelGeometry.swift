import CoreGraphics
import QuadrantCore

/// Where things sit. Every position depends on the screen size only, never on label widths:
/// long names are truncated instead (Design-Principles › Implementation notes, 位置固定).
/// 1440×900 is the Figma reference.
struct PanelGeometry {
    let size: CGSize
    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }

    static let stashSize = CGSize(width: 400, height: 68)
    static let titleTextMax: CGFloat = 170
    /// Text width cap of a branch pill (truncated with an ellipsis, tooltip shows the full name).
    static let branchTextMax: CGFloat = 96
    static let pillPadding: CGFloat = 20
    static let badgeWidth: CGFloat = 42
    static let branchRowHeight: CGFloat = 32
    static let branchGap: CGFloat = 8
    static let moreWidth: CGFloat = 30
    static let moreHeight: CGFloat = 26
    /// Distance branch groups keep from the diagonals.
    static let branchDiagonalInset: CGFloat = 10
    static let starMargin: CGFloat = 24
    static let exclusionMargin: CGFloat = 10
    static let stashMargin: CGFloat = 34

    // Shelf (one per edge, two sections: 固定 above 浮动).
    static let shelfEdgeGap: CGFloat = 12
    static let shelfPadding: CGFloat = 6
    static let slotHeight: CGFloat = 28
    static let horizontalShelfWidth: CGFloat = 548
    static let verticalShelfWidth: CGFloat = 144
    /// Section heights for left/right shelves: label plus six slots (5 + placeholder or "+n").
    static let verticalSectionHeight: CGFloat = 196
    static let verticalSectionGap: CGFloat = 8
    static let horizontalSectionGap: CGFloat = 6

    var halfW: CGFloat { size.width / 2 }
    var halfH: CGFloat { size.height / 2 }
    var norm: CGFloat { (halfW * halfW + halfH * halfH).squareRoot() }

    var stashRect: CGRect {
        CGRect(
            x: center.x - Self.stashSize.width / 2, y: center.y - Self.stashSize.height / 2,
            width: Self.stashSize.width, height: Self.stashSize.height)
    }

    // MARK: Branch groups

    static var maxPillWidth: CGFloat { branchTextMax + pillPadding + badgeWidth }

    /// Widest a top/bottom row can get: capacity pills (one focused with badge) plus "+n".
    static func worstRowWidth(edge: Edge) -> CGFloat {
        let n = CGFloat(Capacity.branches(on: edge))
        let pill = branchTextMax + pillPadding
        return (n - 1) * pill + maxPillWidth + (n - 1) * branchGap + branchGap + moreWidth
    }

    /// Tallest a left/right column can get: capacity pills plus "+n".
    static func worstColumnHeight(edge: Edge) -> CGFloat {
        let n = CGFloat(Capacity.branches(on: edge))
        return n * branchRowHeight + (n - 1) * branchGap + branchGap + moreHeight
    }

    /// Distance from center to the inner edge of top/bottom rows. Fixed per screen size: the worst-case row fits.
    var rowDepth: CGFloat {
        let width = Self.worstRowWidth(edge: .top)
        return (width / 2 * halfH + Self.branchDiagonalInset * norm) / halfW
    }

    /// Distance from center to the inner edge of left/right columns, so the worst-case column fits its wedge.
    var columnGap: CGFloat {
        let height = Self.worstColumnHeight(edge: .left)
        return max(Self.stashSize.width / 2 + 24, (height / 2 * halfW + Self.branchDiagonalInset * norm) / halfH)
    }

    /// Frame of the branch group (pills plus "+n"). Anchor positions are fixed; only the extent follows the content.
    func branchRect(edge: Edge, widths: [CGFloat], hasMore: Bool) -> CGRect {
        guard !widths.isEmpty else { return .zero }
        let gap = Self.branchGap
        switch edge {
        case .top, .bottom:
            var total = widths.reduce(0, +) + gap * CGFloat(widths.count - 1)
            if hasMore { total += gap + Self.moreWidth }
            let y = edge == .top ? center.y - rowDepth - Self.branchRowHeight : center.y + rowDepth
            return CGRect(x: center.x - total / 2, y: y, width: total, height: Self.branchRowHeight)
        case .left, .right:
            var height = CGFloat(widths.count) * Self.branchRowHeight + gap * CGFloat(widths.count - 1)
            if hasMore { height += gap + Self.moreHeight }
            let width = widths.max() ?? 0
            let x = edge == .left ? center.x - columnGap - width : center.x + columnGap
            return CGRect(x: x, y: center.y - height / 2, width: width, height: height)
        }
    }

    func branchRect(edge: Edge, projection: EdgeProjection) -> CGRect {
        let hasBadge = projection.stars.truncatedCount > 0
        let widths = projection.branches.items.map { Self.pillWidth(name: $0.name, hasBadge: $0.isFocused && hasBadge) }
        return branchRect(edge: edge, widths: widths, hasMore: projection.branches.truncatedCount > 0)
    }

    static func pillWidth(name: String, hasBadge: Bool) -> CGFloat {
        min(estimatedTextWidth(name, size: 14), branchTextMax) + pillPadding + (hasBadge ? badgeWidth : 0)
    }

    // MARK: Stars

    /// Point stars cluster around: the outer edge of the branch group's fixed band.
    func starOrigin(edge: Edge) -> CGPoint {
        switch edge {
        case .top: return CGPoint(x: center.x, y: center.y - rowDepth - Self.branchRowHeight - Self.starMargin)
        case .bottom: return CGPoint(x: center.x, y: center.y + rowDepth + Self.branchRowHeight + Self.starMargin)
        case .left: return CGPoint(x: center.x - columnGap - Self.maxPillWidth - Self.starMargin, y: center.y)
        case .right: return CGPoint(x: center.x + columnGap + Self.maxPillWidth + Self.starMargin, y: center.y)
        }
    }

    /// The half of the screen stars of `edge` must not enter (the branch group's side and the center).
    private func innerHalfPlane(edge: Edge) -> CGRect {
        let o = starOrigin(edge: edge)
        switch edge {
        case .top: return CGRect(x: 0, y: o.y, width: size.width, height: size.height - o.y)
        case .bottom: return CGRect(x: 0, y: 0, width: size.width, height: o.y)
        case .left: return CGRect(x: o.x, y: 0, width: size.width - o.x, height: size.height)
        case .right: return CGRect(x: 0, y: 0, width: o.x, height: size.height)
        }
    }

    /// All rectangles stars of `edge` must keep away from, margins included.
    func starExclusions(edge: Edge, quadrants: [Edge: EdgeProjection]) -> [CGRect] {
        var rects = [innerHalfPlane(edge: edge), stashRect.insetBy(dx: -Self.stashMargin, dy: -Self.stashMargin)]
        for other in Edge.allCases {
            rects.append(
                titleRect(edge: other, width: Self.titleWidth(quadrants[other]))
                    .insetBy(dx: -Self.exclusionMargin, dy: -Self.exclusionMargin))
            if let projection = quadrants[other], projection.status != .empty {
                rects.append(shelfRect(edge: other).insetBy(dx: -Self.exclusionMargin, dy: -Self.exclusionMargin))
            }
        }
        return rects
    }

    /// Where the starfield hint text goes: on the outer side of the branch group, clear of everything.
    func hintRect(edge: Edge, quadrants: [Edge: EdgeProjection], textWidth: CGFloat) -> CGRect {
        let exclusions = starExclusions(edge: edge, quadrants: quadrants)
        let box = CGSize(width: textWidth, height: 18)
        let o = starOrigin(edge: edge)
        let preferred: CGPoint
        switch edge {
        case .top: preferred = CGPoint(x: o.x, y: o.y - 40)
        case .bottom: preferred = CGPoint(x: o.x, y: o.y + 40)
        case .left: preferred = CGPoint(x: o.x - 20 - textWidth / 2, y: o.y)
        case .right: preferred = CGPoint(x: o.x + 20 + textWidth / 2, y: o.y)
        }
        return StarfieldLayout.freeRect(edge: edge, size: size, box: box, exclusions: exclusions, near: preferred)
    }

    // MARK: Titles

    /// Fixed anchor per edge. The 「全部显示」 link sits under the name, so the width is name + icon (+ 「失效」).
    func titleRect(edge: Edge, width: CGFloat) -> CGRect {
        let height: CGFloat = 42
        switch edge {
        case .top: return CGRect(x: center.x - 560, y: 20, width: width, height: height)
        case .left: return CGRect(x: 22, y: center.y + 250, width: width, height: height)
        case .right: return CGRect(x: size.width - 35 - width, y: center.y - 270, width: width, height: height)
        case .bottom: return CGRect(x: size.width - 150 - width, y: size.height - 60, width: width, height: height)
        }
    }

    static func titleWidth(_ projection: EdgeProjection?) -> CGFloat {
        guard let projection else { return 150 }
        switch projection.status {
        case .empty: return 130
        case .rootUnavailable, .ready:
            let name = projection.root?.name ?? ""
            return 24 + min(estimatedTextWidth(name, size: 18), titleTextMax)
                + (projection.status == .rootUnavailable ? 40 : 0)
        }
    }

    // MARK: Shelf

    /// Fixed frame of an edge's shelf container.
    func shelfRect(edge: Edge) -> CGRect {
        let pad = Self.shelfPadding
        switch edge {
        case .top, .bottom:
            let height = pad * 2 + Self.slotHeight * 2 + Self.horizontalSectionGap
            let y = edge == .top ? Self.shelfEdgeGap : size.height - Self.shelfEdgeGap - height
            return CGRect(x: center.x - Self.horizontalShelfWidth / 2, y: y, width: Self.horizontalShelfWidth, height: height)
        case .left, .right:
            let height = pad * 2 + Self.verticalSectionHeight * 2 + Self.verticalSectionGap
            let x = edge == .left ? Self.shelfEdgeGap : size.width - Self.shelfEdgeGap - Self.verticalShelfWidth
            return CGRect(x: x, y: center.y - height / 2, width: Self.verticalShelfWidth, height: height)
        }
    }

    /// The 「固定」 section: the drop zone for files (R7.4).
    func pinnedSectionRect(edge: Edge) -> CGRect {
        let shelf = shelfRect(edge: edge)
        let pad = Self.shelfPadding
        switch edge {
        case .top, .bottom:
            return CGRect(x: shelf.minX + pad, y: shelf.minY + pad, width: shelf.width - 2 * pad, height: Self.slotHeight)
        case .left, .right:
            return CGRect(x: shelf.minX + pad, y: shelf.minY + pad, width: shelf.width - 2 * pad, height: Self.verticalSectionHeight)
        }
    }
}

/// Layout questions the App or a preview can ask without drawing anything.
public enum PanelLayout {
    /// How many stars fit in each edge's wedge for this model on a screen of `size`.
    public static func starCapacities(for model: PanelRenderModel, size: CGSize) -> [Edge: Int] {
        let geometry = PanelGeometry(size: size)
        var result: [Edge: Int] = [:]
        for edge in Edge.allCases {
            let exclusions = geometry.starExclusions(edge: edge, quadrants: model.quadrants)
            result[edge] = StarfieldLayout.slots(
                edge: edge, size: size, exclusions: exclusions, origin: geometry.starOrigin(edge: edge)
            ).count
        }
        return result
    }

    /// Where each drop zone sits in panel coordinates (top-left origin): the stash, and the 「固定」 section of
    /// every edge that has a root folder. Used by the App to place the small drop-zone windows (R7.2).
    public static func dropZoneRects(size: CGSize, model: PanelRenderModel) -> [DropZone: CGRect] {
        let geometry = PanelGeometry(size: size)
        var result: [DropZone: CGRect] = [.stash: geometry.stashRect]
        for edge in Edge.allCases {
            if let projection = model.quadrants[edge], projection.status != .empty {
                result[.pinnedShelf(edge)] = geometry.pinnedSectionRect(edge: edge)
            }
        }
        return result
    }
}
