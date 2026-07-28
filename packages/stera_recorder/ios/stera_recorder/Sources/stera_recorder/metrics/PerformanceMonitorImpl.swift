import Foundation

class PerformanceMonitorImpl: PerformanceMonitor {
    private var maxMemoryUsageMb: Double = 0.0
    private var lastMemoryUsageMb: Double = 0.0
    private var lastSampleElapsedMs: Int64 = 0

    func reset() {
        maxMemoryUsageMb = 0.0
        lastMemoryUsageMb = 0.0
        lastSampleElapsedMs = 0
    }

    func sampleHealth() -> [String: Any] {
        let memoryMb = currentMemoryUsageMb()
        if memoryMb > maxMemoryUsageMb {
            maxMemoryUsageMb = memoryMb
        }
        let nowMs = Int64(ProcessInfo.processInfo.systemUptime * 1000)
        let elapsedMs = lastSampleElapsedMs == 0 ? 0 : nowMs - lastSampleElapsedMs
        let previous = lastMemoryUsageMb
        lastMemoryUsageMb = memoryMb
        lastSampleElapsedMs = nowMs

        return [
            "memoryMb": memoryMb,
            "maxMemoryMb": maxMemoryUsageMb,
            "elapsedMsSinceLastSample": elapsedMs,
            "deltaMemoryMb": memoryMb - previous
        ]
    }

    func getPerformanceMetrics() -> [String: Any] {
        return [
            "maxMemoryUsageMb": maxMemoryUsageMb,
            "lastMemoryUsageMb": lastMemoryUsageMb
        ]
    }

    private func currentMemoryUsageMb() -> Double {
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
}
