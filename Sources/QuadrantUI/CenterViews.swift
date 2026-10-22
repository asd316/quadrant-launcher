import QuadrantCore
import enum QuadrantCore.Edge
import SwiftUI

// MARK: Stash

struct StashItemSlot: View {
    let slot: StashSlot
    let selected: Bool
    let theme: Theme
    let context: UIContext
    @State private var hovered = false

    var body: some View {
        let path = slot.path
        ZStack {
            RoundedRectangle(cornerRadius: 9).fill(theme.stashSlotFill)
            if hovered || selected {
                RoundedRectangle(cornerRadius: 9).fill(theme.hover)
            }
            HStack(spacing: 4) {
                Text(path.name)
                    .font(Theme.smallFont)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .strikethrough(slot.isBroken)
                if slot.isBroken { Text("失效").font(Theme.smallFont) }
            }
            .foregroundStyle(slot.isBroken ? theme.broken : theme.stashText)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            if hovered {
                Button {
                    context.send(.stashRemove(path))
                } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .semibold))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(theme.actionFill))
                        .overlay(Circle().strokeBorder(theme.actionBorder, lineWidth: 1))
                        .foregroundStyle(theme.stashText)
                }
                .buttonStyle(.plain)
                .help("移出暂存区")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(3)
            }
        }
        .frame(width: 118, height: 40)
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? theme.accent.opacity(0.7) : .clear, lineWidth: 1))
        .nodeInteraction(
            InteractionNode(
                path: path, kind: slot.kind, context: context,
                onClick: { context.send(.select(path)) },
                onDoubleClick: { context.send(.doubleClick(path, slot.kind)) },
                onHover: { hovered = $0 },
                menu: nodeMenu(
                    path: path, context: context,
                    specific: [NodeMenuItem(title: "移出暂存区", action: { context.send(.stashRemove(path)) })])),
            trailingInset: hovered ? 22 : 0)
        .help(path.name)
    }
}

struct StashView: View {
    @Environment(\.isStaticRender) private var isStatic
    let slots: [StashSlot]
    let selection: NodePath?
    let copyProgress: Double?
    let theme: Theme
    let context: UIContext

    var body: some View {
        let shown = Array(slots.prefix(Capacity.stashItems))
        HStack(spacing: 10) {
            ForEach(0..<Capacity.stashItems, id: \.self) { index in
                if index < shown.count {
                    StashItemSlot(slot: shown[index], selected: selection == shown[index].path, theme: theme, context: context)
                } else {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(theme.stashDash, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(width: 118, height: 40)
                }
            }
        }
        .frame(width: PanelGeometry.stashSize.width, height: PanelGeometry.stashSize.height)
        .background(Glass(fill: theme.stashFill, radius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.stashBorder, lineWidth: 1))
        .overlay(alignment: .bottom) {
            if let progress = copyProgress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.divider)
                        Capsule().fill(theme.accent).frame(width: geo.size.width * min(1, max(0, progress)))
                    }
                }
                .frame(height: 2)
                .padding(.horizontal, 18)
                .padding(.bottom, 5)
            }
        }
        .shadow(color: theme.stashShadow, radius: 6, x: 0, y: 2)
        .background { if !isStatic { StashDropTarget(coordinator: context.coordinator) } }
    }
}

// MARK: Lens

struct LensRowView: View {
    let row: LensRow
    let pinEdge: Edge
    let showsContext: Bool
    let selected: Bool
    let theme: Theme
    let context: UIContext
    @State private var hovered = false

    var body: some View {
        let path = row.path
        let active = hovered || selected
        HStack(spacing: 8) {
            Image(systemName: row.kind == .folder ? "folder.fill" : "doc")
                .font(.system(size: 14))
                .foregroundStyle(row.kind == .folder ? theme.folderIcon : theme.lensText)
                .frame(width: 14)
            Text(path.name)
                .font(Theme.rowFont)
                .foregroundStyle(theme.lensText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if active {
                HStack(spacing: 8) {
                    actionButton("doc.on.doc", help: "复制路径") { context.send(.copyPath(path)) }
                    actionButton(
                        "bookmark", help: row.kind == .folder ? "置顶" : "放进固定位"
                    ) {
                        context.send(row.kind == .folder ? .pinFolder(pinEdge, path) : .pinSlot(pinEdge, path))
                    }
                }
            } else if showsContext, let parent = path.parent {
                Text(parent.name).font(Theme.smallFont).foregroundStyle(theme.lensCount).lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 6).fill(active ? theme.hover : .clear))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? theme.accent.opacity(0.7) : .clear, lineWidth: 1))
        .nodeInteraction(
            InteractionNode(
                path: path, kind: row.kind, context: context,
                onClick: { context.send(.select(path)) },
                onDoubleClick: { context.send(.doubleClick(path, row.kind)) },
                onHover: { hovered = $0 },
                menu: nodeMenu(path: path, context: context, specific: pinMenu)),
            trailingInset: active ? 72 : 0)
        .onHover { hovered = $0 }
    }

    private var pinMenu: [NodeMenuItem] {
        if row.kind == .folder {
            return [
                NodeMenuItem(title: "置顶", action: { context.send(.pinFolder(pinEdge, row.path)) }),
                NodeMenuItem(title: "取消置顶", action: { context.send(.unpinFolder(row.path)) }),
            ]
        }
        return [NodeMenuItem(title: "放进固定位", action: { context.send(.pinSlot(pinEdge, row.path)) })]
    }

    private func actionButton(_ symbol: String, help: String, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(theme.lensText)
                .frame(width: 26, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(theme.actionFill))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.actionBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct LensView: View {
    @Environment(\.isStaticRender) private var isStatic
    let lens: LensModel
    let selection: NodePath?
    let theme: Theme
    let context: UIContext

    static let width: CGFloat = 520
    static let maxHeight: CGFloat = 322
    static let headerHeight: CGFloat = 40

    private var pinEdge: Edge {
        if case .folder(let edge, _) = lens.mode { return edge }
        return .top
    }

    private var isFilter: Bool {
        if case .filter = lens.mode { return true }
        return false
    }

    private var listHeight: CGFloat {
        let content = CGFloat(lens.rows.count) * 30 + 16 + (lens.isLoading ? 28 : 0)
        let empty: CGFloat = lens.rows.isEmpty && !lens.isLoading ? 44 : 0
        return min(Self.maxHeight - Self.headerHeight - 1, max(content, empty))
    }

    var body: some View {
        VStack(spacing: 0) {
            header.frame(height: Self.headerHeight)
            Rectangle().fill(theme.divider).frame(height: 1)
            list.frame(height: listHeight)
        }
        .frame(width: Self.width)
        .background(Glass(fill: theme.lensFill, radius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.lensBorder, lineWidth: 1))
        .shadow(color: theme.lensShadow, radius: theme.lensShadowRadius, x: 0, y: theme.lensShadowY)
    }

    private var header: some View {
        HStack(spacing: 8) {
            switch lens.mode {
            case .folder(_, let crumbs):
                Button {
                    context.send(.lensBack(to: nil))
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .medium))
                        .frame(width: 20, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("返回上一层")
                crumbView(crumbs)
            case .filter(let query):
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).frame(width: 20)
                Text(query).font(Theme.rowFont).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(lens.rows.count) 项").font(Theme.smallFont).foregroundStyle(theme.lensCount)
        }
        .foregroundStyle(theme.lensText)
        .padding(.horizontal, 14)
    }

    private func crumbView(_ crumbs: [NodePath]) -> some View {
        let hidden = max(0, crumbs.count - 3)
        let shown = Array(crumbs.suffix(3))
        return HStack(spacing: 6) {
            if hidden > 0 {
                Text("…").font(Theme.rowFont)
                Text("›").font(Theme.smallFont).foregroundStyle(theme.lensCount)
            }
            ForEach(Array(shown.enumerated()), id: \.element) { index, crumb in
                if index > 0 { Text("›").font(Theme.smallFont).foregroundStyle(theme.lensCount) }
                Button {
                    if crumb != crumbs.last { context.send(.lensBack(to: crumb)) }
                } label: {
                    Text(crumb.name).font(Theme.rowFont).lineLimit(1).truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help(crumb.raw)
            }
        }
    }

    /// Lazy for real use; plain in static renders, where lazy content is not drawn.
    @ViewBuilder private func rowStack<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if isStatic {
            VStack(spacing: 2) { content() }
        } else {
            LazyVStack(spacing: 2) { content() }
        }
    }

    private var rowsContent: some View {
        rowStack {
            ForEach(lens.rows) { row in
                LensRowView(
                    row: row, pinEdge: row.edge ?? pinEdge, showsContext: isFilter,
                    selected: selection == row.path, theme: theme, context: context)
            }
            if lens.isLoading {
                Text("正在读取…").font(Theme.smallFont).foregroundStyle(theme.lensCount).frame(height: 26)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var list: some View {
        if lens.rows.isEmpty && !lens.isLoading {
            Text(isFilter ? "没有匹配" : "这里没有内容")
                .font(Theme.smallFont).foregroundStyle(theme.lensCount)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            if isStatic {
                rowsContent.frame(height: listHeight, alignment: .top).clipped()
            } else {
                ScrollView { rowsContent }.scrollIndicators(.hidden)
            }
        }
    }
}
