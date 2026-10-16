#if os(iOS)
import BackgroundTasks
import Foundation

/// Opportunistic jumpstart for `PhotoBackgroundUploader`'s upload chain. The chain is normally
/// self-sustaining (finishing a batch's last chunk wakes the app via
/// `urlSessionDidFinishEvents(forBackgroundURLSession:)`, which immediately enqueues the next
/// batch), so this only matters when the chain has gone fully idle: right after sign-in, before
/// anything has ever been enqueued, or if the system ever drops every outstanding background task.
public enum PhotoBackupScheduler {
    public static let taskIdentifier = "com.migueltaibo.tpapp.photobackup"

    /// Must run before the app finishes launching, per `BGTaskScheduler`'s own requirement — call
    /// from the app delegate's `didFinishLaunching`, never from a SwiftUI `.task`/view lifecycle,
    /// which can run too late (or not at all, for a launch that exists only to run this task).
    public static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            // swiftlint:disable:next force_cast — BGTaskScheduler guarantees the task it hands
            // back for this identifier matches how it was requested, below, as a processing task.
            handle(task as! BGProcessingTask)
        }
    }

    private static func handle(_ task: BGProcessingTask) {
        // Resubmit before doing anything else: if `refill()` crashes or the task expires, the
        // next opportunistic window is still scheduled instead of the chain going dark forever.
        scheduleNext()

        let completion = CompletionGuard(task)
        let work = Task {
            let madeProgress = await PhotoBackgroundUploader.shared.refill()
            completion.complete(success: madeProgress)
        }
        task.expirationHandler = {
            work.cancel()
            completion.complete(success: false)
        }
    }

    /// Call at app startup (in addition to `register()`, which only wires the handler and by
    /// itself never causes iOS to invoke it) and again after every sign-in, since signing out
    /// clears the remembered owner email `refill()` needs.
    public static func scheduleNext() {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// `BGTask.setTaskCompleted(success:)` must be called exactly once; without this guard, a
/// cancelled `work` task that nonetheless runs its completion line *after* `expirationHandler`
/// already fired would call it a second time. `@unchecked Sendable`: the lock is the actual
/// synchronization, `BGProcessingTask` itself is only ever touched while holding it.
private final class CompletionGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private let task: BGProcessingTask

    init(_ task: BGProcessingTask) {
        self.task = task
    }

    func complete(success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        task.setTaskCompleted(success: success)
    }
}
#endif
