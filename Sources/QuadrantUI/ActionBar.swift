import AppKit
import SwiftUI

/// Compact floating row of icon buttons shown at the right-click point. Labels are tooltips only.
struct ActionBarView: View {
    let origin: CGPoint
    let actions: [NodeAction]
    let panelSize: CGSize
    let theme: Theme
    let dismiss: @MainActor () -> Void

    static let buttonSize: CGFloat = 30
    static let padding: CGFloat = 4

    private var barSize: CGSize {
        CGSize(
            width: CGFloat(actions.count) * Self.buttonSize + 2 * Self.padding,
            height: Self.buttonSize + 2 * Self.padding)
    }

    private var position: CGPoint {
        let size = barSize
        return CGPoint(
            x: min(max(8, origin.x + 6), max(8, panelSize.width - size.width - 8)),
            y: min(max(8, origin.y + 6), max(8, panelSize.height - size.height - 8)))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
            HStack(spacing: 0) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    ActionBarButton(action: action, theme: theme, dismiss: dismiss)
                }
            }
            .padding(Self.padding)
            .background(Glass(fill: theme.lensFill, radius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.lensBorder, lineWidth: 1))
            .shadow(color: theme.lensShadow, radius: theme.lensShadowRadius, x: 0, y: theme.lensShadowY)
            .offset(x: position.x, y: position.y)
        }
        .frame(width: panelSize.width, height: panelSize.height, alignment: .topLeading)
        .transition(.opacity)
    }
}

private struct ActionBarButton: View {
    let action: NodeAction
    let theme: Theme
    let dismiss: @MainActor () -> Void
    @State private var hovered = false

    var body: some View {
        Button {
            action.action()
            dismiss()
        } label: {
            icon
                .frame(width: ActionBarView.buttonSize, height: ActionBarView.buttonSize)
                .background(RoundedRectangle(cornerRadius: 7).fill(hovered ? theme.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(action.title)
    }

    @ViewBuilder private var icon: some View {
        switch action.icon {
        case .symbol(let name):
            Image(systemName: name).font(.system(size: 13)).foregroundStyle(theme.lensText)
        case .finder:
            Image(nsImage: Self.finderIcon).resizable().frame(width: 18, height: 18)
        }
    }

    private static let finderIcon = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
}

/// Highlight over a zone while a drag from another app hovers it (R7.7).
struct ZoneHighlight: View {
    let active: Bool
    let radius: CGFloat
    let theme: Theme

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(theme.accent.opacity(active ? 0.16 : 0))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(theme.accent.opacity(active ? 0.9 : 0), lineWidth: 2))
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.12), value: active)
    }
}

/// Accepts files dragged in from other apps for one zone of the main panel (R7.7).
struct ExternalDropZone: View {
    @Environment(\.isStaticRender) private var isStatic
    let zone: DropZone
    let rect: CGRect
    let radius: CGFloat
    let targeted: Bool
    let theme: Theme
    let context: UIContext
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            if !isStatic {
                ZoneDropTarget(
                    zone: zone, isTargeted: $isTargeted,
                    onExternalDrop: { paths in context.send(.externalDrop(paths, on: zone)) })
            }
            ZoneHighlight(active: targeted || isTargeted, radius: radius, theme: theme)
        }
        .frame(width: rect.width, height: rect.height)
        .onChange(of: isTargeted) { _, value in context.externalHover(value ? zone : nil) }
    }
}
