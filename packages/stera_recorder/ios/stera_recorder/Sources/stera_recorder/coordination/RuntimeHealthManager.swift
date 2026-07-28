import Foundation

/// Owns runtime health-monitoring state and periodic maintenance logic.
/// iOS-simplified version: no EGL, no dynamic bitrate (AVAssetWriter limitation).
class RuntimeHealthManager {

    private static let healthSampleIntervalMs: Int64 = 5000
    private static let periodicMaintenanceIntervalMs: Int64 = 30_000
    private static let bufferAuditIntervalMs: Int64 = 120_000
    private static let driftLogIntervalMs: Int64 = 60_000
    private static let sizeWarningThresholdBytes: Int64 = 2 * 1024 * 1024 * 1024
    private static let fpsDriftThreshold: Double = 1.0
    private static let memoryGrowthWarnRatio: Double = 0.10
    private static let storageWarningThresholdMb: Double = 500.0
    private static let storageCriticalThresholdMb: Double = 100.0

    private let metrics: RecordingMetricsState
    private let healthMonitor: RecordingHealthMonitor
    private let performanceOptimizer: PerformanceOptimizer
    private let performanceMonitor: PerformanceMonitor
    private let datasetWriter: DatasetWriter
    private let writerQueue: DispatchQueue?
    private let recordError: (String, Error?) -> Void

    // Device metrics cache (refreshed every ~500ms, written per-frame at ~15Hz)
    private static let deviceMetricsRefreshIntervalMs: Int64 = 500
    private var lastDeviceMetricsRefreshMs: Int64 = 0
    struct CachedDeviceMetrics {
        var batteryLevel: Float = 0.0
        var batteryState: UInt8 = 0
        var batteryStateStr: String = "unknown"
        var cpuUsage: Float = 0.0
        var memoryUsedMb: Double = 0.0
        var memoryAvailableMb: Double = 0.0
        var thermalState: UInt8 = 0
        var thermalStateStr: String = "unavailable"
    }
    var cachedDeviceMetrics = CachedDeviceMetrics()

    // Health sampling state
    var lastHealthSampleElapsedMs: Int64 = 0
    var lastHealthSampleArkitFrames: Int = 0
    var lastHealthSampleEncodedFrames: Int = 0
    var thermalThrottlingDetected: Bool = false
    var fpsDriftDetected: Bool = false
    var memoryGrowthDetected: Bool = false
    var maxMemoryUsageMb: Double = 0.0
    var leakSuspected: Bool = false
    var lastMemoryUsageMb: Double?
    var baselineMemoryUsageMb: Double?

    // Thermal state
    var lastThermalStatusCode: Int?
    var lastThermalStatusLabel: String = "unavailable"
    var thermalStatusLabel: String = "unavailable"
    var thermalStateTransitionCount: Int = 0

    // Storage monitoring
    var lowStorageWarningFired: Bool = false
    var storageCriticalFired: Bool = false
    var onLowStorageWarning: (() -> Void)?
    var onStorageCritical: (() -> Void)?

    // Periodic maintenance state
    var lastMaintenanceElapsedMs: Int64 = 0
    var maintenanceCycleCount: Int = 0
    var lastBufferAuditElapsedMs: Int64 = 0
    var lastDriftLogElapsedMs: Int64 = 0

    init(
        metrics: RecordingMetricsState,
        healthMonitor: RecordingHealthMonitor,
        performanceOptimizer: PerformanceOptimizer,
        performanceMonitor: PerformanceMonitor,
        datasetWriter: DatasetWriter,
        writerQueue: DispatchQueue? = nil,
        recordError: @escaping (String, Error?) -> Void
    ) {
        self.metrics = metrics
        self.healthMonitor = healthMonitor
        self.performanceOptimizer = performanceOptimizer
        self.performanceMonitor = performanceMonitor
        self.datasetWriter = datasetWriter
        self.writerQueue = writerQueue
        self.recordError = recordError
    }

    func reset() {
        lastHealthSampleElapsedMs = 0
        lastHealthSampleArkitFrames = 0
        lastHealthSampleEncodedFrames = 0
        thermalThrottlingDetected = false
        fpsDriftDetected = false
        memoryGrowthDetected = false
        maxMemoryUsageMb = 0.0
        leakSuspected = false
        lastMemoryUsageMb = nil
        baselineMemoryUsageMb = nil
        lastThermalStatusCode = nil
        lastThermalStatusLabel = "unavailable"
        thermalStatusLabel = "unavailable"
        thermalStateTransitionCount = 0
        lastMaintenanceElapsedMs = 0
        maintenanceCycleCount = 0
        lastBufferAuditElapsedMs = 0
        lastDriftLogElapsedMs = 0
        lowStorageWarningFired = false
        storageCriticalFired = false
        performanceMonitor.reset()
    }

    func maybeSampleRuntimeHealth() {
        let nowMs = Int64(ProcessInfo.processInfo.systemUptime * 1000)

        if lastHealthSampleElapsedMs == 0 {
            _ = performanceMonitor.sampleHealth()
            lastHealthSampleElapsedMs = nowMs
            lastHealthSampleArkitFrames = metrics.arkitFrameCount
            lastHealthSampleEncodedFrames = metrics.encodedVideoFrameCount
            let memMb = healthMonitor.currentMemoryUsageMb()
            baselineMemoryUsageMb = memMb
            maxMemoryUsageMb = memMb
            lastMemoryUsageMb = memMb
            return
        }

        let elapsedMs = nowMs - lastHealthSampleElapsedMs
        if elapsedMs < Self.healthSampleIntervalMs { return }

        _ = performanceMonitor.sampleHealth()

        let arkitDelta = metrics.arkitFrameCount - lastHealthSampleArkitFrames
        let encodedDelta = metrics.encodedVideoFrameCount - lastHealthSampleEncodedFrames
        let elapsedSec = Double(elapsedMs) / 1000.0
        let encodedFpsWindow = elapsedSec > 0 ? Double(encodedDelta) / elapsedSec : 0.0

        fpsDriftDetected = abs(encodedFpsWindow - Double(metrics.targetEncodeFps)) > Self.fpsDriftThreshold

        let memoryUsageMb = healthMonitor.currentMemoryUsageMb()
        if memoryUsageMb > maxMemoryUsageMb { maxMemoryUsageMb = memoryUsageMb }

        lastMemoryUsageMb = memoryUsageMb

        // Thermal check
        let thermalStatus = healthMonitor.readThermalStatus(thermalBitrateClampStatus: 2)
        thermalStatusLabel = thermalStatus.label
        if thermalStatus.throttling {
            thermalThrottlingDetected = true
        }

        let transition = healthMonitor.updateThermalTransition(
            nowMs: nowMs,
            thermalStatus: thermalStatus,
            lastThermalStatusCode: lastThermalStatusCode,
            lastThermalStatusLabel: lastThermalStatusLabel,
            thermalStateTransitionCount: thermalStateTransitionCount,
            logSystem: { [weak self] msg in self?.datasetWriter.logSystem(message: msg) }
        )
        lastThermalStatusCode = transition.lastThermalStatusCode
        lastThermalStatusLabel = transition.lastThermalStatusLabel ?? "unavailable"
        thermalStateTransitionCount = transition.thermalStateTransitionCount

        // Storage check
        let storageMb = healthMonitor.availableStorageMb()
        if storageMb >= 0 {
            if !storageCriticalFired && storageMb < Self.storageCriticalThresholdMb {
                storageCriticalFired = true
                lowStorageWarningFired = true
                onStorageCritical?()
            } else if !lowStorageWarningFired && storageMb < Self.storageWarningThresholdMb {
                lowStorageWarningFired = true
                onLowStorageWarning?()
            }
        }

        let arkitFpsWindow = elapsedSec > 0 ? Double(arkitDelta) / elapsedSec : 0.0
        datasetWriter.logSystem(message:
            "Health sample: arkit_fps_window=\(String(format: "%.2f", arkitFpsWindow)) encoded_fps_window=\(String(format: "%.2f", encodedFpsWindow)) memory_mb=\(String(format: "%.2f", memoryUsageMb)) thermal=\(thermalStatus.label) storage_mb=\(String(format: "%.0f", storageMb))"
        )

        lastHealthSampleElapsedMs = nowMs
        lastHealthSampleArkitFrames = metrics.arkitFrameCount
        lastHealthSampleEncodedFrames = metrics.encodedVideoFrameCount
    }

    func maybeRunPeriodicMaintenance() {
        let nowMs = Int64(ProcessInfo.processInfo.systemUptime * 1000)
        if lastMaintenanceElapsedMs == 0 {
            lastMaintenanceElapsedMs = nowMs
            lastBufferAuditElapsedMs = nowMs
            lastDriftLogElapsedMs = nowMs
            return
        }
        if nowMs - lastMaintenanceElapsedMs < Self.periodicMaintenanceIntervalMs { return }

        maintenanceCycleCount += 1

        let memoryNowMb = healthMonitor.currentMemoryUsageMb()
        if memoryNowMb > maxMemoryUsageMb { maxMemoryUsageMb = memoryNowMb }

        datasetWriter.logSystem(message:
            "Maintenance cycle #\(maintenanceCycleCount): memory_mb=\(String(format: "%.2f", memoryNowMb))"
        )

        lastMaintenanceElapsedMs = nowMs
    }

    func maybeLogSizeProjection(recordingStartTimeMs: Int64, estimateProjectionBytes: (Int64) -> Int64) {
        if metrics.sizeWarningLogged { return }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let elapsedMs = nowMs - recordingStartTimeMs
        if elapsedMs < 2000 { return }
        let projectedBytes = estimateProjectionBytes(elapsedMs)
        if projectedBytes > Self.sizeWarningThresholdBytes {
            datasetWriter.logSystem(message:
                "WARN: projected dataset size exceeds threshold. projected=\(projectedBytes) threshold=\(Self.sizeWarningThresholdBytes)"
            )
            metrics.sizeWarningLogged = true
        }
    }

    // MARK: - Device Metrics (per-frame write + periodic cache refresh)

    /// Refreshes the cached device metrics if the refresh interval has elapsed.
    /// Called from the processing queue; the cached values are read from the writer queue.
    func maybeRefreshDeviceMetricsCache() {
        let nowMs = Int64(ProcessInfo.processInfo.systemUptime * 1000)
        if nowMs - lastDeviceMetricsRefreshMs < Self.deviceMetricsRefreshIntervalMs && lastDeviceMetricsRefreshMs != 0 {
            return
        }
        let battery = healthMonitor.readBatteryInfo()
        let cpuUsage = healthMonitor.readCpuUsage()
        let memoryMb = healthMonitor.currentMemoryUsageMb()
        let availableMemMb = healthMonitor.availableMemoryMb()
        let thermalStatus = healthMonitor.readThermalStatus(thermalBitrateClampStatus: 2)
        cachedDeviceMetrics.batteryLevel = battery.level
        cachedDeviceMetrics.batteryState = battery.state
        cachedDeviceMetrics.batteryStateStr = battery.stateStr
        cachedDeviceMetrics.cpuUsage = cpuUsage
        cachedDeviceMetrics.memoryUsedMb = memoryMb
        cachedDeviceMetrics.memoryAvailableMb = availableMemMb
        cachedDeviceMetrics.thermalState = UInt8(thermalStatus.statusCode)
        cachedDeviceMetrics.thermalStateStr = thermalStatus.label
        lastDeviceMetricsRefreshMs = nowMs
    }

    /// Writes the cached device metrics to MCAP. Must be called on the writerQueue.
    func writeDeviceMetricsForFrame(timestampNs: Int64) {
        let m = cachedDeviceMetrics
        datasetWriter.writeDeviceMetrics(
            timestampNs: timestampNs,
            batteryLevel: m.batteryLevel,
            batteryState: m.batteryState,
            batteryStateStr: m.batteryStateStr,
            cpuUsage: m.cpuUsage,
            memoryUsedMb: m.memoryUsedMb,
            memoryAvailableMb: m.memoryAvailableMb,
            thermalState: m.thermalState,
            thermalStateStr: m.thermalStateStr
        )
    }
}
