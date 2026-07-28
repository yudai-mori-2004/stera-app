import Darwin
import Foundation
import UIKit

/// Monitors thermal state and memory usage on iOS.
/// Uses ProcessInfo.thermalState instead of Android's PowerManager.
class RecordingHealthMonitor {

    struct ThermalSnapshot {
        let label: String
        let statusCode: Int
        let throttling: Bool
        let shouldClampBitrate: Bool
    }

    struct ThermalTransitionResult {
        let transitioned: Bool
        let lastThermalStatusCode: Int?
        let lastThermalStatusLabel: String?
        let thermalStateTransitionCount: Int
    }

    func currentMemoryUsageMb() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            return Double(info.resident_size) / (1024.0 * 1024.0)
        }
        return 0.0
    }

    func readThermalStatus(thermalBitrateClampStatus: Int) -> ThermalSnapshot {
        let thermalState = ProcessInfo.processInfo.thermalState
        let statusCode: Int
        let label: String
        let throttling: Bool

        switch thermalState {
        case .nominal:
            statusCode = 0
            label = "nominal"
            throttling = false
        case .fair:
            statusCode = 1
            label = "fair"
            throttling = false
        case .serious:
            statusCode = 2
            label = "serious"
            throttling = true
        case .critical:
            statusCode = 3
            label = "critical"
            throttling = true
        @unknown default:
            statusCode = 0
            label = "unknown"
            throttling = false
        }

        return ThermalSnapshot(
            label: label,
            statusCode: statusCode,
            throttling: throttling,
            shouldClampBitrate: statusCode >= thermalBitrateClampStatus
        )
    }

    func updateThermalTransition(
        nowMs: Int64,
        thermalStatus: ThermalSnapshot,
        lastThermalStatusCode: Int?,
        lastThermalStatusLabel: String?,
        thermalStateTransitionCount: Int,
        logSystem: (String) -> Void
    ) -> ThermalTransitionResult {
        if lastThermalStatusCode != thermalStatus.statusCode || lastThermalStatusLabel != thermalStatus.label {
            let count = thermalStateTransitionCount + 1
            logSystem("Thermal transition @\(nowMs)ms: \(lastThermalStatusLabel ?? "nil") -> \(thermalStatus.label)")
            return ThermalTransitionResult(
                transitioned: true,
                lastThermalStatusCode: thermalStatus.statusCode,
                lastThermalStatusLabel: thermalStatus.label,
                thermalStateTransitionCount: count
            )
        }
        return ThermalTransitionResult(
            transitioned: false,
            lastThermalStatusCode: lastThermalStatusCode,
            lastThermalStatusLabel: lastThermalStatusLabel,
            thermalStateTransitionCount: thermalStateTransitionCount
        )
    }

    // MARK: - Battery

    func readBatteryInfo() -> (level: Float, state: UInt8, stateStr: String) {
        let device = UIDevice.current
        if !device.isBatteryMonitoringEnabled {
            device.isBatteryMonitoringEnabled = true
        }
        let level = device.batteryLevel < 0 ? 0.0 : device.batteryLevel * 100.0
        let state: UInt8
        let stateStr: String
        switch device.batteryState {
        case .unknown:
            state = 0
            stateStr = "unknown"
        case .unplugged:
            state = 1
            stateStr = "unplugged"
        case .charging:
            state = 2
            stateStr = "charging"
        case .full:
            state = 3
            stateStr = "full"
        @unknown default:
            state = 0
            stateStr = "unknown"
        }
        return (level: level, state: state, stateStr: stateStr)
    }

    // MARK: - CPU Usage

    func readCpuUsage() -> Float {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t(0)
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        guard result == KERN_SUCCESS, let threads = threadList else { return 0.0 }

        var totalUsage: Double = 0.0
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            // THREAD_BASIC_INFO_COUNT is a C macro not always visible to Swift; derive like mach/task_info.h
            var infoCount = mach_msg_type_number_t(
                MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size
            )
            let kr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            if kr == KERN_SUCCESS && (info.flags & TH_FLAGS_IDLE) == 0 {
                totalUsage += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }

        let size = vm_size_t(MemoryLayout<thread_t>.size) * vm_size_t(threadCount)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), size)

        return Float(totalUsage)
    }

    // MARK: - Available Memory

    func availableMemoryMb() -> Double {
        return Double(os_proc_available_memory()) / (1024.0 * 1024.0)
    }

    // MARK: - Available Storage

    func availableStorageMb() -> Double {
        let homeDir = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? homeDir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            return Double(capacity) / (1024.0 * 1024.0)
        }
        return -1.0
    }
}
