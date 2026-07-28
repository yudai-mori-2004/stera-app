import Foundation
import UIKit
import Photos
import PhotosUI
import UniformTypeIdentifiers

/// Implementation of VideoPicker using PHPicker to surface the Photos app
/// with videos only. Returns local file URLs for the selected items.
class VideoPickerImpl: NSObject, VideoPicker {
    
    weak var delegate: VideoPickerDelegate?
    
    private weak var viewController: UIViewController?
    private var isPickingMultiple: Bool = false
    
    init(viewController: UIViewController) {
        self.viewController = viewController
        super.init()
    }
    
    func pickVideos() {
        isPickingMultiple = true
        presentPhotoPicker(selectionLimit: 0) // 0 = no limit
    }
    
    func pickSingleVideo() {
        isPickingMultiple = false
        presentPhotoPicker(selectionLimit: 1)
    }
    
    private func presentPhotoPicker(selectionLimit: Int) {
        guard let viewController = viewController else {
            print("❌ No view controller available for photo picker")
            if isPickingMultiple {
                delegate?.didPickVideos(nil)
            } else {
                delegate?.didPickSingleVideo(nil)
            }
            return
        }
        
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .videos
        configuration.selectionLimit = selectionLimit
        configuration.preferredAssetRepresentationMode = .current
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        
        viewController.present(picker, animated: true)
    }
    
    /// Attempts to retrieve the original filename for a picked asset.
    /// Falls back to the item provider's suggested name.
    private func originalFileName(for result: PHPickerResult) -> String? {
        // Try Photos asset resources for the original filename.
        if let assetId = result.assetIdentifier {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
            if let asset = assets.firstObject {
                let resources = PHAssetResource.assetResources(for: asset)
                if let original = resources.first?.originalFilename {
                    return original
                }
            }
        }
        
        // Fallback to the provider's suggested name.
        if let suggested = result.itemProvider.suggestedName {
            return suggested
        }
        
        return nil
    }
}

// MARK: - PHPickerViewControllerDelegate

extension VideoPickerImpl: PHPickerViewControllerDelegate {
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard !results.isEmpty else {
            picker.dismiss(animated: true) { [weak self] in
                guard let self = self else { return }
                if self.isPickingMultiple {
                    self.delegate?.didPickVideos(nil)
                } else {
                    self.delegate?.didPickSingleVideo(nil)
                }
            }
            return
        }
        
        // Collect URLs after loading providers; copy to temp for local access.
        let group = DispatchGroup()
        var collectedURLs: [String] = []
        let urlAccessQueue = DispatchQueue(label: "open.fpvlabs.stera.videoPicker.urlAccessQueue")
        
        for result in results {
            let provider = result.itemProvider
            guard provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) else {
                continue
            }
            
            // Resolve the best-guess original filename up-front (before load).
            let originalName = originalFileName(for: result)
            
            group.enter()
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                defer { group.leave() }
                
                if let error = error {
                    print("⚠️ Failed to load video: \(error)")
                    return
                }
                
                guard let sourceURL = url else {
                    print("⚠️ No URL returned for picked video")
                    return
                }
                
                // Copy to app support so file survives app termination.
                let appSupportDir: URL
                do {
                    appSupportDir = try FileManager.default.url(
                        for: .applicationSupportDirectory,
                        in: .userDomainMask,
                        appropriateFor: nil,
                        create: true
                    )
                } catch {
                    print("⚠️ Could not access Application Support directory: \(error)")
                    return
                }
                let uploadsDir = appSupportDir.appendingPathComponent("uploads", isDirectory: true)
                if !FileManager.default.fileExists(atPath: uploadsDir.path) {
                    do {
                        try FileManager.default.createDirectory(
                            at: uploadsDir,
                            withIntermediateDirectories: true
                        )
                    } catch {
                        print("⚠️ Could not create uploads directory: \(error)")
                        return
                    }
                }
                
                // Use the original filename when possible so UI can display it.
                let resolvedExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
                let filename: String
                if let originalName = originalName {
                    // Ensure we keep an extension even if missing on the original name.
                    if originalName.contains(".") {
                        filename = originalName
                    } else {
                        filename = "\(originalName).\(resolvedExtension)"
                    }
                } else {
                    filename = "\(UUID().uuidString).\(resolvedExtension)"
                }
                
                let destinationURL = uploadsDir.appendingPathComponent(filename)
                
                do {
                    // Remove existing file if any to avoid collisions.
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                    
                    // Return a custom scheme URL with relative path.
                    // This survives app container UUID changes on simulator/reinstall.
                    // Format: appsupport://uploads/filename.mp4
                    let relativePath = "uploads/\(filename)"
                    let customURL = "appsupport://\(relativePath)"
                    
                    urlAccessQueue.sync {
                        collectedURLs.append(customURL)
                    }
                } catch {
                    print("⚠️ Could not copy picked video: \(error)")
                }
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            picker.dismiss(animated: true)
            
            if self.isPickingMultiple {
                self.delegate?.didPickVideos(collectedURLs.isEmpty ? nil : collectedURLs)
            } else {
                self.delegate?.didPickSingleVideo(collectedURLs.first)
            }
        }
    }
}
