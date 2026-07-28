import Foundation
import UserNotifications

// ─────────────────────────────────────────────────────────────────────────────
// Posts local notifications via UNUserNotificationCenter while native owns
// upload status: app backgrounded or Dart gone. Permission must already be
// granted while foregrounded.
// ─────────────────────────────────────────────────────────────────────────────

public final class UploadStallNotifierImpl: UploadStallNotifier {
    public static let shared = UploadStallNotifierImpl()

    /// THE single identifier for every upload banner — progress, stall, and
    /// finish — shared with Dart's foreground upload notification
    /// (`UploadForegroundNotifier._notificationId = 1001`).
    ///
    /// flutter_local_notifications maps an integer notification id to the
    /// `UNNotificationRequest` identifier via `[id stringValue]`, so Dart's id
    /// `1001` lands on the iOS identifier `"1001"`. Reusing it here makes native's
    /// banners REPLACE Dart's ongoing/paused notification (and each other) in
    /// place instead of stacking — so a pause/stall is shown exactly ONCE,
    /// whether the banner came from Dart (user pause) or native (URL stall),
    /// and the user never sees 2–4 separate upload notifications.
    private static let uploadNotificationId = "1001"

    private init() {}

    public func notifyUrlStall(sessionId: String, uploaded: Int, total: Int) {
        // Generic body: the shared identifier means one banner can represent
        // several stalled sessions (and replaces any Dart "Uploads Paused"
        // banner), so a single-session "X/Y parts" count would be misleading.
        // Opening the app refreshes links for all of them.
        post(
            identifier: Self.uploadNotificationId,
            title: "Upload paused",
            body: "Open the app to refresh upload links and continue."
        )
    }

    public func notifyTransferStall(sessionId: String) {
        // Shared slot, so this replaces any climbing progress banner in place
        // rather than stacking. Generic copy: the cause is usually a lost
        // connection (iOS resumes automatically when it returns) but can also be
        // a server rejection that needs the app reopened — "Open the app" covers
        // both, since reopening always re-pumps the stalled session.
        post(
            identifier: Self.uploadNotificationId,
            title: "Upload paused",
            body: "Your upload was interrupted. Open the app to resume."
        )
    }

    public func notifyFinishNeeded(sessionId: String) {
        // Same shared slot, so the finish prompt supersedes the climbing progress
        // banner (and any paused banner) in place rather than leaving a stale
        // "Uploading 90%" — no explicit removal needed, the re-post replaces it.
        post(
            identifier: Self.uploadNotificationId,
            title: "Almost done!",
            body: "Open the app to finish uploading your video."
        )
    }

    public func notifyProgress(completed: Int, total: Int, percent: Int) {
        // Title "Uploading Videos", body just the percent (e.g. "25%") — the
        // batch "X/Y" count is omitted by request. Silent: this banner re-posts
        // at each milestone, so a sound each time would be noise. The
        // stall/finish prompts keep their default sound.
        post(
            identifier: Self.uploadNotificationId,
            title: "Uploading Videos",
            body: "\(percent)%",
            sound: false
        )
    }

    private func post(identifier: String, title: String, body: String, sound: Bool = true) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard
                settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
                    || settings.authorizationStatus == .ephemeral
            else {
                print(
                    "[windowed-native] notification skipped "
                        + "(permission=\(settings.authorizationStatus.rawValue)) id=\(identifier)"
                )
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if sound { content.sound = .default }
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request) { err in
                if let err = err {
                    print(
                        "[windowed-native] notification failed id=\(identifier) "
                            + "err=\(err.localizedDescription)"
                    )
                } else {
                    print("[windowed-native] notification posted id=\(identifier)")
                }
            }
        }
    }
}
