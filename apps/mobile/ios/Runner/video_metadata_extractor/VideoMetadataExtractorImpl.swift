import Foundation
import AVFoundation
import UIKit
import Photos

/// Implementation of VideoMetadataExtractor for video operations on iOS.
/// Uses AVFoundation for thumbnail extraction and metadata retrieval.
class VideoMetadataExtractorImpl: VideoMetadataExtractor {
    
    /// Directory for storing thumbnails
    private lazy var thumbnailsDirectory: URL = {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let thumbnailsPath = documentsPath.appendingPathComponent("thumbnails", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: thumbnailsPath.path) {
            try? FileManager.default.createDirectory(at: thumbnailsPath, withIntermediateDirectories: true)
        }
        
        return thumbnailsPath
    }()
    
    // MARK: - Thumbnail Extraction
    
    func extractThumbnail(urlString: String, timeMs: Int64) -> String? {
        guard let url = resolveURL(urlString: urlString) else {
            print("❌ Invalid URL string: \(urlString)")
            return nil
        }
        
        // Start security-scoped access if needed
        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            
            // Maximum dimension for thumbnails
            generator.maximumSize = CGSize(width: 512, height: 512)
            
            // Convert milliseconds to CMTime
            let time = CMTime(value: CMTimeValue(timeMs), timescale: 1000)
            
            // Generate the image
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            let uiImage = UIImage(cgImage: cgImage)
            
            // Generate unique filename based on URL hash
            let fileName = "\(urlString.hashValue).jpg"
            let thumbnailPath = thumbnailsDirectory.appendingPathComponent(fileName)
            
            // Save as JPEG
            if let jpegData = uiImage.jpegData(compressionQuality: 0.85) {
                try jpegData.write(to: thumbnailPath)
                print("✅ Thumbnail extracted: \(thumbnailPath.path)")
                return thumbnailPath.path
            }
        } catch {
            print("❌ Error extracting thumbnail: \(error)")
        }
        
        return nil
    }
    
    // MARK: - Video Duration
    
    func getVideoDuration(urlString: String) -> Int? {
        guard let url = resolveURL(urlString: urlString) else {
            print("❌ Invalid URL string: \(urlString)")
            return nil
        }
        
        // Start security-scoped access if needed
        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        let asset = AVURLAsset(url: url)
        let duration = asset.duration
        
        // Convert CMTime to seconds
        let durationSeconds = CMTimeGetSeconds(duration)
        
        guard durationSeconds.isFinite else {
            print("❌ Invalid duration for: \(urlString)")
            return nil
        }
        
        let seconds = Int(durationSeconds)
        print("✅ Video duration: \(seconds) seconds")
        return seconds
    }
    
    // MARK: - Video Metadata
    
    func getVideoMetadata(urlString: String) -> [String: Any?] {
        var metadata: [String: Any?] = [:]
        
        guard let url = resolveURL(urlString: urlString) else {
            print("❌ Invalid URL string for metadata: \(urlString)")
            return metadata
        }
        
        // Start security-scoped access if needed
        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        var resolvedName: String?
        var mimeType: String?
        var size: Int64?
        
        // Attempt to resolve the original filename from Photos if possible.
        let assets = PHAsset.fetchAssets(withALAssetURLs: [url], options: nil)
        if let asset = assets.firstObject {
            let resources = PHAssetResource.assetResources(for: asset)
            if let original = resources.first?.originalFilename {
                resolvedName = original
            }
        }
        
        // Fallback to file resource values.
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .nameKey,
                .fileSizeKey,
                .contentTypeKey
            ])
            
            if resolvedName == nil {
                resolvedName = resourceValues.name
            }
            
            if let fileSize = resourceValues.fileSize {
                size = Int64(fileSize)
            }
            
            if let contentType = resourceValues.contentType {
                mimeType = contentType.preferredMIMEType
            }
        } catch {
            print("❌ Error getting file metadata: \(error)")
        }
        
        metadata["name"] = resolvedName
        metadata["size"] = size
        metadata["mimeType"] = mimeType
        
        return metadata
    }
    
    // MARK: - Open in Viewer
    
    func openVideoInViewer(urlString: String) -> Bool {
        guard let url = resolveURL(urlString: urlString) else {
            print("❌ Invalid URL string: \(urlString)")
            return false
        }
        
        // Start security-scoped access
        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        
        // For opening in external app, we need to keep access or copy to a shareable location
        // The simplest approach is to use UIActivityViewController or QLPreviewController
        
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                if shouldStopAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
                return
            }
            
            // Use UIActivityViewController for sharing/opening
            let activityVC = UIActivityViewController(
                activityItems: [url],
                applicationActivities: nil
            )
            
            // On iPad, we need to set the source for the popover
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = rootViewController.view
                popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX,
                                          y: rootViewController.view.bounds.midY,
                                          width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            activityVC.completionWithItemsHandler = { _, _, _, _ in
                if shouldStopAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            rootViewController.present(activityVC, animated: true)
        }
        
        print("✅ Opened video viewer for: \(urlString)")
        return true
    }
    
    // MARK: - Save to Gallery
    
    func saveVideoToGallery(sourcePath: String) -> Bool {
        let sourceURL: URL
        
        if sourcePath.hasPrefix("file://") {
            guard let url = URL(string: sourcePath) else {
                print("❌ Invalid file URL: \(sourcePath)")
                return false
            }
            sourceURL = url
        } else {
            sourceURL = URL(fileURLWithPath: sourcePath)
        }
        
        // Start security-scoped access if needed
        let shouldStopAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            print("❌ Source file does not exist: \(sourcePath)")
            return false
        }
        
        var success = false
        let semaphore = DispatchSemaphore(value: 0)
        
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: sourceURL)
        }) { completed, error in
            if completed {
                print("✅ Video saved to gallery: \(sourcePath)")
                success = true
            } else if let error = error {
                print("❌ Error saving video to gallery: \(error)")
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        return success
    }
    
    // MARK: - Private Helpers
    
    private func resolveURL(urlString: String) -> URL? {
        // Handle custom appsupport:// scheme for relative paths
        // Format: appsupport://uploads/filename.mp4 -> {AppSupport}/uploads/filename.mp4
        if urlString.hasPrefix("appsupport://") {
            let relativePath = String(urlString.dropFirst("appsupport://".count))
            do {
                let appSupportDir = try FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: false
                )
                let resolvedURL = appSupportDir.appendingPathComponent(relativePath)
                print("🔍 VideoMetadataExtractor: Resolved appsupport:// to \(resolvedURL.path)")
                return resolvedURL
            } catch {
                print("❌ VideoMetadataExtractor: Failed to resolve appsupport:// URL: \(error)")
                return nil
            }
        }
        
        // First, try to resolve from a stored bookmark
        // Use same prefix as SecurityScopedURLHelperImpl for consistency
        let bookmarkKey = "io.rootlens.app.bookmark.\(urlString.hashValue)"
        if let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                
                if isStale {
                    print("⚠️ Bookmark is stale for: \(urlString)")
                    // Try to recreate bookmark
                    if url.startAccessingSecurityScopedResource() {
                        if let newBookmarkData = try? url.bookmarkData(
                            options: .minimalBookmark,
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        ) {
                            UserDefaults.standard.set(newBookmarkData, forKey: bookmarkKey)
                        }
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                print("✅ Resolved URL from bookmark: \(url.lastPathComponent)")
                return url
            } catch {
                print("⚠️ Failed to resolve bookmark: \(error)")
            }
        }
        
        // Handle file:// URLs
        if urlString.hasPrefix("file://") {
            return URL(string: urlString)
        }
        
        // Handle regular file paths
        if urlString.hasPrefix("/") {
            return URL(fileURLWithPath: urlString)
        }
        
        // Handle other URL schemes
        return URL(string: urlString)
    }
}
