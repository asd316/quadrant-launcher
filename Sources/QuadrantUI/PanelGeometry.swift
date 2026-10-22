import CoreGraphics
import QuadrantCore

/// Where things sit, relative to the screen center and edges (1440×900 is the Figma reference).
/// Sizes of text-driven items are estimates; they only feed star-slot exclusions.
struct PanelGeometry {
    let size: CGSize
    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }

    static let stashSize = CGSize(width: 400, height: 68)
    static let titleTextMax: CGFloat = 170
    static let branchTextMax: CGFloat = 128
    static let shelfEdgeGap: CGFloat = 12
    static let verticalShelfWidth: CGFloat = 144
    static let branchStarMargin: CGFloat = 34
    static let exclusionMargin: CGFloat = 10
    static let sideBand: CGFloat = 112
    static let capBand: CGFloat = 76

    // Branch groups: top row bottom edge sits 62 above the stash top; bottom row 6 below it.
    /// Figma distance from the screen center to the inner edge of the top/bottom row.
    static let baseRowDepth: CGFloat = 96
    /// Figma distance from the screen center to the inner edge of the left/right column.
    static let baseColumnGap: CGFloat = 229
    static let branchRowHeight: CGFloat = 32
    static let branchGap: CGFloat = 8
    /// Distance branch groups keep from the diagonals.
    static let branchDiagonalInset: CGFloat = 10

    private var halfW: CGFloat { size.width / 2 }
    private var halfH: CGFloat { size.height / 2 }
    private var norm: CGFloat { (halfW * halfW + halfH * halfH).squareRoot() }

    /// Distance from center to the inner edge of a top/bottom row of `width`, so the whole row sits in its wedge.
    func rowDepth(width: CGFloat) -> CGFloat {
        max(Self.baseRowDepth, (width / 2 * halfH + Self.branchDiagonalInset * norm) / halfW)
    }

    /// Distance from center to the inner edge of a left/right column of `height`, so every pill sits in its wedge.
    func columnGap(height: CGFloat) -> CGFloat {
        max(Self.baseColumnGap, (height / 2 * halfW + Self.branchDiagonalInset * norm) / halfH)
    }

    var stashRect: CGRect {
        CGRect(
            x: center.x - Self.stashSize.width / 2, y: center.y - Self.stashSize.height / 2,
            width: Self.stashSize.width, height: Self.stashSize.height)
    }

    /// Title origin rule per edge: top and left anchor their leading side, right and bottom their trailing side.
    func titleRect(edge: Edge, width: CGFloat) -> CGRect {
        let height: CGFloat = 26
        switch edge {
        case .top: return CGRect(x: center.x - 540, y: 20, width: width, height: height)
        case .left: return CGRect(x: 22, y: center.y + 250, width: width, height: height)
        case .right: return CGRect(x: size.width - 35 - width, y: center.y - 270, width: width, height: height)
        case .bottom: return CGRect(x: size.width - 185 - width, y: size.height - 48, width: width, height: height)
        }
    }

    func shelfRect(edge: Edge, slotCount: Int) -> CGRect {
        guard slotCount > 0 else { return .zero }
        switch edge {
        case .top, .bottom:
            let width = min(620, CGFloat(slotCount) * 112 + 12)
            let y = edge == .top ? Self.shelfEdgeGap : size.height - Self.shelfEdgeGap - 40
            return CGRect(x: center.x - width / 2, y: y, width: width, height: 40)
        case .left, .right:
            let height = CGFloat(slotCount) * 30 + 10
            let x = edge == .left ? Self.shelfEdgeGap : size.width - Self.shelfEdgeGap - Self.verticalShelfWidth
            return CGRect(x: x, y: center.y - height / 2, width: Self.verticalShelfWidth, height: height)
        }
    }

    /// Frame of the branch group (pills plus "+n"), placed inside its own wedge.
    func branchRect(edge: Edge, widths: [CGFloat], hasMore: Bool) -> CGRect {
        guard !widths.isEmpty else { return .zero }
        let gap = Self.branchGap
        switch edge {
        case .top, .bottom:
            var total = widths.reduce(0, +) + gap * CGFloat(widths.count - 1)
            if hasMore { total += gap + 30 }
            let depth = rowDepth(width: total)
            let y = edge == .top ? center.y - depth - Self.branchRowHeight : center.y + depth
            return CGRect(x: center.x - total / 2, y: y, width: total, height: Self.branchRowHeight)
        case .left, .right:
            var height = CGFloat(widths.count) * Self.branchRowHeight + gap * CGFloat(widths.count - 1)
            if hasMore { height += gap + 26 }
            let width = widths.max() ?? 0
            let offset = columnGap(height: height)
            let x = edge == .left ? center.x - offset - width : center.x + offset
            return CGRect(x: x, y: center.y - height / 2, width: width, height: height)
        }
    }

    func branchRect(edge: Edge, projection: EdgeProjection) -> CGRect {
        let hasBadge = projection.stars.truncatedCount > 0
        let widths = projection.branches.items.map { Self.pillWidth(name: $0.name, hasBadge: $0.isFocused && hasBadge) }
        return branchRect(edge: edge, widths: widths, hasMore: projection.branches.truncatedCount > 0)
    }

    static func pillWidth(name: String, hasBadge: Bool) -> CGFloat {
        min(estimatedTextWidth(name, size: 14), branchTextMax) + 20 + (hasBadge ? 38 : 0)
    }

    static func titleWidth(_ projection: EdgeProjection?) -> CGFloat {
        guard let projection else { return 150 }
        switch projection.status {
        case .empty: return 130
        case .rootUnavailable, .ready:
            let name = projection.root?.name ?? ""
            return 24 + min(estimatedTextWidth(name, size: 18), titleTextMax)
                + (projection.branches.hiddenCount > 0 ? 70 : 0) + (projection.status == .rootUnavailable ? 40 : 0)
        }
    }

    /// Where the starfield hint text goes: inside the wedge, clear of everything, nearest to the usual spot.
    func hintRect(edge: Edge, quadrants: [Edge: EdgeProjection], textWidth: CGFloat) -> CGRect {
        let exclusions = starExclusions(edge: edge, quadrants: quadrants)
        let box = CGSize(width: textWidth, height: 18)
        let normal: CGPoint
        switch edge {
        case .top: normal = CGPoint(x: 0, y: -1)
        case .bottom: normal = CGPoint(x: 0, y: 1)
        case .left: normal = CGPoint(x: -1, y: 0)
        case .right: normal = CGPoint(x: 1, y: 0)
        }
        let preferred = CGPoint(x: center.x + normal.x * 0.46 * halfW, y: center.y + normal.y * 0.46 * halfH)
        return StarfieldLayout.freeRect(
            edge: edge, size: size, box: box, exclusions: exclusions, near: preferred)
    }

    /// All rectangles stars of `edge` must keep away from, margins included.
    func starExclusions(edge: Edge, quadrants: [Edge: EdgeProjection]) -> [CGRect] {
        var rects = [stashRect.insetBy(dx: -Self.branchStarMargin, dy: -Self.branchStarMargin)]
        // Outer bands stay clear: shelves and titles live there, and Figma keeps stars off the screen sides.
        rects.append(CGRect(x: 0, y: 0, width: Self.sideBand, height: size.height))
        rects.append(CGRect(x: size.width - Self.sideBand, y: 0, width: Self.sideBand, height: size.height))
        rects.append(CGRect(x: 0, y: 0, width: size.width, height: Self.capBand))
        rects.append(CGRect(x: 0, y: size.height - Self.capBand, width: size.width, height: Self.capBand))
        for other in Edge.allCases {
            rects.append(
                titleRect(edge: other, width: Self.titleWidth(quadrants[other]))
                    .insetBy(dx: -Self.exclusionMargin, dy: -Self.exclusionMargin))
        }
        guard let projection = quadrants[edge] else { return rects }
        let branches = branchRect(edge: edge, projection: projection)
        if !branches.isEmpty {
            rects.append(branches.insetBy(dx: -Self.branchStarMargin, dy: -Self.branchStarMargin))
        }
        let count =
            projection.pinnedSlots.count + projection.floating.items.count
            + (projection.floating.truncatedCount > 0 ? 1 : 0)
        let shelf = shelfRect(edge: edge, slotCount: count)
        if !shelf.isEmpty { rects.append(shelf.insetBy(dx: -Self.exclusionMargin, dy: -Self.exclusionMargin)) }
        return rects
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
            result[edge] = StarfieldLayout.slots(edge: edge, size: size, exclusions: exclusions).count
        }
        return result
    }
}
