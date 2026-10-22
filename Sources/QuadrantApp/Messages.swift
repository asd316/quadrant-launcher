import Foundation
import QuadrantCore

/// One-line Chinese messages (Design-Principles › Copy): state the reason, never apologize.
enum Messages {
    static let stateReset = "状态已重置"

    static func text(for rejection: Rejection) -> String {
        switch rejection {
        case .pinsFull: "置顶已满"
        case .pinnedSlotsFull(_, let capacity): "固定位已满（\(capacity) 个）"
        case .pinnedSlotsFilesOnly: "固定位只能放文件"
        case .clipboardEmpty: "剪贴板里没有可用的文件或路径"
        case .copyIntoItself: "不能复制到它自己里面"
        }
    }

    static func text(for notice: Notice) -> String {
        switch notice {
        case .copiedTo(let name): "已复制到 \(name)"
        case .copyFailed(let reason): "复制失败：\(reason)"
        }
    }

    static func text(for issues: [ShortcutIssue]) -> String? {
        guard let first = issues.first else { return nil }
        let detail: String
        switch first {
        case .malformedFile: detail = "shortcuts.json 格式不对"
        case .unknownAction(let name): detail = "未知动作 \(name)"
        case .invalidChord(let action, let chord, _): detail = "\(action) 的快捷键 \(chord) 无效"
        case .conflict(let action, let chord, _): detail = "\(action) 的快捷键 \(chord) 与其他动作冲突"
        }
        let rest = issues.count > 1 ? "等 \(issues.count) 处" : ""
        return "快捷键配置：\(detail)\(rest)，已用默认值"
    }

    static let storeSaveFailed = "保存失败"
}
