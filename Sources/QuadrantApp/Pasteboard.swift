import AppKit
import QuadrantCore
import QuadrantSystem

/// The only place the App writes to the general pasteboard.
@MainActor
enum PasteboardWriter {
    /// Path text only (R7.1).
    static func writePath(_ path: NodePath) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(path.raw, forType: .string)
    }

    /// R8.1: file reference plus path text, so Finder pastes the file and a text field pastes the path.
    static func writeNode(_ path: NodePath) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(URL(fileURLWithPath: path.raw).absoluteString, forType: .fileURL)
        item.setString(path.raw, forType: .string)
        pb.writeObjects([item])
    }

    /// R8.4: what ⌘V can use right now.
    static func readPasteItems() -> [PasteItem] {
        ClipboardPaths.readFromGeneralPasteboard().map { PasteItem($0.0, kind: $0.1) }
    }
}
