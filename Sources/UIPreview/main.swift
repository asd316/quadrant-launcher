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

// Every folder and file name is a code (quadrant letter + number) so screenshots show no real names.
let home = NodePath("/Users/preview")
let downloads = home.appending("Folder A")
let knowledge = home.appending("Folder B")
let documents = home.appending("Folder C")
let desktop = home.appending("Folder D")

func codes(_ prefix: String, _ range: ClosedRange<Int>, _ format: String = "%02d", ext: String = "") -> [String] {
    range.map { prefix + String(format: format, $0) + ext }
}

// Folder A: 8 branches, focus A8 with 40 files.
let papers = downloads.appending("A8")
let downloadsTree = folder(
    downloads,
    children: codes("A", 1...7, "%d").enumerated().map {
        folder(downloads.appending($0.element), ageDays: Double($0.offset) + 3)
    } + [
        folder(
            papers, ageDays: 0.5,
            children: [folder(papers.appending("A8-1")), folder(papers.appending("A8-2"), ageDays: 2)]
                + codes("A8-", 1...40, ext: ".pdf").enumerated().map { file(papers.appending($0.element), ageDays: Double($0.offset + 1) * 0.3) })
    ])

// Folder B: 10 branches, focus B1 with 37 stars.
let work = knowledge.appending("B1")
let starFolders = codes("B1-", 1...37).enumerated().map { folder(work.appending($0.element), ageDays: Double($0.offset) * 1.5) }
let knowledgeTree = folder(
    knowledge,
    children: [folder(work, children: starFolders)]
        + codes("B", 2...10, "%d").enumerated().map { folder(knowledge.appending($0.element), ageDays: Double($0.offset) * 6 + 5) })

let documentsTree = folder(
    documents,
    children: codes("C", 1...6, "%d").enumerated().map {
        folder(
            documents.appending($0.element), ageDays: Double($0.offset) + 1,
            children: $0.offset == 0 ? codes("C1-", 1...4, "%d").map { folder(documents.appending("C1").appending($0)) } : [])
    } + [file(documents.appending("C-01.txt"))])

let desktopTree = folder(
    desktop,
    children: codes("D", 1...3, "%d").map { folder(desktop.appending($0)) }
        + ["D-01.pptx", "D-02.png", "D-03.pdf"].enumerated().map { file(desktop.appending($0.element), ageDays: Double($0.offset)) })

let state = PersistentState(
    roots: [.top: downloads, .left: knowledge, .right: documents, .bottom: desktop],
    focus: [downloads: papers, knowledge: work, documents: documents.appending("C1")],
    stash: [
        StashItem(targetPath: home.appending("S-01.xlsx"), kind: .file, addedAt: now.addingTimeInterval(-60)),
        StashItem(targetPath: home.appending("S-02.md"), kind: .file, addedAt: now),
    ],
    pinnedSlots: codes("P-", 1...5, ext: ".md").enumerated().map {
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
                LensRow(path: papers.appending("A8-2"), kind: .folder, modifiedAt: Date().addingTimeInterval(-2 * 86_400)),
                LensRow(path: papers.appending("A8-1"), kind: .folder, modifiedAt: Date().addingTimeInterval(-40 * 86_400)),
            ]
                + (1...38).map {
                    LensRow(
                        path: papers.appending(String(format: "A8-%02d.pdf", $0)), kind: .file,
                        modifiedAt: Date().addingTimeInterval(-Double($0) * 40_000 - 400_000), size: Int64($0) * 311_000)
                })
        model.keyboardSelection = papers.appending("A8-01.pdf")
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
