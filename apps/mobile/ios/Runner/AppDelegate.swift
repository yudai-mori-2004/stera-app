import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Phase 2: register the windowed engine's BGProcessingTask handler before
        // the app finishes launching (required). Inert unless a session schedules
        // a request; the identifier is in Info.plist BGTaskSchedulerPermittedIdentifiers.
        if #available(iOS 13.0, *) {
            ChunkWindowManager.shared.registerBackgroundTask()
        }
        // Sweep zombie background tasks left by sessions that already finished or
        // were cancelled in a prior run, so they don't starve the live upload's
        // connection budget. Safe at any time; matches tasks by their stable
        // taskDescription key and never touches a live session.
        ChunkWindowManager.shared.reconcileOnLaunch()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    /// Called by iOS when background URL session events are pending.
    /// This happens when app was terminated and uploads completed in background.
    /// Stays in AppDelegate because background URL session callbacks are delivered
    /// at the application level, not the scene level.
    override func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        if identifier == "io.rootlens.app.iosWindowedUploader" {
            // Phase 2 windowed engine: the out-of-process daemon wakes us with
            // completion events; the manager journals + refills its window.
            ChunkWindowManager.shared.backgroundCompletionHandler = completionHandler
            NSLog("✅ AppDelegate: Handling windowed URL session events for %@", identifier)
            UserDefaults.standard.set(
                Date().timeIntervalSince1970,
                forKey: "lastWindowedURLSessionWakeup"
            )
        } else {
            NSLog("⚠️ AppDelegate: Unknown background URL session: %@", identifier)
            completionHandler()
        }
    }
}
