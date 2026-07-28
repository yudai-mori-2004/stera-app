import Foundation

protocol PerformanceMonitor {
    func reset()
    func sampleHealth() -> [String: Any]
    func getPerformanceMetrics() -> [String: Any]
}
