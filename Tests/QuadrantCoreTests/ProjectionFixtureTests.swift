import Foundation
import Testing

@testable import QuadrantCore

/// Shared fixtures (Prototype-Brief test dataset) for the Weight and Projection tests.
enum Fixture {
    static let now = Date(timeIntervalSince1970: 1_792_000_000)
    static let day: TimeInterval = 86_400

    static func ago(days: Double) -> Date { now.addingTimeInterval(-days * day) }
    /// Old enough that recency is effectively 0.
    static let old = ago(days: 3_000)

    static func file(_ path: String, modified: Date? = nil) -> FolderNode {
        FolderNode(path: NodePath(path), kind: .file, modifiedAt: modified ?? old)
    }

    static func folder(_ path: String, modified: Date? = nil, _ children: [FolderNode] = []) -> FolderNode {
        FolderNode(path: NodePath(path), kind: .folder, modifiedAt: modified ?? old, children: children)
    }

    static func event(_ path: String, daysAgo: Double = 0, _ action: UsageAction = .openStar) -> UsageEvent {
        UsageEvent(path: NodePath(path), action: action, occurredAt: ago(days: daysAgo))
    }

    static func index(_ events: [UsageEvent]) -> UsageIndex { UsageIndex(events: events, asOf: now) }

    // Left quadrant: 个人知识库, 10 branches, the first with 37 L3 folders.
    static let kbRoot = "/Users/demo/Documents/Notes"
    static let workbench = "\(kbRoot)/0-projects"
    static let launcher = "\(workbench)/quadrant-file-launcher"

    static let branchNames = [
        "0-projects", "5-learning", "exp-setup-notes", "3-methods", "AI-chats",
        "todo", "1-background", "2-research", "F-guides", "H-sharing",
    ]

    static var workbenchStars: [FolderNode] {
        let real = ["quadrant-file-launcher", "Photo Archive", "habit-tracker", "budget-app"]
            .map { folder("\(workbench)/\($0)") }
        let filler = (1...33).map { folder("\(workbench)/project-\(String(format: "%02d", $0))") }
        return real + filler
    }

    static var knowledgeBase: FolderSnapshot {
        let branches = branchNames.map { name -> FolderNode in
            let path = "\(kbRoot)/\(name)"
            return name == "0-projects" ? folder(path, workbenchStars) : folder(path)
        }
        return FolderSnapshot(root: folder(kbRoot, branches))
    }

    // Top quadrant: Downloads.
    static let downloads = "/Users/demo/Downloads"

    static var downloadsSnapshot: FolderSnapshot {
        let papers = folder(
            "\(downloads)/论文",
            [folder("\(downloads)/论文/已读"), folder("\(downloads)/论文/待读")]
                + (1...40).map { file("\(downloads)/论文/paper-\(String(format: "%02d", $0)).pdf") })
        let installers = folder(
            "\(downloads)/安装包",
            ["Cursor.dmg", "Raycast.dmg", "node-v22.pkg"].map { file("\(downloads)/安装包/\($0)") })
        let course = folder(
            "\(downloads)/课程", (1...6).map { folder("\(downloads)/课程/第\($0)周") })
        let rest = ["截图", "发票", "临时", "数据导出", "字体"].map { folder("\(downloads)/\($0)") }
        return FolderSnapshot(root: folder(downloads, [papers, installers, course] + rest + [file("\(downloads)/报价单.xlsx")]))
    }
}

@Test func fixtureTreeLooksRight() {
    #expect(Fixture.knowledgeBase.node(at: NodePath(Fixture.launcher)) != nil)
    #expect(Fixture.knowledgeBase.root.folders.count == 10)
    #expect(Fixture.workbenchStars.count == 37)
}
