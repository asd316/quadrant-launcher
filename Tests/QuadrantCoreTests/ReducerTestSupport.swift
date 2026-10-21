import Foundation
@testable import QuadrantCore

let t0 = Date(timeIntervalSince1970: 1_000_000)
let t1 = Date(timeIntervalSince1970: 2_000_000)
func p(_ s: String) -> NodePath { NodePath(s) }

func fullPanel(_ persistent: PersistentState = PersistentState()) -> PanelState {
    PanelState(persistent: persistent, display: .full)
}

func run(_ state: PanelState, _ intent: Intent, at now: Date = t1) -> (PanelState, [Effect]) {
    reduce(state, intent, now: now)
}

func usageEvents(_ fx: [Effect]) -> [UsageEvent] {
    fx.compactMap { if case .recordUsage(let e) = $0 { e } else { nil } }
}

func mutations(_ fx: [Effect]) -> [StateMutation] {
    var out: [StateMutation] = []
    for e in fx { if case .persist(let m) = e { out += m } }
    return out
}

func stashItem(_ path: String, _ at: Date) -> StashItem {
    StashItem(targetPath: p(path), kind: .file, addedAt: at)
}
