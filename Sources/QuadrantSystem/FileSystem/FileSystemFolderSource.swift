import Foundation
import QuadrantCore

public enum FolderSourceError: Error, Equatable, CustomStringConvertible {
    case folderMissing(NodePath)
    case notAFolder(NodePath)

    public var description: String {
        switch self {
        case .folderMissing(let path): "Folder does not exist: \(path.raw)"
        case .notAFolder(let path): "Path is not a folder: \(path.raw)"
        }
    }
}

/// Reads folders from disk. Read-only (R6.4). Scan rules: Data-Model › 扫描规则.
public struct FileSystemFolderSource: FolderSource {
    public init() {}

    public func snapshot(root: NodePath) async throws -> FolderSnapshot {
        let rootNode = try Self.scan(root, level: 1)
        return FolderSnapshot(root: rootNode)
    }

    public func children(of folder: NodePath) async throws -> [FolderNode] {
        try Self.requireFolder(folder)
        return Self.readChildren(of: folder)
    }

    public func exists(_ path: NodePath) -> Bool {
        FileManager.default.fileExists(atPath: path.raw)
    }

    public func changes(under roots: [NodePath]) -> AsyncStream<Set<NodePath>> {
        FSEventsWatcher.stream(roots: roots)
    }

    // MARK: - Scanning

    private static func requireFolder(_ path: NodePath) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path.raw, isDirectory: &isDirectory) else {
            throw FolderSourceError.folderMissing(path)
        }
        guard isDirectory.boolValue else { throw FolderSourceError.notAFolder(path) }
    }

    /// Scans `path` as level `level`. Folders at levels 1 and 2 are scanned further;
    /// a level-3 folder gets its direct files only.
    private static func scan(_ path: NodePath, level: Int) throws -> FolderNode {
        try requireFolder(path)
        let modifiedAt = modificationDate(path)
        var children: [FolderNode] = []
        for entry in readChildren(of: path) {
            if entry.kind == .folder, !entry.isSymlink, level < 3 {
                children.append(try scan(entry.path, level: level + 1))
            } else if entry.kind == .folder, level >= 3 {
                continue
            } else {
                children.append(entry)
            }
        }
        return FolderNode(path: path, kind: .folder, modifiedAt: modifiedAt, children: children)
    }

    /// Direct children, shallow nodes, hidden names skipped, sorted by path.
    private static func readChildren(of folder: NodePath) -> [FolderNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]
        let url = URL(fileURLWithPath: folder.raw, isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys, options: []
        ) else { return [] }
        var nodes: [FolderNode] = []
        for child in urls {
            let name = child.lastPathComponent
            if name.hasPrefix(".") { continue }
            let values = try? child.resourceValues(forKeys: Set(keys))
            let isSymlink = values?.isSymbolicLink ?? false
            let path = folder.appending(name)
            var isDirectory = values?.isDirectory ?? false
            if isSymlink {
                // Kind follows the target; a broken link counts as a file.
                var targetIsDirectory: ObjCBool = false
                isDirectory = FileManager.default.fileExists(atPath: path.raw, isDirectory: &targetIsDirectory)
                    && targetIsDirectory.boolValue
            }
            nodes.append(FolderNode(
                path: path,
                kind: isDirectory ? .folder : .file,
                modifiedAt: values?.contentModificationDate ?? .distantPast,
                size: isDirectory ? nil : values?.fileSize.map(Int64.init),
                isSymlink: isSymlink
            ))
        }
        return nodes.sorted { $0.path < $1.path }
    }

    private static func modificationDate(_ path: NodePath) -> Date {
        let url = URL(fileURLWithPath: path.raw)
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }
}
