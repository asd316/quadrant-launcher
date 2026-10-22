import CoreGraphics

/// Panel placement. The panel sits below the menu bar so the menu bar and status item stay usable.
enum PanelFrame {
    /// Full width, from the screen bottom up to the menu bar's lower edge. The Dock is not subtracted.
    static func frame(screenFrame: CGRect, visibleFrame: CGRect) -> CGRect {
        let top = min(visibleFrame.maxY, screenFrame.maxY)
        return CGRect(x: screenFrame.minX, y: screenFrame.minY, width: screenFrame.width, height: max(0, top - screenFrame.minY))
    }

    /// Height of the menu bar strip.
    static func topInset(screenFrame: CGRect, visibleFrame: CGRect) -> CGFloat {
        max(0, screenFrame.maxY - visibleFrame.maxY)
    }

    /// Top-left-origin rect in panel coordinates → screen coordinates (bottom-left origin).
    static func screenRect(_ rect: CGRect, panelFrame: CGRect) -> CGRect {
        CGRect(x: panelFrame.minX + rect.minX, y: panelFrame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}
