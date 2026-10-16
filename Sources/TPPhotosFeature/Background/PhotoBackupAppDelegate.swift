#if os(iOS)
import UIKit

/// `BGTaskScheduler` registration and `handleEventsForBackgroundURLSession` both require a
/// `UIApplicationDelegate` — SwiftUI's `App` protocol has no equivalent hook for either — so
/// `TPAppApp` wires this in via `@UIApplicationDelegateAdaptor`.
public final class PhotoBackupAppDelegate: NSObject, UIApplicationDelegate {
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        PhotoBackupScheduler.register()
        PhotoBackupScheduler.scheduleNext()
        // Reconnects to the background URLSession identifier on every launch, including one that
        // exists only to run the BGProcessingTask above — otherwise its delegate callbacks would
        // have nothing listening and completed chunk uploads would go unprocessed.
        PhotoBackgroundUploader.shared.activate()
        return true
    }

    public func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        PhotoBackgroundUploader.shared.handleEventsForBackgroundURLSession(completion: completionHandler)
    }
}
#endif
