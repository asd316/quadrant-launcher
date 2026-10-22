import AppKit
import QuadrantCore
import enum QuadrantCore.Edge
import QuadrantUI
import SwiftUI

// Renders PanelView with fixture data to PNGs. Usage: UIPreview <output-dir>

let now = Date(timeIntervalSince1970: 1_800_000_000)
let size = CGSize(width: 1440, height: 900)

func folder(_ path: NodePath, ageDays: Double = 1, children: [FolderNode] = []) -> FolderNode {
    FolderNode(path: path, kind: .folder, modifiedAt: now.addingTimeInterval(-ageDays * 86_400), children: children)
}

func file(_ path: NodePath, ageDays: Double = 1) -> FolderNode {
    FolderNode(path: path, kind: .file, modifiedAt: now.addingTimeInterval(-ageDays * 86_400))
}

let home = NodePath("/Users/preview")
let downloads = home.appending("Downloads")
let documents = home.appending("Documents")
let desktop = home.appending("Desktop")
let knowledge = home.appending("个人知识库")

// Downloads: 8 branches, focus 论文 with 40 files.
let papers = downloads.appending("论文")
let downloadsTree = folder(
    downloads,
    children: ["截图", "安装包", "发票", "合同扫描", "照片", "视频", "音频"].enumerated().map {
        folder(downloads.appending($0.element), ageDays: Double($0.offset) + 3)
    } + [
        folder(
            papers, ageDays: 0.5,
            children: [folder(papers.appending("待读")), folder(papers.appending("已读"), ageDays: 2)]
                + (1...40).map { file(papers.appending(String(format: "paper-%02d.pdf", $0)), ageDays: Double($0) * 0.3) })
    ])

// Knowledge base: 10 branches, focus 0-projects with 37 stars.
let work = knowledge.appending("0-projects")
let realStars = ["quadrant-file-launcher", "Photo Archive", "habit-tracker", "budget-app"]
let starFolders =
    realStars.enumerated().map { folder(work.appending($0.element), ageDays: Double($0.offset) * 4) }
    + (1...33).map { folder(work.appending(String(format: "project-%02d", $0)), ageDays: Double($0) * 1.5) }
let knowledgeTree = folder(
    knowledge,
    children: [folder(work, children: starFolders)]
        + ["5-learning", "exp-setup-notes", "3-methods", "AI-chats", "todo", "2-research", "100-ideas", "F-guides", "H-sharing"]
            .enumerated().map { folder(knowledge.appending($0.element), ageDays: Double($0.offset) * 6 + 5) })

let documentsTree = folder(
    documents,
    children: ["配置", "合同", "Zoom", "项目代码", "简历", "税务"].enumerated().map {
        folder(
            documents.appending($0.element), ageDays: Double($0.offset) + 1,
            children: $0.offset == 0
                ? ["zsh", "raycast", "karabiner", "git"].map { folder(documents.appending("配置").appending($0)) } : [])
    } + [file(documents.appending("备忘.txt"))])

let desktopTree = folder(
    desktop,
    children: ["演示素材", "待处理", "草稿"].map { folder(desktop.appending($0)) }
        + ["今天要发的.pptx", "白板.png", "待签.pdf"].enumerated().map { file(desktop.appending($0.element), ageDays: Double($0.offset)) })

let state = PersistentState(
    roots: [.top: downloads, .left: knowledge, .right: documents, .bottom: desktop],
    focus: [downloads: papers, knowledge: work, documents: documents.appending("配置")],
    stash: [
        StashItem(targetPath: home.appending("报价单.xlsx"), kind: .file, addedAt: now.addingTimeInterval(-60)),
        StashItem(targetPath: home.appending("Glossary（术语表）.md"), kind: .file, addedAt: now),
    ],
    pinnedSlots: ["AGENTS.md", "Glossary.md", "Design-Principles.md", "Prototype-Brief.md", "Todo.md"].enumerated().map {
        PinnedSlot(edge: .left, targetPath: knowledge.appending($0.element), addedAt: now.addingTimeInterval(Double($0.offset)))
    })

let usage = UsageIndex(
    events: (0..<12).flatMap { i in
        (0..<max(1, 12 - i)).map { _ in
            UsageEvent(path: starFolders[i % starFolders.count].path, action: .openStar, occurredAt: now.addingTimeInterval(-Double(i) * 86_400))
        }
    },
    asOf: now)

func project(capacities: [Edge: Int]) -> [Edge: EdgeProjection] {
    Projection.project(
        state: state,
        inputs: [
            .top: EdgeInput(snapshot: FolderSnapshot(root: downloadsTree), starCapacity: capacities[.top] ?? 0, currentFolder: papers),
            .left: EdgeInput(snapshot: FolderSnapshot(root: knowledgeTree), starCapacity: capacities[.left] ?? 0),
            .right: EdgeInput(snapshot: FolderSnapshot(root: documentsTree), starCapacity: capacities[.right] ?? 0, currentFolder: documents),
            .bottom: EdgeInput(snapshot: FolderSnapshot(root: desktopTree), starCapacity: capacities[.bottom] ?? 0, currentFolder: desktop),
        ],
        usage: usage, now: now, exists: { _ in true })
}

func makeModel(lens: Bool) -> PanelRenderModel {
    var model = PanelRenderModel(
        quadrants: project(capacities: [:]),
        stash: state.stash.map { StashSlot(path: $0.targetPath, kind: $0.kind, isBroken: false) })
    let capacities = PanelLayout.starCapacities(for: model, size: size)
    model.quadrants = project(capacities: capacities)
    if lens {
        model.lens = LensModel(
            mode: .folder(edge: .top, crumbs: [downloads, papers]),
            rows: [
                LensRow(path: papers.appending("已读"), kind: .folder, modifiedAt: Date().addingTimeInterval(-2 * 86_400)),
                LensRow(path: papers.appending("待读"), kind: .folder, modifiedAt: Date().addingTimeInterval(-40 * 86_400)),
            ]
                + (1...38).map {
                    LensRow(
                        path: papers.appending(String(format: "paper-%02d.pdf", $0)), kind: .file,
                        modifiedAt: Date().addingTimeInterval(-Double($0) * 40_000 - 400_000), size: Int64($0) * 311_000)
                })
        model.keyboardSelection = papers.appending("paper-01.pdf")
    }
    return model
}

@MainActor
func render(_ model: PanelRenderModel, dark: Bool, to url: URL) {
    let view = PanelView(model: model, send: { _ in })
        .staticRendering()
        .environment(\.colorScheme, dark ? .dark : .light)
        .frame(width: size.width, height: size.height)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    guard let cg = renderer.cgImage else {
        print("render failed: \(url.lastPathComponent)")
        return
    }
    let rep = NSBitmapImageRep(cgImage: cg)
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: url)
        print("wrote \(url.path)")
    }
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".", isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let browse = makeModel(lens: false)
let lens = makeModel(lens: true)
print("star capacities:", PanelLayout.starCapacities(for: browse, size: size))
render(browse, dark: false, to: outDir.appendingPathComponent("browse-light.png"))
render(browse, dark: true, to: outDir.appendingPathComponent("browse-dark.png"))
render(lens, dark: false, to: outDir.appendingPathComponent("lens-light.png"))
render(lens, dark: true, to: outDir.appendingPathComponent("lens-dark.png"))
