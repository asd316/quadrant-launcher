import QuadrantCore
import enum QuadrantCore.Edge
import SwiftUI

/// Root view of the panel. Draws a `PanelRenderModel` and reports `UIEvent`s; no rules live here.
public struct PanelView: View {
    let model: PanelRenderModel
    let send: @MainActor (UIEvent) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.isStaticRender) private var isStatic
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var actionBar: ActionBarModel?
    @State private var externalTarget: DropZone?

    struct ActionBarModel {
        var origin: CGPoint
        var actions: [NodeAction]
    }

    public init(model: PanelRenderModel, send: @escaping @MainActor (UIEvent) -> Void) {
        self.model = model
        self.send = send
    }

    public var body: some View {
        GeometryReader { geo in
            content(size: geo.size)
        }
    }

    private func content(size: CGSize) -> some View {
        let theme = Theme(scheme)
        let geometry = PanelGeometry(size: size)
        let context = UIContext(
            send: send, coordinator: .shared,
            presentActions: { origin, actions in actionBar = ActionBarModel(origin: origin, actions: actions) },
            dismissActions: { if actionBar != nil { actionBar = nil } },
            externalHover: { externalTarget = $0 })
        let hidden = model.isHalfHidden
        let lensOpen = model.lens != nil
        let capacities = PanelLayout.starCapacities(for: model, size: size)
        let fade: Animation? = reduceMotion ? nil : .easeOut(duration: 0.12)

        // Half-hidden (R7.2): draw nothing, but keep every view alive so the drag source survives the drag.
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                background(theme: theme, size: size)
                externalZones(geometry: geometry, theme: theme, context: context)
                ZStack(alignment: .topLeading) {
                    ForEach(Edge.allCases, id: \.self) { edge in
                        quadrant(edge, size: size, geometry: geometry, theme: theme, context: context)
                    }
                }
                .opacity(lensOpen ? 0.65 : 1)
                .animation(fade, value: lensOpen)

                centerLayer(size: size, theme: theme, context: context)

                if let bar = actionBar {
                    ActionBarView(
                        origin: bar.origin, actions: bar.actions, panelSize: size, theme: theme,
                        dismiss: { actionBar = nil })
                }
            }
            .opacity(hidden ? 0 : 1)
            .allowsHitTesting(!hidden)
            .animation(.easeOut(duration: 0.1), value: hidden)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .onChange(of: capacities, initial: true) {
            for edge in Edge.allCases { send(.starCapacityMeasured(edge, capacities[edge] ?? 0)) }
        }
    }

    // MARK: Background

    @ViewBuilder
    private func background(theme: Theme, size: CGSize) -> some View {
        ZStack {
            if isStatic {
                theme.panelSolid
            } else {
                VisualEffectBackground(material: .underWindowBackground, blending: .behindWindow)
                theme.panelBackground
            }
            Canvas { gc, canvasSize in
                let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let corners = [
                    CGPoint.zero, CGPoint(x: canvasSize.width, y: 0),
                    CGPoint(x: canvasSize.width, y: canvasSize.height), CGPoint(x: 0, y: canvasSize.height),
                ]
                for edge in [Edge.left, .right] {
                    gc.fill(wedge(edge, corners: corners, center: c), with: .color(theme.quadrantTint))
                }
                var lines = Path()
                lines.move(to: corners[0]); lines.addLine(to: corners[2])
                lines.move(to: corners[1]); lines.addLine(to: corners[3])
                gc.stroke(lines, with: .color(theme.diagonal), lineWidth: 1)
                if model.keyboardRegion != .center {
                    let edge = Edge(region: model.keyboardRegion)
                    if let edge {
                        gc.stroke(
                            wedge(edge, corners: corners, center: c).strokedPath(.init(lineWidth: 0)),
                            with: .color(.clear), lineWidth: 0)
                        gc.stroke(
                            wedge(edge, corners: corners, center: c), with: .color(theme.accent.opacity(0.22)),
                            lineWidth: 6)
                    }
                }
            }
            .clipShape(Rectangle())
        }
        .frame(width: size.width, height: size.height)
    }

    private func wedge(_ edge: Edge, corners: [CGPoint], center: CGPoint) -> Path {
        // corners: top-left, top-right, bottom-right, bottom-left
        let pair: (CGPoint, CGPoint)
        switch edge {
        case .top: pair = (corners[0], corners[1])
        case .right: pair = (corners[1], corners[2])
        case .bottom: pair = (corners[2], corners[3])
        case .left: pair = (corners[3], corners[0])
        }
        var path = Path()
        path.move(to: center); path.addLine(to: pair.0); path.addLine(to: pair.1); path.closeSubpath()
        return path
    }

    // MARK: Quadrants

    @ViewBuilder
    private func quadrant(_ edge: Edge, size: CGSize, geometry: PanelGeometry, theme: Theme, context: UIContext)
        -> some View
    {
        let projection = model.quadrants[edge]
        let root = geometry.rootRect(edge: edge)
        RootEntry(projection: projection, edge: edge, theme: theme, context: context)
            .anchored(.topLeading, in: size, dx: root.minX, dy: root.minY)

        if let projection, projection.status != .empty {
            let shelf = geometry.shelfRect(edge: edge)
            ShelfView(
                edge: edge, projection: projection,
                selection: model.keyboardSelection, theme: theme, context: context
            )
            .anchored(.topLeading, in: size, dx: shelf.minX, dy: shelf.minY)
        }

        if let projection, projection.status == .ready {

            let branchRect = geometry.branchRect(edge: edge, projection: projection)
            BranchGroup(edge: edge, projection: projection, selection: model.keyboardSelection, theme: theme, context: context)
                .branchPlacement(edge, size: size, rect: branchRect)

            starLayer(edge, projection: projection, size: size, geometry: geometry, theme: theme, context: context)
        }
    }

    @ViewBuilder
    private func starLayer(
        _ edge: Edge, projection: EdgeProjection, size: CGSize, geometry: PanelGeometry, theme: Theme,
        context: UIContext
    ) -> some View {
        let slots = StarfieldLayout.slots(
            edge: edge, size: size, exclusions: geometry.starExclusions(edge: edge, quadrants: model.quadrants),
            origin: geometry.starOrigin(edge: edge))
        if projection.stars.branch == nil || projection.stars.items.isEmpty {
            let text = projection.stars.branch == nil ? "点击一个分支目录，显示它的星点" : "没有子文件夹"
            let rect = geometry.hintRect(
                edge: edge, quadrants: model.quadrants, textWidth: estimatedTextWidth(text, size: 12))
            StarHint(text: text, theme: theme)
                .anchored(.center, in: size, dx: rect.midX - size.width / 2, dy: rect.midY - size.height / 2)
        } else {
            StarField(
                edge: edge, projection: projection, slots: slots, selection: model.keyboardSelection, theme: theme,
                context: context, size: size
            )
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: projection.stars.branch)
        }
    }

    // MARK: External drops (R7.7)

    /// The stash and each edge's 「固定」 section accept files dragged in from other apps.
    @ViewBuilder
    private func externalZones(geometry: PanelGeometry, theme: Theme, context: UIContext) -> some View {
        let rects = PanelLayout.dropZoneRects(size: geometry.size, model: model)
        ForEach(Array(rects.keys.sorted { String(describing: $0) < String(describing: $1) }), id: \.self) { zone in
            if let rect = rects[zone] {
                ExternalDropZone(
                    zone: zone, rect: rect, radius: zone == .stash ? 16 : 8, targeted: externalTarget == zone,
                    theme: theme, context: context)
                .anchored(.topLeading, in: geometry.size, dx: rect.minX, dy: rect.minY)
            }
        }
    }

    // MARK: Center

    @ViewBuilder
    private func centerLayer(size: CGSize, theme: Theme, context: UIContext) -> some View {
        ZStack {
            if model.keyboardRegion == .center, let selection = model.keyboardSelection, model.stash.contains(where: { $0.path == selection }) {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(theme.accent.opacity(0.3), lineWidth: 2)
                    .frame(width: PanelGeometry.stashSize.width + 12, height: PanelGeometry.stashSize.height + 12)
            }
            StashView(
                slots: model.stash, selection: model.keyboardSelection, copyProgress: model.copyProgress,
                theme: theme, context: context)

            if let message = model.message {
                Text(message)
                    .font(Theme.smallFont)
                    .foregroundStyle(theme.lensText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .offset(y: model.lens == nil ? 56 : -56)
            }
        }
        .frame(width: size.width, height: size.height)

        if let lens = model.lens {
            LensView(lens: lens, selection: model.keyboardSelection, theme: theme, context: context)
                .transition(
                    reduceMotion
                        ? .opacity : .opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                .frame(width: size.width, height: size.height, alignment: .top)
                .offset(y: size.height / 2 + PanelGeometry.stashSize.height / 2 + 16)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: lens.mode)
        }
    }
}

extension Edge {
    init?(region: KeyboardRegion) {
        switch region {
        case .top: self = .top
        case .bottom: self = .bottom
        case .left: self = .left
        case .right: self = .right
        case .center: return nil
        }
    }
}

extension View {
    /// Places the group on `rect`: rows centered on it, left column trailing-aligned, right column leading-aligned.
    func branchPlacement(_ edge: Edge, size: CGSize, rect: CGRect) -> some View {
        switch edge {
        case .top, .bottom:
            return AnyView(anchored(.center, in: size, dx: rect.midX - size.width / 2, dy: rect.midY - size.height / 2))
        case .left:
            return AnyView(anchored(.trailing, in: size, dx: rect.maxX - size.width))
        case .right:
            return AnyView(anchored(.leading, in: size, dx: rect.minX))
        }
    }
}
