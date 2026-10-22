import CoreGraphics
import Testing

@testable import QuadrantApp

@Suite struct PanelFrameTests {
    @Test func belowMenuBarFullWidthDownToScreenBottomIgnoringDock() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        // Menu bar 24pt on top, Dock 70pt at the bottom.
        let visible = CGRect(x: 0, y: 70, width: 1440, height: 806)
        #expect(PanelFrame.frame(screenFrame: screen, visibleFrame: visible) == CGRect(x: 0, y: 0, width: 1440, height: 876))
        #expect(PanelFrame.topInset(screenFrame: screen, visibleFrame: visible) == 24)
    }

    @Test func secondaryScreenOffsetIsKept() {
        let screen = CGRect(x: 1440, y: -100, width: 1920, height: 1080)
        let visible = CGRect(x: 1440, y: -100, width: 1920, height: 1055)
        #expect(PanelFrame.frame(screenFrame: screen, visibleFrame: visible) == CGRect(x: 1440, y: -100, width: 1920, height: 1055))
    }

    @Test func zoneRectConvertsToScreenCoordinates() {
        let panel = CGRect(x: 0, y: 0, width: 1440, height: 876)
        let r = PanelFrame.screenRect(CGRect(x: 100, y: 50, width: 200, height: 80), panelFrame: panel)
        #expect(r == CGRect(x: 100, y: 746, width: 200, height: 80))
    }
}
