import CoreGraphics
import QuadrantCore

/// Pure layout of star label slots inside one edge's wedge. No SwiftUI.
///
/// The wedge of an edge is the triangle between the screen center and that screen side, bounded by the two
/// diagonals. Labels are horizontal boxes, so the same row scan works for all four edges.
enum StarfieldLayout {
    /// Dot (4.5) + gap (8) + room for the label text.
    static let labelSize = CGSize(width: 112, height: 18)
    static let rowPitch: CGFloat = 24
    static let columnGap: CGFloat = 8
    /// Distance kept from the diagonals and from the screen side.
    static let diagonalInset: CGFloat = 10
    static let screenInset: CGFloat = 8

    struct Slot: Equatable {
        var frame: CGRect
        /// Distance from the screen center to the slot's center.
        var distance: CGFloat
    }

    /// Whether `point` lies inside the edge's wedge, at least `inset` away from both diagonals.
    static func isInside(_ point: CGPoint, edge: Edge, size: CGSize, inset: CGFloat) -> Bool {
        let dx = point.x - size.width / 2
        let dy = point.y - size.height / 2
        let halfW = size.width / 2
        let halfH = size.height / 2
        let norm = (halfW * halfW + halfH * halfH).squareRoot()
        switch edge {
        case .top: return dy < 0 && (-dy * halfW - abs(dx) * halfH) / norm >= inset
        case .bottom: return dy > 0 && (dy * halfW - abs(dx) * halfH) / norm >= inset
        case .left: return dx < 0 && (-dx * halfH - abs(dy) * halfW) / norm >= inset
        case .right: return dx > 0 && (dx * halfH - abs(dy) * halfW) / norm >= inset
        }
    }

    /// Non-overlapping label slots, nearest to `origin` (default: the screen center) first. `exclusions` already include their margins.
    static func slots(edge: Edge, size: CGSize, exclusions: [CGRect], origin: CGPoint? = nil) -> [Slot] {
        let box = labelSize
        let starts = columnStarts(edge: edge, size: size, box: box)
        var result: [Slot] = []
        var y = screenInset + 3
        while y + box.height <= size.height - screenInset {
            for x in starts {
                let rect = CGRect(x: x, y: y, width: box.width, height: box.height)
                if isValid(rect, edge: edge, size: size, exclusions: exclusions) {
                    result.append(Slot(
                        frame: rect,
                        distance: distance(rect, from: origin ?? CGPoint(x: size.width / 2, y: size.height / 2))))
                }
            }
            y += rowPitch
        }
        return result.sorted {
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            if $0.frame.minY != $1.frame.minY { return $0.frame.minY < $1.frame.minY }
            return $0.frame.minX < $1.frame.minX
        }
    }


    /// Column grid per edge: left anchored to the left edge, right mirrored, top/bottom centered.
    private static func columnStarts(edge: Edge, size: CGSize, box: CGSize) -> [CGFloat] {
        let pitch = box.width + columnGap
        switch edge {
        case .left:
            var xs: [CGFloat] = []
            var x = screenInset
            while x + box.width <= size.width - screenInset {
                xs.append(x)
                x += pitch
            }
            return xs
        case .right:
            var xs: [CGFloat] = []
            var x = size.width - screenInset - box.width
            while x >= screenInset {
                xs.append(x)
                x -= pitch
            }
            return xs
        case .top, .bottom:
            let available = size.width - 2 * screenInset
            let count = max(1, Int((available + columnGap) / pitch))
            let total = CGFloat(count) * box.width + CGFloat(count - 1) * columnGap
            let start = (size.width - total) / 2
            return (0..<count).map { start + CGFloat($0) * pitch }
        }
    }

    static func isValid(_ rect: CGRect, edge: Edge, size: CGSize, exclusions: [CGRect]) -> Bool {
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
        ]
        guard corners.allSatisfy({ isInside($0, edge: edge, size: size, inset: diagonalInset) }) else { return false }
        return !exclusions.contains { $0.intersects(rect) }
    }

    private static func distance(_ rect: CGRect, from origin: CGPoint) -> CGFloat {
        let dx = rect.midX - origin.x
        let dy = rect.midY - origin.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// A free box of `box` size inside the wedge, nearest to `near`. Falls back to centering on `near`.
    static func freeRect(edge: Edge, size: CGSize, box: CGSize, exclusions: [CGRect], near: CGPoint) -> CGRect {
        var best: CGRect?
        var bestDistance = CGFloat.infinity
        var y = screenInset
        while y + box.height <= size.height - screenInset {
            var x = screenInset
            while x + box.width <= size.width - screenInset {
                let rect = CGRect(x: x, y: y, width: box.width, height: box.height)
                let d = hypot(rect.midX - near.x, rect.midY - near.y)
                if d < bestDistance, isValid(rect, edge: edge, size: size, exclusions: exclusions) {
                    best = rect
                    bestDistance = d
                }
                x += 6
            }
            y += 6
        }
        return best ?? CGRect(x: near.x - box.width / 2, y: near.y - box.height / 2, width: box.width, height: box.height)
    }
}
