import Foundation

/// What AppModel needs from the panel window.
@MainActor
protocol PanelWindowControlling: AnyObject {
    /// Full screen, key window (also the end of a drag).
    func restoreFull()
    /// R7.2: shrink to the stash rectangle.
    func enterHalfHidden()
    func hide()
}
