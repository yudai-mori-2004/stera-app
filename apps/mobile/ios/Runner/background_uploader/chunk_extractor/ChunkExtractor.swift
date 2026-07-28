import CryptoKit
import Foundation

struct ExtractedChunk {
    let fileURL: URL
    let md5Base64: String
}

enum ChunkExtractError: Error {
    case shortRead
}

protocol ChunkExtractor {
    init(tempDir: URL, bufferSize: Int)

    func extract(sessionId: String, partNumber: Int, sourceURL: URL, offset: Int64, length: Int)
        throws -> ExtractedChunk
}

class ChunkExtractorImpl: ChunkExtractor {
    private let tempDir: URL
    private let bufferSize: Int

    required init(tempDir: URL, bufferSize: Int = 2 * 1024 * 1024) {
        self.tempDir = tempDir
        self.bufferSize = bufferSize
        try? FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
    }

    /// Extract `[offset, offset+length)` of `sourceURL` into a temp file, hashing
    /// as we copy. The caller holds security-scoped access to `sourceURL` for the
    /// session, so this should not start/stop access per chunk.
    func extract(
        sessionId: String,
        partNumber: Int,
        sourceURL: URL,
        offset: Int64,
        length: Int
    ) throws -> ExtractedChunk {
        let src = try FileHandle(forReadingFrom: sourceURL)
        defer { try? src.close() }
        try src.seek(toOffset: UInt64(offset))

        let tmpURL = tempDir.appendingPathComponent("\(sessionId)_p\(partNumber).tmp")
        FileManager.default.createFile(
            atPath: tmpURL.path,
            contents: nil,
            attributes: [
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ]
        )
        let dst = try FileHandle(forWritingTo: tmpURL)
        defer { try? dst.close() }

        var hasher = Insecure.MD5()
        var remaining = length
        while remaining > 0 {
            let n = min(bufferSize, remaining)
            guard let data = try src.read(upToCount: n), !data.isEmpty else {
                throw ChunkExtractError.shortRead
            }
            hasher.update(data: data)
            try dst.write(contentsOf: data)
            remaining -= data.count
        }

        let md5Base64 = Data(hasher.finalize()).base64EncodedString()
        return ExtractedChunk(fileURL: tmpURL, md5Base64: md5Base64)
    }
}
