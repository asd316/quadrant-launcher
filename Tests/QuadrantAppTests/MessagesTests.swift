import QuadrantCore
import Testing

@testable import QuadrantApp

@Suite struct MessagesTests {
    @Test func rejectionWording() {
        #expect(Messages.text(for: .pinnedSlotsFull(.top, capacity: 5)) == "固定位已满（5 个）")
        #expect(Messages.text(for: .pinsFull(capacity: 4)) == "置顶已满")
        #expect(Messages.text(for: .clipboardEmpty) == "剪贴板里没有可用的文件或路径")
        #expect(Messages.text(for: .copyIntoItself) == "不能复制到它自己里面")
        #expect(Messages.text(for: .pinnedSlotsFilesOnly) == "固定位只能放文件")
    }

    @Test func noticeWording() {
        #expect(Messages.text(for: .copiedTo(folderName: "资料")) == "已复制到 资料")
        #expect(Messages.text(for: .copyFailed(reason: "磁盘已满")) == "复制失败：磁盘已满")
    }

    @Test func shortcutIssuesSummarizeOnce() {
        #expect(Messages.text(for: []) == nil)
        let one = Messages.text(for: [.malformedFile])
        #expect(one == "快捷键配置：shortcuts.json 格式不对，已用默认值")
        let many = Messages.text(for: [.unknownAction("x"), .malformedFile])
        #expect(many?.contains("等 2 处") == true)
    }

    @Test func firstRunSeedUsesOnlyExistingFolders() {
        let all = FirstRunSeed.roots(home: "/Users/u", exists: { _ in true })
        #expect(all[.top] == np("/Users/u/Downloads"))
        #expect(all[.bottom] == np("/Users/u/Desktop"))
        #expect(all[.right] == np("/Users/u/Documents"))
        #expect(all[.left] == np("/Users/u/Documents/Notes"))
        let some = FirstRunSeed.roots(home: "/Users/u", exists: { !$0.contains("Notes") })
        #expect(some[.left] == nil)
        #expect(some.count == 3)
    }
}
