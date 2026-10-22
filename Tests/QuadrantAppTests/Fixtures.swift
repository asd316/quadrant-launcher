import Foundation
import QuadrantCore
import QuadrantUI

@testable import QuadrantApp

let fxNow = Date(timeIntervalSince1970: 2_000_000)
func np(_ s: String) -> NodePath { NodePath(s) }

func folder(_ path: String, _ children: [FolderNode] = []) -> FolderNode {
    FolderNode(path: np(path), kind: .folder, modifiedAt: fxNow, children: children)
}

func file(_ path: String) -> FolderNode {
    FolderNode(path: np(path), kind: .file, modifiedAt: fxNow)
}

/// /r/top: branches Alpha (star Docs with a file, file note.txt) and Beta.
func topSnapshot() -> FolderSnapshot {
    FolderSnapshot(root: folder("/r/top", [
        folder("/r/top/Alpha", [
            folder("/r/top/Alpha/Docs", [file("/r/top/Alpha/Docs/spec.md")]),
            file("/r/top/Alpha/note.txt"),
        ]),
        folder("/r/top/Beta"),
        file("/r/top/readme.txt"),
    ]))
}

func baseState() -> PanelState {
    var persistent = PersistentState()
    persistent.roots[.top] = np("/r/top")
    persistent.focus[np("/r/top")] = np("/r/top/Alpha")
    return PanelState(persistent: persistent, display: .full)
}

func renderInputs(
    state: PanelState, cache: [NodePath: [FolderNode]] = [:], selection: NodePath? = nil
) -> RenderInputs {
    RenderInputs(
        state: state, snapshots: [.top: topSnapshot()], starCapacity: [.top: 3], childrenCache: cache,
        usage: UsageIndex(events: [], asOf: fxNow), now: fxNow, exists: .all, selection: selection,
        copyProgress: nil, message: nil)
}

func render(_ state: PanelState, cache: [NodePath: [FolderNode]] = [:], selection: NodePath? = nil) -> PanelRenderModel {
    RenderModelBuilder.build(renderInputs(state: state, cache: cache, selection: selection))
}

func mapping(_ state: PanelState, cache: [NodePath: [FolderNode]] = [:], capacity: [Edge: Int] = [.top: 3]) -> MappingContext {
    MappingContext(state: state, model: render(state, cache: cache), starCapacity: capacity, exists: .all)
}

/// Intents inside commands, in order. Other commands are dropped.
func intents(_ commands: [AppCommand]) -> [Intent] {
    commands.compactMap { if case .intent(let i) = $0 { i } else { nil } }
}

func describe(_ commands: [AppCommand]) -> [String] {
    commands.map {
        switch $0 {
        case .intent(let i): describe(i)
        case .select(let p): "select(\(p?.raw ?? "nil"))"
        case .reveal(let p): "reveal(\(p.raw))"
        case .starCapacity(let e, let n): "starCapacity(\(e),\(n))"
        case .dismissPanel: "dismissPanel"
        }
    }
}

func describe(_ intent: Intent) -> String {
    switch intent {
    case .focusBranch(let e, let b): "focusBranch(\(e),\(b.raw))"
    case .clickStar(let e, let s, _): "clickStar(\(e),\(s.raw))"
    case .openLens(let e, let f): "openLens(\(e),\(f.raw))"
    case .lensEnter(let f): "lensEnter(\(f.raw))"
    case .lensBack: "lensBack"
    case .setFilter(let t): "setFilter(\(t))"
    case .copyPath(let p): "copyPath(\(p.raw))"
    case .open(let p): "open(\(p.raw))"
    case .beginDrag(let p, _): "beginDrag(\(p.raw))"
    case .endDrag(let o): "endDrag(\(o))"
    case .stashAdd(let p, _): "stashAdd(\(p.raw))"
    case .stashRemove(let p): "stashRemove(\(p.raw))"
    case .pinSlot(let e, let p, _): "pinSlot(\(e),\(p.raw))"
    case .unpinSlot(let e, let p): "unpinSlot(\(e),\(p.raw))"
    case .hide(let p): "hide(\(p.raw))"
    case .unhide(let p): "unhide(\(p.raw))"
    case .pin(let p, let r): "pin(\(p.raw),\(r.pinnedCount)/\(r.capacity))"
    case .unpin(let p): "unpin(\(p.raw))"
    case .crossNavigate(let d): "cross(\(d))"
    case .copyNode(let p, _): "copyNode(\(p.raw))"
    case .paste(let items, let t): "paste(\(items.map(\.path.raw)),\(t))"
    case .escape: "escape"
    default: String(describing: intent)
    }
}
