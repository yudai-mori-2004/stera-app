import Foundation
import Flutter

/// Handles Flutter MethodChannel calls for VideoMetadataExtractor operations.
/// Equivalent to Android's VideoMetadataMethodChannelHandler.
class VideoMetadataMethodChannelHandler: NSObject {
    
    private static let channelName = "video_helper"
    
    private let videoMetadataExtractor: VideoMetadataExtractor
    private let methodChannel: FlutterMethodChannel
    
    init(binaryMessenger: FlutterBinaryMessenger) {
        self.videoMetadataExtractor = VideoMetadataExtractorImpl()
        self.methodChannel = FlutterMethodChannel(
            name: VideoMetadataMethodChannelHandler.channelName,
            binaryMessenger: binaryMessenger
        )
        
        super.init()
        
        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call: call, result: result)
        }
    }
    
    private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "extractThumbnail":
            handleExtractThumbnail(call: call, result: result)
        case "getVideoDuration":
            handleGetVideoDuration(call: call, result: result)
        case "getVideoMetadata":
            handleGetVideoMetadata(call: call, result: result)
        case "openVideoInViewer":
            handleOpenVideoInViewer(call: call, result: result)
        case "saveVideoToGallery":
            handleSaveVideoToGallery(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Method Handlers
    
    private func handleExtractThumbnail(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let urlString = args["uri"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "URI is null", details: nil))
            return
        }
        
        let timeMs = (args["timeMs"] as? NSNumber)?.int64Value ?? 0
        
        // Run on background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let thumbnailPath = self?.videoMetadataExtractor.extractThumbnail(
                urlString: urlString,
                timeMs: timeMs
            )
            
            DispatchQueue.main.async {
                result(thumbnailPath)
            }
        }
    }
    
    private func handleGetVideoDuration(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let urlString = args["uri"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "URI is null", details: nil))
            return
        }
        
        // Run on background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let durationSeconds = self?.videoMetadataExtractor.getVideoDuration(urlString: urlString)
            
            DispatchQueue.main.async {
                result(durationSeconds)
            }
        }
    }
    
    private func handleGetVideoMetadata(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let urlString = args["uri"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "URI is null", details: nil))
            return
        }
        
        // Run on background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let metadata = self?.videoMetadataExtractor.getVideoMetadata(urlString: urlString)
            
            DispatchQueue.main.async {
                result(metadata)
            }
        }
    }
    
    private func handleOpenVideoInViewer(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let urlString = args["uri"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "URI is null", details: nil))
            return
        }
        
        let success = videoMetadataExtractor.openVideoInViewer(urlString: urlString)
        result(success)
    }
    
    private func handleSaveVideoToGallery(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let sourcePath = args["sourcePath"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Source path is null", details: nil))
            return
        }
        
        // Run on background thread as photo library operations can be slow
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = self?.videoMetadataExtractor.saveVideoToGallery(sourcePath: sourcePath) ?? false
            
            DispatchQueue.main.async {
                result(success)
            }
        }
    }
}
