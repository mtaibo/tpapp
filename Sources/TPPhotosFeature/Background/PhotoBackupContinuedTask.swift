#if os(iOS)
import BackgroundTasks
import Foundation

/// Keeps a user-started "Backup now" run alive after the app leaves the foreground, using iOS 26's
/// `BGContinuedProcessingTask`: the system shows the run's progress in its own UI and lets the
/// process keep executing while it keeps reporting progress, instead of suspending it a few
/// seconds after the user switches apps or locks the screen.
///
/// This is what actually makes a large backup finish unattended. `PhotoBackgroundUploader`'s
/// background-session chain can't: chunk tasks it enqueues while the app is already in the
/// background are treated as discretionary by iOS, so they mostly wait for Wi-Fi + charging.
///
/// Usage: `start(onExpire:)` when the run begins, `update(completed:total:)` as photos land, and
/// `finish(success:)` exactly once at the end. If the system refuses the request (or the device
/// doesn't support it) every call is a no-op and the run just behaves as a foreground run.
@MainActor
final class PhotoBackupContinuedTask {
    /// Must match the wildcard entry in Info.plist's `BGTaskSchedulerPermittedIdentifiers`
    /// (`com.migueltaibo.tpapp.photobackup.continued.*`).
    private static let identifierPrefix = "com.migueltaibo.tpapp.photobackup.continued"

    private var task: BGContinuedProcessingTask?
    private var isFinished = false
    private var lastCompleted = 0
    private var lastTotal = 0

    /// `onExpire` runs when the system (or the user, from the system progress UI) stops the task —
    /// the caller should stop starting new uploads.
    func start(onExpire: @escaping @MainActor () -> Void) {
        // A fresh identifier per run: registering the same identifier twice throws, and continued
        // tasks (unlike BGProcessingTask) may be registered right before they're submitted.
        let identifier = "\(Self.identifierPrefix).\(UUID().uuidString)"

        // `using: .main` so the launch handler runs on the main thread and can touch this
        // main-actor state directly, without sending the (non-Sendable) task across actors.
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                guard let task = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                guard let self, !self.isFinished else {
                    task.setTaskCompleted(success: true) // the run already ended before iOS launched this
                    return
                }
                task.expirationHandler = { [weak self] in
                    Task { @MainActor in
                        onExpire()
                        self?.finish(success: false)
                    }
                }
                self.task = task
                self.report()
            }
        }
        guard registered else { return }

        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: "Photo Backup",
            subtitle: "Preparing…"
        )
        // Fail instead of queueing: a backup that only starts minutes later, after the user has
        // moved on, would be more confusing than one that just runs in the foreground.
        request.strategy = .fail
        BGTaskScheduler.shared.submitTaskRequest(request) { _ in }
    }

    func update(completed: Int, total: Int) {
        lastCompleted = completed
        lastTotal = total
        report()
    }

    func finish(success: Bool) {
        guard !isFinished else { return }
        isFinished = true
        guard let task else { return }
        report()
        task.setTaskCompleted(success: success)
        self.task = nil
    }

    private func report() {
        guard let task else { return }
        // Total stays 0 (indeterminate) while the library is still being scanned/checked.
        task.progress.totalUnitCount = Int64(lastTotal)
        task.progress.completedUnitCount = Int64(lastCompleted)
        let subtitle = lastTotal == 0 ? "Preparing…" : "\(lastCompleted) of \(lastTotal) photos"
        task.updateTitle("Photo Backup", subtitle: subtitle)
    }
}
#endif
