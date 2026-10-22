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
    /// Row stagger, so labels in neighboring rows do not line up in columns.
    static let stagger: [CGFloat] = [0, 36, 14, 50, 24]

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

    /// Non-overlapping label slots, nearest to the screen center first. `exclusions` already include their margins.
    static func slots(edge: Edge, size: CGSize, exclusions: [CGRect]) -> [Slot] {
        let box = labelSize
        var result: [Slot] = []
        var row = 0
        var y = screenInset + 3
        while y + box.height <= size.height - screenInset {
            var x = screenInset + stagger[row % stagger.count]
            while x + box.width <= size.width - screenInset {
                let rect = CGRect(x: x, y: y, width: box.width, height: box.height)
                if isValid(rect, edge: edge, size: size, exclusions: exclusions) {
                    result.append(Slot(frame: rect, distance: distanceFromCenter(rect, size: size)))
                    x += box.width + columnGap
                } else {
                    x += 4
                }
            }
            y += rowPitch
            row += 1
        }
        return result.sorted {
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            if $0.frame.minY != $1.frame.minY { return $0.frame.minY < $1.frame.minY }
            return $0.frame.minX < $1.frame.minX
        }
    }

    private static func isValid(_ rect: CGRect, edge: Edge, size: CGSize, exclusions: [CGRect]) -> Bool {
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
        ]
        guard corners.allSatisfy({ isInside($0, edge: edge, size: size, inset: diagonalInset) }) else { return false }
        return !exclusions.contains { $0.intersects(rect) }
    }

    private static func distanceFromCenter(_ rect: CGRect, size: CGSize) -> CGFloat {
        let dx = rect.midX - size.width / 2
        let dy = rect.midY - size.height / 2
        return (dx * dx + dy * dy).squareRoot()
    }
}
