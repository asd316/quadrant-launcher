import QuadrantCore
import enum QuadrantCore.Edge
import SwiftUI

/// One drop zone drawn in its own small window while the main panel is half-hidden (R7.2).
/// The window size is the zone's rect from `PanelLayout.dropZoneRects`. The view draws the zone's normal
/// look, highlights it while a drag hovers, and records a drop of the panel's own drag (fileURL).
public struct DropZoneView: View {
    let zone: DropZone
    let model: PanelRenderModel
    let send: @MainActor (UIEvent) -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var isTargeted = false

    public init(zone: DropZone, model: PanelRenderModel, send: @escaping @MainActor (UIEvent) -> Void) {
        self.zone = zone
        self.model = model
        self.send = send
    }

    public var body: some View {
        let theme = Theme(scheme)
        let context = UIContext(send: send, coordinator: .shared)
        content(theme: theme, context: context)
            .overlay(highlight(theme: theme))
            .background(ZoneDropTarget(zone: zone, isTargeted: $isTargeted))
            .animation(.easeOut(duration: 0.12), value: isTargeted)
    }

    @ViewBuilder
    private func content(theme: Theme, context: UIContext) -> some View {
        switch zone {
        case .stash:
            StashView(
                interactive: false, slots: model.stash, selection: nil, copyProgress: nil, theme: theme,
                context: context)
        case .pinnedShelf(let edge):
            Group {
                if let projection = model.quadrants[edge] {
                    PinnedSection(
                        edge: edge, projection: projection, selection: nil, theme: theme, context: context,
                        interactive: false)
                }
            }
            .padding(.leading, 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.shelfBackground))
        }
    }

    private func highlight(theme: Theme) -> some View {
        let radius: CGFloat = zone == .stash ? 16 : 8
        return RoundedRectangle(cornerRadius: radius)
            .fill(theme.accent.opacity(isTargeted ? 0.16 : 0))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(theme.accent.opacity(isTargeted ? 0.9 : 0), lineWidth: 2))
            .allowsHitTesting(false)
    }
}
