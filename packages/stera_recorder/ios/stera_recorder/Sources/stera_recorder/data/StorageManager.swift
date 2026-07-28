import Foundation

protocol StorageManager {
    func verifyHeadroom(baseDir: URL, durationSeconds: Int64, includeDepth: Bool) -> (Bool, String?)
    func estimateDatasetSize(durationSeconds: Int64, includeDepth: Bool) -> Int64
}
