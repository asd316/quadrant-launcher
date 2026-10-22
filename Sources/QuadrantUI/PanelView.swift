import QuadrantCore
import SwiftUI

/// Root view of the panel. Placeholder until the UI layer is written.
public struct PanelView: View {
    let model: PanelRenderModel
    let send: @MainActor (UIEvent) -> Void

    public init(model: PanelRenderModel, send: @escaping @MainActor (UIEvent) -> Void) {
        self.model = model
        self.send = send
    }

    public var body: some View {
        Text("Quadrant Launcher")
    }
}
