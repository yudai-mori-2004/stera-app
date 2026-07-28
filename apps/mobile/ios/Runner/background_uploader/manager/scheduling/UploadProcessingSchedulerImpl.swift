import BackgroundTasks
import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Collaborator (Impl) — wraps BGTaskScheduler. When a processing slot is
// granted it chains the next request, then runs the injected `onSlot` work
// (the engine refilling its active windows). In-flight URLSession tasks keep
// running out-of-process, so the expiration handler has nothing to cancel.
// ─────────────────────────────────────────────────────────────────────────────

public final class UploadProcessingSchedulerImpl: UploadProcessingScheduler {
    private let identifier: String
    private let onSlot: () -> Void

    public init(identifier: String, onSlot: @escaping () -> Void) {
        self.identifier = identifier
        self.onSlot = onSlot
    }

    public func register() {
        guard #available(iOS 13.0, *) else { return }
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier, using: nil
        ) { [weak self] task in
            guard let self = self, let processing = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handle(processing)
        }
    }

    public func schedule() {
        guard #available(iOS 13.0, *) else { return }
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }

    @available(iOS 13.0, *)
    private func handle(_ task: BGProcessingTask) {
        schedule()  // chain the next slot
        task.expirationHandler = {
            // In-flight URLSession tasks continue out-of-process; nothing to cancel.
        }
        onSlot()
        task.setTaskCompleted(success: true)
    }
}
