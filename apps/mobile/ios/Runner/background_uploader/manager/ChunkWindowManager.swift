import Foundation

#if canImport(UIKit)
  import UIKit
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Phase 2 — the windowed transfer engine (coordinator Impl). Compiles in Xcode.
//
// Keeps at most `windowSize` parts in flight on a background URLSession,
// refilling from the journaled manifest — so progress continues across
// background wake-ups without Dart. Distinct session identifier from the legacy
// engine so both coexist behind the `ios_windowed_uploader` flag.
//
// Per practices 05 "Splitting large impls", the side concerns are extracted into
// collaborators (this file stays the transfer loop + URLSession delegate, which
// is where upload correctness lives):
//   • UploadSourceFileAccess     — security-scoped access + file protection
//   • UploadProcessingScheduler  — BGProcessingTask scheduling
//
// ⚠️ Runtime behavior (background-wake refill, termination survival) still needs
//    on-device verification; this compiles and is structurally complete.
// ─────────────────────────────────────────────────────────────────────────────

public final class ChunkWindowManager: NSObject, ChunkWindowManaging {
  public static let shared = ChunkWindowManager()

  private static let sessionIdentifier = "open.fpvlabs.stera.iosWindowedUploader"
  /// BGProcessingTask id — must match Info.plist BGTaskSchedulerPermittedIdentifiers.
  public static let backgroundTaskIdentifier = "open.fpvlabs.stera.upload.finalize"
  /// Don't start a part whose URL would expire mid-transfer.
  private static let urlFreshnessMargin: TimeInterval = 120

  private var urlSession: URLSession!
  private let journal = UploadJournal()
  private let extractor: any ChunkExtractor
  private let stallNotifier: UploadStallNotifier = UploadStallNotifierImpl.shared

  // Collaborators (practices 05 decomposition).
  private let fileAccess: UploadSourceFileAccess
  private var scheduler: UploadProcessingScheduler!

  /// Live event bridge to Dart (nil when app is background/terminated — the
  /// journal still records everything for the next drain).
  public var eventSink: (([String: Any]) -> Void)?
  public var backgroundCompletionHandler: (() -> Void)?

  /// Whether the Flutter app is currently foregrounded. Dart flips this on
  /// every app-lifecycle change. The event sink alone can't tell us this: when
  /// the app is merely backgrounded (not killed) the sink stays connected even
  /// though Dart is frozen and its in-app UI is hidden. Notifications gate on
  /// "sink gone OR app not foregrounded" so the background banner fires while
  /// suspended-but-alive, yet stays silent while the UI owns the screen.
  /// Defaults to `false` so a fresh engine relaunched headless for background
  /// URLSession events still notifies before Dart has reported its state.
  ///
  /// On the foreground → background transition the adaptive concurrency gate
  /// stops applying (Dart, its tuner included, is about to freeze), so every
  /// active window is topped up to full size — the daemon then has the whole
  /// backlog to advance through without an app wake.
  public var appForegrounded: Bool = false {
    didSet {
      guard oldValue, !appForegrounded else { return }
      for sessionId in journal.activeSessionIds() {
        fill(sessionId)
      }
    }
  }

  private let workQueue = DispatchQueue(label: "open.fpvlabs.stera.windowManager")

  /// Sessions that have asked Dart for more presigned URLs (`needUrls`) and are
  /// awaiting a `provideUrls` answer. Prevents re-emitting `needUrls` on every
  /// subsequent `fill` while one request is in flight. Mutated only on
  /// `workQueue`. Cleared by `provideUrls`/`beginSession`.
  private var urlRequestPending: Set<String> = []

  /// Whether an "Upload paused" banner has already been posted for the current
  /// stall episode — covers both a presigned-URL dry-up and a transfer parking
  /// the window (offline mid-transfer / server rejection). The background-wake
  /// refill calls `fill` on EVERY active session, so without a cross-session
  /// guard one stall fans out into one banner per session (the user saw ~20).
  /// Reset when fresh URLs arrive (`provideUrls`/`beginSession`) or a part
  /// uploads (progress = no longer stalled) so a genuine later stall re-notifies.
  /// Mutated only on `workQueue`.
  private var stallNotified = false

  /// Matches the tuner's starting level on the Dart side — an engine
  /// relaunched headless behaves like today's fixed-6 build until Dart
  /// pushes a tuned value.
  private static let defaultTransferConcurrency = 6

  /// Foreground in-flight ceiling for `fill` (the adaptive gate). Set from
  /// Dart via `setTransferConcurrency`; only consulted while
  /// `appForegrounded`. Mutated only on `workQueue`.
  private var transferConcurrency = ChunkWindowManager.defaultTransferConcurrency

  private override init() {
    self.extractor = ChunkExtractorImpl(
      tempDir: FileManager.default.temporaryDirectory
        .appendingPathComponent("ios_windowed_uploader_chunks", isDirectory: true)
    )
    self.fileAccess = UploadSourceFileAccessImpl(
      log: { print("[windowed-native] \($0)") }
    )
    super.init()
    let config = URLSessionConfiguration.background(
      withIdentifier: ChunkWindowManager.sessionIdentifier
    )
    config.sessionSendsLaunchEvents = true
    config.isDiscretionary = false
    config.waitsForConnectivity = true
    config.timeoutIntervalForResource = 7 * 24 * 3600
    config.timeoutIntervalForRequest = 120
    // Static per-host PUT ceiling — URLSession can't change it after the
    // session is created, so it's pinned at the adaptive gate's MAX and the
    // real foreground parallelism lever is `transferConcurrency` (how many
    // tasks fill() keeps in flight, 5–10, tuned from Dart by measured part
    // durations). Backgrounded, in-flight = windowSize and this cap is what
    // bounds the daemon's parallelism.
    config.httpMaximumConnectionsPerHost = 10
    if #available(iOS 13.0, *) {
      config.allowsExpensiveNetworkAccess = true
      config.allowsConstrainedNetworkAccess = true
    }
    self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

    self.scheduler = UploadProcessingSchedulerImpl(
      identifier: ChunkWindowManager.backgroundTaskIdentifier,
      onSlot: { [weak self] in self?.runProcessingSlot() }
    )

    // Top the window up at willResignActive rather than waiting for Dart to
    // report the background transition: iOS honors `isDiscretionary = false`
    // only for tasks created while the app still counts as foreground (state
    // `.inactive` qualifies), and demotes anything a backgrounded app creates
    // to the daemon's deferred (discretionary) queue. Dart's `paused` report
    // arrives after the app is already `.background`, so the top-up it
    // triggers transfers slowly; this one transfers at full speed. Same 16
    // tasks either way — only the priority class changes. The `paused` didSet
    // top-up stays as the fallback.
    #if canImport(UIKit)
      NotificationCenter.default.addObserver(
        self, selector: #selector(handleWillResignActive),
        name: UIApplication.willResignActiveNotification, object: nil
      )
    #endif
  }

  // MARK: - IosWindowedUploader

  public func beginSession(_ manifest: UploadSessionManifest) {
    journal.upsertSession(
      sessionId: manifest.sessionId, fileUrl: manifest.fileUrl,
      chunkSize: manifest.chunkSize, fileSize: manifest.fileSize,
      contentType: manifest.contentType, windowSize: manifest.windowSize,
      state: "active"
    )
    journal.upsertParts(manifest.parts.map { planned($0, sessionId: manifest.sessionId) })
    journal.clearStallNotificationSent(manifest.sessionId)
    // Make the source readable by the out-of-process daemon while the screen is
    // locked — the key to uninterrupted locked uploads (req 2). Done here
    // because beginSession runs foregrounded/unlocked, so the attribute is
    // writable now even if a later refill happens while locked.
    fileAccess.relaxProtection(manifest.fileUrl)
    // Fresh start/resume carries its own batch of URLs, so clear any stale
    // pending-request flag — otherwise a session that asked for URLs, was
    // interrupted, then resumed could never re-ask. Also re-arm the URL-stall
    // banner: fresh URLs mean we're no longer stalled, so a future dry-up
    // should be able to notify again.
    workQueue.async {
      self.urlRequestPending.remove(manifest.sessionId)
      self.stallNotified = false
    }
    // Resume reconciliation: parts left `inFlight` by a prior run are only
    // rescheduled if no live URLSession task still owns them. Adopt the live
    // ones, reclaim the orphans, then fill. getAllTasks is async, so fill
    // runs in its completion to see the reconciled state.
    urlSession.getAllTasks { tasks in
      let liveKeys = Set(tasks.compactMap { $0.taskDescription })
      let reclaimed = self.journal.reclaimOrphanedInFlight(
        sessionId: manifest.sessionId, liveKeys: liveKeys
      )
      self.log(
        "beginSession \(manifest.sessionId): liveTasks=\(tasks.count) "
          + "reclaimedOrphans=\(reclaimed)")
      self.fill(manifest.sessionId)
    }
    scheduler.schedule()
  }

  public func provideUrls(sessionId: String, parts: [UploadPartPlan]) {
    journal.upsertParts(parts.map { planned($0, sessionId: sessionId) })
    journal.clearStallNotificationSent(sessionId)
    // The needUrls request was answered — allow the next one if we run dry
    // again, and re-arm the URL-stall banner (fresh URLs = no longer stalled).
    // Mutated on workQueue (same queue fill uses) so it is ordered before
    // fill's body reads it.
    workQueue.async {
      self.urlRequestPending.remove(sessionId)
      self.stallNotified = false
    }
    fill(sessionId)
  }

  public func pauseSession(sessionId: String) {
    // Let in-flight tasks finish; just stop refilling.
    journal.setSessionState(sessionId, "paused")
  }

  public func cancelSession(sessionId: String) {
    // A task belongs to this session iff its taskDescription is
    // "<sessionId>#<partNumber>" — a self-describing key that survives app
    // relaunches, so we can cancel the right tasks without consulting the
    // journal first. Capture the file url before deleting the session config.
    let fileUrl = journal.sessionConfig(sessionId)?.fileUrl
    urlSession.getAllTasks { tasks in
      var cancelled = 0
      for task in tasks where task.taskDescription?.hasPrefix("\(sessionId)#") ?? false {
        task.cancel()
        cancelled += 1
      }
      if let fileUrl = fileUrl {
        self.workQueue.async { self.fileAccess.endAccess(fileUrl) }
      }
      self.journal.deleteSession(sessionId)
      self.log("cancelSession \(sessionId): cancelledTasks=\(cancelled)")
    }
  }

  public func setTransferConcurrency(maxInFlight: Int) {
    let clamped = max(1, maxInFlight)
    workQueue.async {
      guard self.transferConcurrency != clamped else { return }
      self.transferConcurrency = clamped
      self.log("setTransferConcurrency -> \(clamped)")
    }
    // A raised gate opens headroom right away; fill() re-reads the value on
    // `workQueue` (ordered after the write above) and no-ops if nothing
    // changed, so this is safe to call unconditionally.
    for sessionId in journal.activeSessionIds() {
      fill(sessionId)
    }
  }

  public func drainJournal(sessionId: String?) -> [[String: Any]] {
    return journal.drain(sessionId: sessionId)
  }

  /// Delete journal rows Dart has applied to Drift (contract §3 drain protocol).
  public func acknowledgeDrain(_ rows: [[String: Any]]) {
    journal.deleteDrainedParts(rows)
    log("acknowledgeDrain deleted \(rows.count) row(s)")
  }

  /// Per-session transfer snapshot for the in-app dev page — release-safe
  /// visibility into whether the engine is actually scheduling work. `inFlight`
  /// counts parts currently handed to URLSession; if it's > 0 but `uploaded`
  /// never climbs, the transfers themselves are stuck (network/daemon). If it's
  /// 0 with planned parts remaining, the engine isn't scheduling. Journal-only
  /// reads, so it's synchronous and safe to call from the channel.
  public func engineState() -> [[String: Any]] {
    let freshUntil = Date().addingTimeInterval(ChunkWindowManager.urlFreshnessMargin)
    // Read on workQueue (its owning queue); safe because nothing on
    // workQueue ever syncs back to the caller.
    let concurrency = workQueue.sync { transferConcurrency }
    return journal.allSessionIds().map { sid in
      [
        "sessionId": sid,
        "state": journal.sessionState(sid) ?? "?",
        "uploaded": journal.uploadedCount(sessionId: sid),
        "inFlight": journal.inFlightCount(sessionId: sid),
        "totalParts": journal.totalParts(for: sid),
        "urlStalled": journal.isUrlStalled(sessionId: sid, freshUntil: freshUntil),
        "transferConcurrency": concurrency,
      ]
    }
  }

  public func freeDiskBytes() -> Int64 {
    // Probe the volume that holds the chunk temp dir — that's where the
    // sliding window's bytes actually land (the extractor's dir lives under
    // `temporaryDirectory`, same volume). "Important usage" is what iOS will
    // let an active, user-initiated task consume (purgeable space included),
    // so it's the honest figure to gate on.
    let probeURL = FileManager.default.temporaryDirectory
    if let values = try? probeURL.resourceValues(
      forKeys: [.volumeAvailableCapacityForImportantUsageKey]
    ), let capacity = values.volumeAvailableCapacityForImportantUsage {
      return Int64(capacity)
    }
    if let values = try? probeURL.resourceValues(
      forKeys: [.volumeAvailableCapacityKey]
    ), let capacity = values.volumeAvailableCapacity {
      return Int64(capacity)
    }
    // Couldn't read — report "plenty" so the pre-flight fails open and a
    // probe failure never blocks an upload.
    return Int64.max
  }

  // MARK: - Background processing (refill while the app is dead)

  /// Register the BGProcessingTask handler. Call once from AppDelegate
  /// `didFinishLaunching` (iOS 13+).
  @available(iOS 13.0, *)
  public func registerBackgroundTask() {
    scheduler.register()
  }

  /// Refill every active session when iOS grants a processing slot. Backend
  /// auto-complete (Phase 5 sweep) handles the final `complete`; this just keeps
  /// the bytes moving for very large uploads.
  private func runProcessingSlot() {
    for sessionId in journal.activeSessionIds() {
      fill(sessionId)
    }
  }

  /// Fill every active window to full size while task creation still earns
  /// foreground (non-discretionary) priority — see the observer registration
  /// in `init` for why this beats the Dart-`paused` top-up. The fill loop
  /// extracts + resumes one part at a time, so parts already resumed keep
  /// their priority even if the transition continues into suspension; the
  /// background-task assertion buys the rest of the pass time to finish.
  /// Also fires on transient interruptions (app switcher, Control Center) —
  /// harmless: the same parts would be scheduled on upcoming fills anyway,
  /// and the foreground gate simply pauses scheduling until in-flight drains
  /// back under it.
  @objc private func handleWillResignActive() {
    let sessions = journal.activeSessionIds()
    guard !sessions.isEmpty else { return }
    log("willResignActive: topping up \(sessions.count) session(s)")
    #if canImport(UIKit)
      let app = UIApplication.shared
      var bgTask: UIBackgroundTaskIdentifier = .invalid
      func endBgTask() {
        if bgTask != .invalid {
          app.endBackgroundTask(bgTask)
          bgTask = .invalid
        }
      }
      bgTask = app.beginBackgroundTask(withName: "windowedUploaderTopUp") {
        endBgTask()
      }
      let group = DispatchGroup()
      for sessionId in sessions {
        group.enter()
        fill(sessionId, toFullWindow: true) { group.leave() }
      }
      group.notify(queue: .main) { endBgTask() }
    #else
      for sessionId in sessions {
        fill(sessionId, toFullWindow: true)
      }
    #endif
  }

  /// One-shot launch reconciliation. iOS re-attaches a background session's
  /// persisted tasks asynchronously after relaunch; some of them belong to
  /// sessions that already finished (`drained`) or were cancelled. Those are
  /// zombies — they only burn the per-host connection budget and re-PUT work
  /// that's already done, starving the live upload. Cancel them. We do NOT
  /// touch the journal rows here: Dart still drains drained sessions to learn
  /// their results (the drain/finalize handshake owns deletion). Tasks are
  /// matched by `taskDescription` prefix, so this never affects a live session.
  public func reconcileOnLaunch() {
    urlSession.getAllTasks { tasks in
      guard !tasks.isEmpty else { return }
      for sessionId in self.journal.allSessionIds() {
        let state = self.journal.sessionState(sessionId)
        guard state == "drained" || state == "cancelled" else { continue }
        var cancelled = 0
        for task in tasks where task.taskDescription?.hasPrefix("\(sessionId)#") ?? false {
          task.cancel()
          cancelled += 1
        }
        if cancelled > 0 {
          self.log(
            "reconcileOnLaunch: cancelled \(cancelled) "
              + "zombie task(s) for \(state ?? "?") session=\(sessionId)")
        }
      }
    }
  }

  // MARK: - Window fill

  /// Schedule parts up to the window ceiling. [completion] fires on `workQueue`
  /// once this fill pass has finished extracting + `.resume()`-ing its tasks —
  /// the signal the background-wake path waits on before telling iOS it's done
  /// (otherwise iOS can suspend us mid-extraction and the session stalls with no
  /// outstanding tasks → no further wakes). Default nil for the live-app callers.
  /// [toFullWindow] skips the foreground gate — the willResignActive top-up,
  /// which must fill the whole window BEFORE the app state flips (Dart hasn't
  /// reported the transition yet, so `appForegrounded` is still true there).
  private func fill(
    _ sessionId: String, toFullWindow: Bool = false, completion: (() -> Void)? = nil
  ) {
    workQueue.async {
      defer { completion?() }
      guard self.journal.sessionState(sessionId) == "active",
        let cfg = self.journal.sessionConfig(sessionId)
      else {
        self.log(
          "fill \(sessionId): skipped "
            + "(state=\(self.journal.sessionState(sessionId) ?? "nil"))")
        return
      }
      self.fileAccess.beginAccess(cfg.fileUrl)
      let sourceURL = self.fileAccess.resolve(cfg.fileUrl)
      var scheduled = 0

      // Effective in-flight ceiling: foregrounded, the adaptive gate
      // (5–10, tuned from Dart) bounds parallelism; backgrounded, the
      // full window is the backlog the daemon advances through without
      // wakes. Everything below — the loop AND the needUrls trigger —
      // must use this ceiling, not cfg.windowSize: judging "couldn't
      // fill" against the un-gated window would emit needUrls when the
      // gate (not URL dryness) stopped the loop, and each such round
      // presigns nothing new, walking the Dart no-progress breaker
      // toward a spurious `needUrlsStall` failure.
      let ceiling =
        (self.appForegrounded && !toFullWindow)
        ? min(cfg.windowSize, self.transferConcurrency)
        : cfg.windowSize

      while self.journal.inFlightCount(sessionId: sessionId) < ceiling {
        let freshUntil = Date().addingTimeInterval(ChunkWindowManager.urlFreshnessMargin)
        guard
          let part = self.journal.claimNextSchedulablePart(
            sessionId: sessionId, freshUntil: freshUntil
          )
        else { break }

        guard
          let chunk = try? self.extractor.extract(
            sessionId: sessionId, partNumber: part.partNumber,
            sourceURL: sourceURL, offset: part.offset, length: part.length
          )
        else {
          self.journal.markError(
            sessionId: sessionId, partNumber: part.partNumber,
            newState: "planned", errorCode: "fileError",
            attempts: part.attempts + 1
          )
          continue
        }

        guard let url = URL(string: part.url ?? "") else {
          self.journal.markError(
            sessionId: sessionId, partNumber: part.partNumber,
            newState: "planned", errorCode: "urlExpired",
            attempts: part.attempts
          )
          continue
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(cfg.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(chunk.md5Base64, forHTTPHeaderField: "Content-MD5")
        let task = self.urlSession.uploadTask(with: request, fromFile: chunk.fileURL)
        // Stable, self-describing identity for the part. iOS persists
        // taskDescription with the background task and restores it across
        // app launches, so delegate callbacks can resolve the exact
        // session+part without relying on the integer taskIdentifier
        // (which is reused across launches and collides between sessions).
        task.taskDescription = "\(sessionId)#\(part.partNumber)"
        self.journal.attachTask(
          sessionId: sessionId, partNumber: part.partNumber,
          taskId: task.taskIdentifier, tempPath: chunk.fileURL.path,
          md5: chunk.md5Base64
        )
        task.resume()
        scheduled += 1
      }

      let inFlight = self.journal.inFlightCount(sessionId: sessionId)
      let uploaded = self.journal.uploadedCount(sessionId: sessionId)
      // The file's true part count, derived from its size — NOT the number
      // of rows currently in the journal (Dart feeds parts one presigned
      // batch at a time, so the journal lags the file until every batch
      // arrives). Draining on journal-rows-only would finish after just the
      // first batch and finalize would fail for the missing parts.
      let totalParts =
        cfg.chunkSize > 0
        ? Int((cfg.fileSize + Int64(cfg.chunkSize) - 1) / Int64(cfg.chunkSize))
        : uploaded
      self.log(
        "fill \(sessionId): scheduled=\(scheduled) "
          + "inFlight=\(inFlight) ceiling=\(ceiling)/\(cfg.windowSize) "
          + "uploaded=\(uploaded)/\(totalParts)")

      if inFlight == 0, uploaded >= totalParts {
        self.journal.setSessionState(sessionId, "drained")
        self.notifyFinishNeededIfNeeded(
          sessionId: sessionId, uploaded: uploaded, total: totalParts)
        self.send(["type": "sessionDrained", "sessionId": sessionId])
      } else if inFlight < ceiling, (uploaded + inFlight) < totalParts,
        !self.urlRequestPending.contains(sessionId)
      {
        let freshUntil = Date().addingTimeInterval(ChunkWindowManager.urlFreshnessMargin)
        if self.journal.isUrlStalled(sessionId: sessionId, freshUntil: freshUntil) {
          self.notifyUrlStallIfNeeded(
            sessionId: sessionId, uploaded: uploaded, total: totalParts)
        }
        self.urlRequestPending.insert(sessionId)
        self.send(["type": "needUrls", "sessionId": sessionId])
        self.log(
          "fill \(sessionId): needUrls "
            + "(uploaded=\(uploaded) inFlight=\(inFlight)/\(totalParts), awaiting next batch)"
        )
      }
    }
  }

  /// Refill active sessions after a background URLSession wake. [completion]
  /// fires (on main) only once every active session's window has been topped up
  /// — so the caller can defer the iOS background-completion handler until new
  /// tasks are actually in flight, instead of racing suspension against the
  /// async refill.
  private func refillActiveSessionsAfterBackgroundWake(completion: (() -> Void)? = nil) {
    urlSession.getAllTasks { tasks in
      let liveKeys = Set(tasks.compactMap { $0.taskDescription })
      let sessions = self.journal.activeSessionIds()
      guard !sessions.isEmpty else {
        DispatchQueue.main.async { completion?() }
        return
      }
      let group = DispatchGroup()
      for sessionId in sessions {
        let reclaimed = self.journal.reclaimOrphanedInFlight(
          sessionId: sessionId, liveKeys: liveKeys
        )
        if reclaimed > 0 {
          self.log(
            "backgroundWake: reclaimed \(reclaimed) orphan(s) session=\(sessionId)")
        }
        group.enter()
        self.fill(sessionId) { group.leave() }
      }
      group.notify(queue: .main) { completion?() }
    }
  }

  // MARK: - Helpers

  private func planned(_ p: UploadPartPlan, sessionId: String) -> JournalPart {
    JournalPart(
      sessionId: sessionId, partNumber: p.partNumber, offset: p.offset,
      length: p.length, url: p.url, urlExpiresAt: p.urlExpiresAt,
      state: "planned", taskId: nil, tempPath: nil, etag: nil, md5: nil,
      attempts: 0, errorCode: nil
    )
  }

  /// Resolve a task back to its (sessionId, partNumber) from the self-describing
  /// `taskDescription` set in `fill` ("<sessionId>#<partNumber>"). Returns nil
  /// for tasks without that key (legacy tasks or already-torn-down sessions).
  /// sessionIds never contain "#", so the last separator splits cleanly.
  private func partKey(for task: URLSessionTask) -> (sessionId: String, partNumber: Int)? {
    guard let desc = task.taskDescription,
      let hashIdx = desc.lastIndex(of: "#"),
      let partNumber = Int(desc[desc.index(after: hashIdx)...])
    else { return nil }
    return (String(desc[desc.startIndex..<hashIdx]), partNumber)
  }

  private func log(_ message: String) {
    print("[windowed-native] \(message)")
  }

  /// True when native should own user-facing notifications: either Dart is
  /// gone (sink nil) or the app is backgrounded (Dart frozen, UI hidden). When
  /// false, the foreground UI owns progress and native stays silent to avoid a
  /// double banner.
  private var shouldPostNotification: Bool {
    eventSink == nil || !appForegrounded
  }

  /// Shared gate for any "Upload paused" banner. Returns true (and claims the
  /// episode) only when native owns notifications and no banner has been posted
  /// for this stall episode yet — across ALL sessions, since the background-wake
  /// refill fills every active session and would otherwise post one banner each.
  /// Must run on `workQueue` (mutates `stallNotified`).
  private func claimStallNotification(sessionId: String) -> Bool {
    guard shouldPostNotification else { return false }
    guard !stallNotified else { return false }
    guard !journal.stallNotificationSent(sessionId) else { return false }
    stallNotified = true
    journal.markStallNotificationSent(sessionId)
    return true
  }

  private func notifyUrlStallIfNeeded(sessionId: String, uploaded: Int, total: Int) {
    // Foreground Dart can answer `needUrls` and show inline state. Once the
    // app is backgrounded or relaunched headless, a URL stall needs a local
    // prompt so the user knows opening the app will refresh links and resume.
    guard claimStallNotification(sessionId: sessionId) else { return }
    stallNotifier.notifyUrlStall(sessionId: sessionId, uploaded: uploaded, total: total)
  }

  /// Surface a single "Upload paused" banner after a part transfer fails and
  /// leaves the session parked — nothing in flight and not yet complete. This
  /// is the non-URL stall path: the device dropped offline mid-transfer (the
  /// rescheduled task now waits for connectivity) or the server rejected a part.
  /// `didCompleteWithError` runs on the delegate queue, so hop to `workQueue`
  /// before touching `stallNotified`. Deduped per stall episode and re-armed on
  /// the next successful part.
  private func notifyTransferStallIfStuck(sessionId: String) {
    workQueue.async {
      guard self.journal.inFlightCount(sessionId: sessionId) == 0 else { return }
      guard !self.journal.allPartsUploaded(sessionId: sessionId) else { return }
      guard self.claimStallNotification(sessionId: sessionId) else { return }
      self.stallNotifier.notifyTransferStall(sessionId: sessionId)
      self.log("transferStall \(sessionId): paused notification posted")
    }
  }

  /// Surface a background progress banner each time this session crosses a new
  /// 25/50/75/100 milestone. Gated on `shouldPostNotification` — while the app is
  /// foregrounded Dart owns the in-app progress UI, so native staying silent
  /// avoids a double notification. The per-session `progressNotifiedBucket`
  /// flag makes this fire once per crossed milestone rather than on every part.
  private static let progressMilestones = [25, 50, 75, 100]

  private func notifyProgressIfNeeded(sessionId: String, uploaded: Int, total: Int) {
    guard shouldPostNotification else { return }
    guard total > 0 else { return }
    let percent = min(100, uploaded * 100 / total)
    guard
      let bucket = Self.progressMilestones.last(where: { percent >= $0 })
    else { return }
    guard bucket > journal.progressNotifiedBucket(sessionId) else { return }
    journal.setProgressNotifiedBucket(sessionId, bucket)
    let counts = journal.videoCounts()
    stallNotifier.notifyProgress(
      completed: counts.completed, total: counts.total, percent: bucket)
  }

  private func notifyFinishNeededIfNeeded(sessionId: String, uploaded: Int, total: Int) {
    // Like the stall prompt: only when Dart is dead. While merely
    // backgrounded, `resumeOnLaunch` finalizes the drained session on the
    // next foreground without nagging the user.
    guard eventSink == nil else { return }
    guard !journal.finishNotificationSent(sessionId) else { return }
    journal.markFinishNotificationSent(sessionId)
    stallNotifier.notifyFinishNeeded(sessionId: sessionId)
    log("sessionDrained \(sessionId): finish notification (uploaded=\(uploaded)/\(total))")
  }

  private func cleanupTemp(_ path: String?) {
    guard let path = path else { return }
    try? FileManager.default.removeItem(atPath: path)
  }

  private func send(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in self?.eventSink?(event) }
  }
}

// MARK: - URLSession delegates

extension ChunkWindowManager: URLSessionDelegate {
  public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    log("urlSessionDidFinishEvents: refilling active sessions")
    // CRITICAL: do not call the iOS background-completion handler until the
    // next window is actually scheduled. fill() is async (chunk extraction +
    // task.resume on workQueue); calling the handler first lets iOS suspend us
    // mid-extraction, leaving the session with zero outstanding tasks — and a
    // session with no in-flight tasks gets no further wakes, so the upload
    // stalls until the user foregrounds. Hold a background-task assertion so
    // the in-process extraction survives the wake, then signal done.
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      #if canImport(UIKit)
        let app = UIApplication.shared
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        func endBgTask() {
          if bgTask != .invalid {
            app.endBackgroundTask(bgTask)
            bgTask = .invalid
          }
        }
        bgTask = app.beginBackgroundTask(withName: "windowedUploaderRefill") {
          endBgTask()
        }
        self.refillActiveSessionsAfterBackgroundWake {
          self.log("urlSessionDidFinishEvents: refill complete, signalling done")
          self.backgroundCompletionHandler?()
          self.backgroundCompletionHandler = nil
          endBgTask()
        }
      #else
        self.refillActiveSessionsAfterBackgroundWake {
          self.backgroundCompletionHandler?()
          self.backgroundCompletionHandler = nil
        }
      #endif
    }
  }
}

extension ChunkWindowManager: URLSessionTaskDelegate {
  public func urlSession(
    _ session: URLSession, task: URLSessionTask,
    didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
    totalBytesExpectedToSend: Int64
  ) {
    guard totalBytesExpectedToSend > 0,
      let key = partKey(for: task)
    else { return }
    send([
      "type": "progress", "sessionId": key.sessionId,
      "partNumber": key.partNumber,
      "bytesSent": totalBytesSent, "totalBytes": totalBytesExpectedToSend,
    ])
  }

  public func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
  ) {
    guard let key = partKey(for: task) else {
      // No self-describing key — e.g. a task created before this build, or
      // an event for a session already torn down. Dropping it is safe: such
      // parts get re-driven by the launch reclaim (planned → scheduled).
      log(
        "didComplete: no part key for task \(task.taskIdentifier) "
          + "desc=\(task.taskDescription ?? "nil") error=\(error.map { "\($0)" } ?? "nil")"
      )
      return
    }
    let sessionId = key.sessionId
    let partNumber = key.partNumber
    cleanupTemp(journal.tempPath(sessionId: sessionId, partNumber: partNumber))
    let httpStatus = (task.response as? HTTPURLResponse)?.statusCode ?? -1
    log(
      "didComplete \(sessionId) part=\(partNumber) "
        + "http=\(httpStatus) error=\(error.map { "\($0)" } ?? "nil")")

    if let error = error {
      let nativeCode = classify(error: error)
      journal.markError(
        sessionId: sessionId, partNumber: partNumber,
        newState: "planned", errorCode: nativeCode, attempts: 1
      )
      send([
        "type": "partFailed", "sessionId": sessionId,
        "partNumber": partNumber, "errorCode": nativeCode,
      ])
      notifyTransferStallIfStuck(sessionId: sessionId)
      fill(sessionId)
      return
    }

    guard let http = task.response as? HTTPURLResponse,
      http.statusCode == 200 || http.statusCode == 201
    else {
      let status = (task.response as? HTTPURLResponse)?.statusCode ?? -1
      journal.markError(
        sessionId: sessionId, partNumber: partNumber,
        newState: status == 403 ? "planned" : "error",
        errorCode: httpErrorCode(status), attempts: 1
      )
      send([
        "type": "partFailed", "sessionId": sessionId,
        "partNumber": partNumber, "errorCode": httpErrorCode(status),
        "httpStatus": status,
      ])
      notifyTransferStallIfStuck(sessionId: sessionId)
      fill(sessionId)
      return
    }

    let etag =
      (http.allHeaderFields["Etag"] as? String
      ?? http.allHeaderFields["ETag"] as? String
      ?? "").replacingOccurrences(of: "\"", with: "")
    journal.markUploaded(sessionId: sessionId, partNumber: partNumber, etag: etag)
    // Progress means we're no longer stalled — re-arm the paused banner so a
    // genuine later stall (offline again, URLs dry up) can notify afresh.
    journal.clearStallNotificationSent(sessionId)
    workQueue.async { self.stallNotified = false }
    notifyProgressIfNeeded(
      sessionId: sessionId,
      uploaded: journal.uploadedCount(sessionId: sessionId),
      total: journal.totalParts(for: sessionId)
    )
    send([
      "type": "partCompleted", "sessionId": sessionId,
      "partNumber": partNumber, "etag": etag,
    ])
    fill(sessionId)
  }

  private func classify(error: Error) -> String {
    let nsError = error as NSError
    let code = nsError.code
    if code == NSURLErrorCancelled,
      let reason = nsError.userInfo["NSURLErrorBackgroundTaskCancelledReasonKey"]
        as? NSNumber,
      reason.intValue == 0
    {
      return "userForceQuit"
    }
    switch code {
    case NSURLErrorTimedOut: return "timeout"
    case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost: return "network"
    case NSURLErrorCancelled: return "cancelled"
    default: return "network"
    }
  }

  private func httpErrorCode(_ status: Int) -> String {
    if status == 403 { return "urlExpired" }
    if status >= 500 { return "http_5xx" }
    return "http_4xx"
  }
}
