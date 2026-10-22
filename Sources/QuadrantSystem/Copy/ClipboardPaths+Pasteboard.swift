import AppKit
import Foundation
import QuadrantCore

extension ClipboardPaths {
    /// Reads file URLs and text from the general pasteboard and resolves them (R8.4).
    @MainActor
    public static func readFromGeneralPasteboard() -> [(NodePath, NodeKind)] {
        let pasteboard = NSPasteboard.general
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        let fileURLs = objects.compactMap { $0 as? URL }
        let text = pasteboard.string(forType: .string)
        return resolve(fileURLs: fileURLs, text: text, exists: { FileManager.default.fileExists(atPath: $0) })
    }
}
