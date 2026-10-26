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

/// Small "+n" link used for every truncation (one component).
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

// MARK: Root folder entry

/// L1 root folder entry (R2.7): a clickable pill around the stash. Clicking opens the lens on the root,
/// so the user sees everything directly inside that one-level folder.
struct RootEntry: View {
    let projection: EdgeProjection?
    let edge: Edge
    let theme: Theme
    let context: UIContext
    @State private var hovered = false

    private var status: EdgeStatus { projection?.status ?? .empty }
    private var unavailable: Bool { status == .rootUnavailable }
    private var name: String { projection?.root?.name ?? "" }
    private var vertical: Bool { edge.isHorizontalSide }
    private var hiddenCount: Int { projection?.branches.hiddenCount ?? 0 }
    /// R2.8: the root is the source of the starfield when its contents are shown.
    private var isCurrent: Bool { projection?.currentFolder == projection?.root }

    var body: some View {
        ZStack(alignment: vertical ? .bottomTrailing : .topTrailing) {
            switch status {
            case .empty:
                emptyEntry
            case .rootUnavailable, .ready:
                Button(action: open) { entry }
                    .buttonStyle(.plain)
                    .disabled(unavailable)
                    .onHover { hovered = $0 }
                    .help(unavailable ? "常驻文件夹不存在" : (projection?.root?.raw ?? ""))
                    .contextMenu {
                        if !unavailable, let root = projection?.root {
                            Button("在透镜里查看全部") { context.send(.openLens(edge, folder: root)) }
                            Button("在 Finder 中显示") { context.send(.revealInFinder(root)) }
                        }
                    }
            }
            if hiddenCount > 0 {
                Button {
                    context.send(.showAllBranches(edge))
                } label: {
                    Image(systemName: "eye").font(.system(size: 10, weight: .medium))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.shelfText)
                .help("全部显示被隐藏的分支目录")
                .padding(2)
            }
        }
    }

    private func open() {
        guard !unavailable, let root = projection?.root else { return }
        context.send(.drillCloud(edge, root))
    }

    private var entry: some View {
        Group {
            if vertical {
                VStack(spacing: 5) {
                    Image(systemName: "folder").font(.system(size: 13))
                    rotatedName
                }
                .frame(width: PanelGeometry.rootVerticalSize.width, height: PanelGeometry.rootVerticalSize.height)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "folder").font(.system(size: 16))
                    Text(name)
                        .font(Theme.titleFont)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .strikethrough(unavailable)
                        .frame(maxWidth: PanelGeometry.titleTextMax, alignment: .leading)
                    if unavailable {
                        Text("失效").font(Theme.smallFont)
                    }
                }
                .padding(.horizontal, 10)
                .frame(
                    width: PanelGeometry.rootHorizontalSize.width, height: PanelGeometry.rootHorizontalSize.height,
                    alignment: .leading)
            }
        }
        .foregroundStyle(unavailable ? theme.broken : theme.title)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hovered || (isCurrent && !unavailable) ? theme.hover : theme.shelfBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isCurrent && !unavailable ? theme.branchText.opacity(0.55) : theme.divider, lineWidth: 1))
    }

    /// Side tabs are narrow, so the name turns 90° and keeps the full text readable in the 96px height.
    private var rotatedName: some View {
        Text(name)
            .font(Theme.rowFont)
            .lineLimit(1)
            .truncationMode(.tail)
            .strikethrough(unavailable)
            .frame(width: PanelGeometry.rootVerticalSize.height - 18, height: 18)
            .rotationEffect(.degrees(90))
            .frame(width: PanelGeometry.rootVerticalSize.width, height: PanelGeometry.rootVerticalSize.height - 18)
    }

    private var emptyEntry: some View {
        Text(vertical ? "未设置\n常驻\n文件夹" : "未设置常驻文件夹")
            .font(Theme.smallFont)
            .multilineTextAlignment(.center)
            .foregroundStyle(theme.hint.opacity(0.7))
            .frame(
                width: vertical ? PanelGeometry.rootVerticalSize.width : PanelGeometry.rootHorizontalSize.width,
                height: vertical ? PanelGeometry.rootVerticalSize.height : PanelGeometry.rootHorizontalSize.height)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(theme.stashDash, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
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
    var interactive = true
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc").font(.system(size: 12))
            Text(name)
                .font(Theme.smallFont)
                .lineLimit(1)
                .truncationMode(.tail)
                .strikethrough(isBroken)
                .frame(maxWidth: vertical ? .infinity : (isBroken ? 30 : 56), alignment: .leading)
                .fixedSize(horizontal: !vertical, vertical: false)
            if isBroken { Text("失效").font(Theme.smallFont) }
        }
        .foregroundStyle(isBroken ? theme.broken : theme.shelfText)
        .padding(.horizontal, 8)
        .frame(maxWidth: vertical ? .infinity : nil, alignment: .leading)
        .frame(height: PanelGeometry.slotHeight)
        .background(RoundedRectangle(cornerRadius: 7).fill(hovered ? theme.hover : .clear))
        .selectionStyle(selected, radius: 7, theme: theme)
        .modifier(
            OptionalInteraction(
                enabled: interactive,
                node: InteractionNode(
                    path: path, kind: .file, context: context,
                    onClick: { context.send(.select(path)) },
                    onDoubleClick: { context.send(.doubleClick(path, .file)) },
                    onHover: { hovered = $0 },
                    menu: nodeMenu(
                        path: path, context: context,
                        specific: [
                            isPinned
                                ? NodeAction(title: "移出固定位", icon: .symbol("pin.slash"), action: { context.send(.unpinSlot(edge, path)) })
                                : NodeAction(title: "放进固定位", icon: .symbol("pin"), action: { context.send(.pinSlot(edge, path)) })
                        ]),
                    dropZone: isPinned ? .pinnedShelf(edge) : nil)))
        .help(name)
    }
}

private struct OptionalInteraction: ViewModifier {
    let enabled: Bool
    let node: InteractionNode

    func body(content: Content) -> some View {
        if enabled { content.nodeInteraction(node) } else { content }
    }
}

/// Dashed empty slot with a very quiet hint.
struct EmptySlot: View {
    let text: String
    let vertical: Bool
    let theme: Theme

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(theme.shelfText.opacity(0.6))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(maxWidth: vertical ? .infinity : nil, alignment: .leading)
            .frame(height: PanelGeometry.slotHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(theme.stashDash, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

struct SectionLabel: View {
    let text: String
    let theme: Theme

    var body: some View {
        Text(text).font(.system(size: 11)).foregroundStyle(theme.shelfText.opacity(0.75))
    }
}

/// 「固定」: pinned files, plus one dashed slot while there is room (R4.3: up to five).
struct PinnedSection: View {
    let edge: Edge
    let projection: EdgeProjection
    let selection: NodePath?
    let theme: Theme
    let context: UIContext
    var interactive = true

    private var vertical: Bool { edge.isHorizontalSide }

    var body: some View {
        let pinned = projection.pinnedSlots
        let slots = Group {
            ForEach(pinned, id: \.path) { slot in
                ShelfSlot(
                    name: slot.name, path: slot.path, isBroken: slot.isBroken, isPinned: true,
                    vertical: vertical, selected: selection == slot.path, edge: edge, theme: theme,
                    context: context, interactive: interactive)
            }
            if pinned.count < Capacity.pinnedSlotsPerEdge {
                EmptySlot(text: "拖文件到这里", vertical: vertical, theme: theme)
            }
        }
        if vertical {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(text: "固定", theme: theme).frame(height: 16)
                slots
            }
        } else {
            HStack(spacing: 2) {
                SectionLabel(text: "固定", theme: theme).frame(width: 28, alignment: .leading)
                slots
            }
        }
    }
}

struct ShelfView: View {
    let edge: Edge
    let projection: EdgeProjection
    let selection: NodePath?
    let theme: Theme
    let context: UIContext

    private var vertical: Bool { edge.isHorizontalSide }

    var body: some View {
        let floating = projection.floating
        let pinnedSection = PinnedSection(
            edge: edge, projection: projection, selection: selection, theme: theme, context: context)
        let floatingSlots = Group {
            ForEach(floating.items, id: \.path) { item in
                ShelfSlot(
                    name: item.name, path: item.path, isBroken: false, isPinned: false,
                    vertical: vertical, selected: selection == item.path, edge: edge, theme: theme, context: context)
            }
            if floating.items.isEmpty {
                EmptySlot(text: "选中文件夹后自动出现", vertical: vertical, theme: theme)
            }
            if floating.truncatedCount > 0 {
                MoreButton(count: floating.truncatedCount, theme: theme, height: PanelGeometry.slotHeight, color: theme.shelfText) {
                    context.send(.openLens(edge, folder: projection.currentFolder ?? projection.root ?? NodePath("/")))
                }
            }
        }
        Group {
            if vertical {
                VStack(alignment: .leading, spacing: PanelGeometry.verticalSectionGap) {
                    pinnedSection.frame(height: PanelGeometry.verticalSectionHeight, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 2) {
                        SectionLabel(text: "浮动", theme: theme).frame(height: 16)
                        floatingSlots
                    }
                    .frame(height: PanelGeometry.verticalSectionHeight, alignment: .topLeading)
                }
                .frame(width: PanelGeometry.verticalShelfWidth - 2 * PanelGeometry.shelfPadding, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: PanelGeometry.horizontalSectionGap) {
                    pinnedSection.frame(height: PanelGeometry.slotHeight)
                    HStack(spacing: 2) {
                        SectionLabel(text: "浮动", theme: theme).frame(width: 28, alignment: .leading)
                        floatingSlots
                    }
                    .frame(height: PanelGeometry.slotHeight)
                }
                .frame(width: PanelGeometry.horizontalShelfWidth - 2 * PanelGeometry.shelfPadding, alignment: .leading)
            }
        }
        .padding(PanelGeometry.shelfPadding)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.shelfBackground))
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
                        NodeAction(
                            title: "在透镜里查看全部", icon: .symbol("list.bullet"),
                            action: { context.send(.openLens(edge, folder: item.path)) }),
                        item.isPinned
                            ? NodeAction(title: "取消置顶", icon: .symbol("pin.slash"), action: { context.send(.unpinFolder(item.path)) })
                            : NodeAction(title: "置顶", icon: .symbol("pin"), action: { context.send(.pinFolder(edge, item.path)) })
                    ],
                    after: [NodeAction(title: "隐藏", icon: .symbol("eye.slash"), action: { context.send(.hideBranch(edge, item.path)) })])),
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
        // Only the branch that is the cloud's source keeps the focus fill; deeper clouds have no focused branch.
        let cloud = projection.stars.branch
        let items = projection.branches.visualOrder.map { item in
            var shown = item
            if item.path != cloud { shown.isFocused = false }
            return shown
        }
        let more = projection.branches.truncatedCount
        // Truncation is shown by the starfield's own「+n」control (R2.8), not by the branch pill.
        let starsMore = 0
        let pills = ForEach(items, id: \.path) { item in
            BranchPill(
                item: item, edge: edge, starsTruncated: starsMore,
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
    private var isFolder: Bool { item.kind == .folder }

    var body: some View {
        HStack(spacing: 8) {
            if isFolder {
                Circle().fill(theme.starLabel).frame(width: 4.5, height: 4.5).opacity(item.brightness)
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.starLabel)
                    .opacity(labelOpacity)
                    .frame(width: 4.5, height: 9)
            }
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
                path: item.path, kind: item.kind, context: context,
                onClick: {
                    // Folders drill the cloud; a file point is selected like any other file (Enter copies its path).
                    if isFolder { context.send(.drillCloud(edge, item.path)) } else { context.send(.select(item.path)) }
                },
                onDoubleClick: { context.send(.doubleClick(item.path, item.kind)) },
                onHover: { hovered = $0 },
                menu: nodeMenu(path: item.path, context: context, specific: menuActions),
                // Folder double-click opens Finder (R7.7); wait out the interval so it does not also drill.
                delaysClick: isFolder))
        .help(item.name)
    }

    private var menuActions: [NodeAction] {
        if !isFolder {
            return [
                NodeAction(
                    title: "放进固定位", icon: .symbol("pin"),
                    action: { context.send(.pinSlot(edge, item.path)) })
            ]
        }
        var actions = [
            NodeAction(
                title: "在透镜里查看全部", icon: .symbol("list.bullet"),
                action: { context.send(.openLens(edge, folder: item.path)) })
        ]
        if item.canPin {
            actions.append(
                item.isPinned
                    ? NodeAction(title: "取消置顶", icon: .symbol("pin.slash"), action: { context.send(.unpinFolder(item.path)) })
                    : NodeAction(title: "置顶", icon: .symbol("pin"), action: { context.send(.pinFolder(edge, item.path)) }))
        }
        return actions
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
