import Foundation

/// What AppModel needs from the panel window.
@MainActor
protocol PanelWindowControlling: AnyObject {
    /// Full screen, key window (also the end of a drag).
    func restoreFull()
    /// R7.2: shrink to the stash rectangle.
    func enterHalfHidden()
    func hide()
    /// R7.7: drop to normal level so Finder opens above the panel; the panel stays visible.
    func stepBehind()
    /// Back to the panel level, in front.
    func bringToFront()
}
