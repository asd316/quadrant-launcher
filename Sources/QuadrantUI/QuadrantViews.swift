import QuadrantCore
import enum QuadrantCore.Edge
import SwiftUI

extension View {
    /// Keyboard selection: hover background plus a thin accent outline.
    func selectionStyle(_ selected: Bool, radius: CGFloat, theme: Theme) -> some View {
        background(RoundedRectangle(cornerRadius: radius).fill(selected ? theme.hover : .clear))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(selected ? theme.accent.opacity(0.7) : .clear, lineWidth: 1))
    }

    func anchored(_ alignment: Alignment, in size: CGSize, dx: CGFloat = 0, dy: CGFloat = 0) -> some View {
        frame(width: size.width, height: size.height, alignment: alignment).offset(x: dx, y: dy)
    }
}

private func moreHelp(_ count: Int) -> String { "还有 \(count) 个，在透镜里看" }

/// Small "+n" link used for every truncation (one component, Design-Principles).
struct MoreButton: View {
    let count: Int
    let theme: Theme
    var height: CGFloat = 26
    var color: Color
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Text("+\(count)")
                .font(Theme.smallFont)
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .frame(height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(moreHelp(count))
    }
}

// MARK: Title

struct QuadrantTitle: View {
    let projection: EdgeProjection?
    let edge: Edge
    let theme: Theme
    let context: UIContext

    var body: some View {
        switch projection?.status ?? .empty {
        case .empty:
            Text("未设置常驻文件夹").font(Theme.smallFont).foregroundStyle(theme.hint.opacity(0.7))
        case .rootUnavailable, .ready:
            let unavailable = projection?.status == .rootUnavailable
            HStack(spacing: 7) {
                Image(systemName: "folder").font(.system(size: 17))
                Text(projection?.root?.name ?? "")
                    .font(Theme.titleFont)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: PanelGeometry.titleTextMax, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                    .strikethrough(unavailable)
                if unavailable {
                    Text("失效").font(Theme.smallFont)
                }
                if let hidden = projection?.branches.hiddenCount, hidden > 0 {
                    Button("全部显示") { context.send(.showAllBranches(edge)) }
                        .buttonStyle(.plain)
                        .font(Theme.smallFont)
                        .foregroundStyle(theme.shelfText)
                        .underline()
                        .padding(.leading, 6)
                }
            }
            .foregroundStyle(unavailable ? theme.broken : theme.title)
            .help(projection?.root?.raw ?? "")
        }
    }
}

// MARK: Shelf

struct ShelfSlot: View {
    let name: String
    let path: NodePath
    let isBroken: Bool
    let isPinned: Bool
    let vertical: Bool
    let selected: Bool
    let edge: Edge
    let theme: Theme
    let context: UIContext
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc").font(.system(size: 12))
            Text(name)
                .font(Theme.smallFont)
                .lineLimit(1)
                .truncationMode(.tail)
                .strikethrough(isBroken)
                .frame(maxWidth: vertical ? .infinity : 84, alignment: .leading)
                .fixedSize(horizontal: !vertical, vertical: false)
            if isBroken { Text("失效").font(Theme.smallFont) }
        }
        .foregroundStyle(isBroken ? theme.broken : theme.shelfText)
        .padding(.horizontal, 8)
        .frame(maxWidth: vertical ? .infinity : nil, alignment: .leading)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7).fill(hovered ? theme.hover : .clear))
        .selectionStyle(selected, radius: 7, theme: theme)
        .nodeInteraction(
            InteractionNode(
                path: path, kind: .file, context: context,
                onClick: { context.send(.select(path)) },
                onDoubleClick: { context.send(.doubleClick(path, .file)) },
                onHover: { hovered = $0 },
                menu: nodeMenu(
                    path: path, context: context,
                    specific: [
                        isPinned
                            ? NodeMenuItem(title: "移出固定位", action: { context.send(.unpinSlot(edge, path)) })
                            : NodeMenuItem(title: "放进固定位", action: { context.send(.pinSlot(edge, path)) })
                    ])))
        .help(name)
    }
}

struct ShelfView: View {
    let edge: Edge
    let projection: EdgeProjection
    let focusedFolder: NodePath?
    let selection: NodePath?
    let theme: Theme
    let context: UIContext

    private var vertical: Bool { edge.isHorizontalSide }

    var body: some View {
        let pinned = projection.pinnedSlots
        let floating = projection.floating
        if !pinned.isEmpty || !floating.items.isEmpty {
            let content = Group {
                ForEach(pinned, id: \.path) { slot in
                    ShelfSlot(
                        name: slot.name, path: slot.path, isBroken: slot.isBroken, isPinned: true,
                        vertical: vertical, selected: selection == slot.path, edge: edge, theme: theme, context: context)
                }
                if !pinned.isEmpty && !floating.items.isEmpty { separator }
                ForEach(floating.items, id: \.path) { item in
                    ShelfSlot(
                        name: item.name, path: item.path, isBroken: false, isPinned: false,
                        vertical: vertical, selected: selection == item.path, edge: edge, theme: theme, context: context)
                }
                if floating.truncatedCount > 0 {
                    MoreButton(count: floating.truncatedCount, theme: theme, height: 28, color: theme.shelfText) {
                        context.send(.openLens(edge, folder: focusedFolder ?? projection.root ?? NodePath("/")))
                    }
                    .frame(maxWidth: vertical ? .infinity : nil, alignment: .leading)
                }
            }
            Group {
                if vertical {
                    VStack(alignment: .leading, spacing: 2) { content }.frame(width: PanelGeometry.verticalShelfWidth - 12)
                } else {
                    HStack(spacing: 2) { content }
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.shelfBackground))
        }
    }

    @ViewBuilder private var separator: some View {
        if vertical {
            Rectangle().fill(theme.divider).frame(height: 1).padding(.horizontal, 8)
        } else {
            Rectangle().fill(theme.divider).frame(width: 1, height: 14).padding(.horizontal, 4)
        }
    }
}

// MARK: Branches

struct BranchPill: View {
    let item: BranchItem
    let edge: Edge
    let starsTruncated: Int
    let selected: Bool
    let theme: Theme
    let context: UIContext
    @State private var hovered = false

    private var showsBadge: Bool { item.isFocused && starsTruncated > 0 }

    var body: some View {
        HStack(spacing: 6) {
            Text(item.name)
                .font(Theme.rowFont)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: PanelGeometry.branchTextMax)
                .fixedSize(horizontal: true, vertical: false)
            if showsBadge {
                Button {
                    context.send(.openLens(edge, folder: item.path))
                } label: {
                    Text("+\(starsTruncated)")
                        .font(Theme.smallFont)
                        .frame(width: 30, height: 24)
                        .background(RoundedRectangle(cornerRadius: 9).fill(theme.badgeFill))
                }
                .buttonStyle(.plain)
                .help(moreHelp(starsTruncated))
            }
        }
        .foregroundStyle(item.isFocused ? theme.focusText : theme.branchText)
        .padding(.leading, 10)
        .padding(.trailing, showsBadge ? 4 : 10)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(item.isFocused ? theme.focusFill : (hovered ? theme.hover : .clear))
        )
        .selectionStyle(selected, radius: 8, theme: theme)
        .nodeInteraction(
            InteractionNode(
                path: item.path, kind: .folder, context: context,
                onClick: { context.send(.clickBranch(edge, item.path)) },
                onDoubleClick: { context.send(.doubleClick(item.path, .folder)) },
                onHover: { hovered = $0 },
                menu: nodeMenu(
                    path: item.path, context: context,
                    specific: [
                        item.isPinned
                            ? NodeMenuItem(title: "取消置顶", action: { context.send(.unpinFolder(item.path)) })
                            : NodeMenuItem(title: "置顶", action: { context.send(.pinFolder(edge, item.path)) }),
                        NodeMenuItem(title: "隐藏", action: { context.send(.hideBranch(edge, item.path)) }),
                    ])),
            trailingInset: showsBadge ? 34 : 0)
        .help(item.name)
    }
}

struct BranchGroup: View {
    let edge: Edge
    let projection: EdgeProjection
    let selection: NodePath?
    let theme: Theme
    let context: UIContext

    var body: some View {
        let items = projection.branches.visualOrder
        let more = projection.branches.truncatedCount
        let pills = ForEach(items, id: \.path) { item in
            BranchPill(
                item: item, edge: edge, starsTruncated: projection.stars.truncatedCount,
                selected: selection == item.path, theme: theme, context: context)
        }
        let moreView = Group {
            if more > 0 {
                MoreButton(count: more, theme: theme, color: theme.branchText) {
                    context.send(.openLens(edge, folder: projection.root ?? NodePath("/")))
                }
            }
        }
        switch edge {
        case .top, .bottom:
            HStack(spacing: 8) { pills; moreView }
        case .left:
            VStack(alignment: .trailing, spacing: 8) { pills; moreView }
        case .right:
            VStack(alignment: .leading, spacing: 8) { pills; moreView }
        }
    }
}

// MARK: Stars

struct StarView: View {
    let item: StarItem
    let edge: Edge
    let selected: Bool
    let theme: Theme
    let context: UIContext
    @State private var hovered = false

    /// Dot opacity follows brightness (0.25...1); the label stays readable (0.7...1).
    private var labelOpacity: Double { 0.7 + 0.3 * (min(1, max(0.25, item.brightness)) - 0.25) / 0.75 }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(theme.starLabel).frame(width: 4.5, height: 4.5).opacity(item.brightness)
            Text(item.name)
                .font(Theme.smallFont)
                .foregroundStyle(theme.starLabel)
                .opacity(labelOpacity)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 92, alignment: .leading)
        }
        .frame(width: StarfieldLayout.labelSize.width - 6, height: StarfieldLayout.labelSize.height, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 5).fill(hovered ? theme.hover : .clear))
        .selectionStyle(selected, radius: 5, theme: theme)
        .nodeInteraction(
            InteractionNode(
                path: item.path, kind: .folder, context: context,
                onClick: { context.send(.clickStar(edge, item.path)) },
                onDoubleClick: { context.send(.doubleClick(item.path, .folder)) },
                onHover: { hovered = $0 },
                menu: nodeMenu(
                    path: item.path, context: context,
                    specific: [
                        item.isPinned
                            ? NodeMenuItem(title: "取消置顶", action: { context.send(.unpinFolder(item.path)) })
                            : NodeMenuItem(title: "置顶", action: { context.send(.pinFolder(edge, item.path)) })
                    ])))
        .help(item.name)
    }
}

struct StarField: View {
    let edge: Edge
    let projection: EdgeProjection
    let slots: [StarfieldLayout.Slot]
    let selection: NodePath?
    let theme: Theme
    let context: UIContext
    let size: CGSize

    var body: some View {
        let stars = projection.stars
        ZStack(alignment: .topLeading) {
            ForEach(Array(zip(stars.items, slots)), id: \.0.path) { pair in
                StarView(
                    item: pair.0, edge: edge, selected: selection == pair.0.path, theme: theme, context: context
                )
                .offset(x: pair.1.frame.minX, y: pair.1.frame.minY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .id(stars.branch)
        .transition(.opacity)
    }
}

/// Text in the starfield area when there is nothing to draw (no focused branch, or a branch without sub-folders).
struct StarHint: View {
    let text: String
    let theme: Theme

    var body: some View {
        Text(text).font(Theme.smallFont).foregroundStyle(theme.hint)
    }
}
