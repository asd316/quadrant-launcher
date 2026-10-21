import CoreServices
import Foundation
import QuadrantCore
import Synchronization

/// One FSEvents stream feeding one `AsyncStream`. The stream is owned by this object
/// and torn down when the consumer cancels or finishes.
final class FSEventsWatcher: Sendable {
    private let continuation: AsyncStream<Set<NodePath>>.Continuation
    private let queue = DispatchQueue(label: "quadrant.fsevents")
    /// Address of the running stream, 0 when none. Kept as an integer because the C pointer is not Sendable.
    private let stream = Mutex<UInt>(0)

    private init(continuation: AsyncStream<Set<NodePath>>.Continuation) {
        self.continuation = continuation
    }

    /// Latency is FSEvents' own coalescing window: events inside it arrive as one callback.
    static func stream(roots: [NodePath], latency: TimeInterval = 0.3) -> AsyncStream<Set<NodePath>> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            guard !roots.isEmpty else {
                continuation.finish()
                return
            }
            let watcher = FSEventsWatcher(continuation: continuation)
            guard watcher.start(roots: roots, latency: latency) else {
                continuation.finish()
                return
            }
            continuation.onTermination = { _ in watcher.stop() }
        }
    }

    private func start(roots: [NodePath], latency: TimeInterval) -> Bool {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(self).toOpaque(),
            retain: nil,
            release: { info in
                if let info { Unmanaged<FSEventsWatcher>.fromOpaque(info).release() }
            },
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
            let cPaths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
            var changed = Set<NodePath>()
            for index in 0..<count {
                changed.insert(NodePath(String(cString: cPaths[index])))
            }
            if !changed.isEmpty { watcher.continuation.yield(changed) }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(
            nil, callback, &context, roots.map(\.raw) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
        ) else {
            // Stream was never created, so the context's retain was not consumed.
            Unmanaged<FSEventsWatcher>.fromOpaque(context.info!).release()
            return false
        }
        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            return false
        }
        stream.withLock { $0 = UInt(bitPattern: created) }
        return true
    }

    private func stop() {
        let address = stream.withLock { current -> UInt in
            defer { current = 0 }
            return current
        }
        guard let running = FSEventStreamRef(bitPattern: address) else { return }
        FSEventStreamStop(running)
        FSEventStreamInvalidate(running)
        FSEventStreamRelease(running)
    }
}
