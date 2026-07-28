import Foundation

#if canImport(Flutter)
import Flutter

/// Handles Flutter MethodChannel calls for SecurityScopedURLHelper operations.
/// Equivalent to Android's ContentUriMethodChannelHandler.
public class SecurityScopedURLMethodChannelHandler: NSObject {
    
    private static let channelName = "content_uri_helper"
    
    private let securityScopedURLHelper: SecurityScopedURLHelperImpl
    private let methodChannel: FlutterMethodChannel
    
    init(binaryMessenger: FlutterBinaryMessenger) {
        self.securityScopedURLHelper = SecurityScopedURLHelperImpl()
        self.methodChannel = FlutterMethodChannel(
            name: SecurityScopedURLMethodChannelHandler.channelName,
            binaryMessenger: binaryMessenger
        )
        
        super.init()
        
        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call: call, result: result)
        }
    }
    
    private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "takePersistentPermission":
            handleTakePersistentPermission(call: call, result: result)
        case "releasePersistentPermission":
            handleReleasePersistentPermission(call: call, result: result)
        case "hasPermission":
            handleHasPermission(call: call, result: result)
        case "getFileSize":
            handleGetFileSize(call: call, result: result)
        case "getFileMetadata":
            handleGetFileMetadata(call: call, result: result)
        case "readChunk":
            handleReadChunk(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Method Handlers
    
    private func handleTakePersistentPermission(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let urlString = args["uri"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "URI is null", details: nil))
            return
        }
        
        let success = securityScopedURLHelper.saveSecurityScopedBookmark(urlString: urlString)
        result(success)
    }
    
    private func handleReleasePersistentPermission(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let urlString = args["uri"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "URI is null", details: nil))
            return
        }
        
        let success = securityScopedURLHelper.releaseSecurityScopedBookmark(urlString: urlString)
        result(success)
    }
    
    private func handleHasPermission(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let urlString = args["uri"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "URI is null", details: nil))
            return
        }
        
        let hasBookmark = securityScopedURLHelper.hasBookmark(urlString: urlString)
        result(hasBookmark)
    }
    
    private func handleGetFileSize(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let urlString = args["uri"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "URI is null", details: nil))
            return
        }
        
        let size = securityScopedURLHelper.getFileSize(urlString: urlString)
        result(size)
    }
    
    private func handleGetFileMetadata(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let urlString = args["uri"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "URI is null", details: nil))
            return
        }
        
        let metadata = securityScopedURLHelper.getFileMetadata(urlString: urlString)
        result(metadata)
    }
    
    private func handleReadChunk(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let urlString = args["uri"] as? String,
              let offset = args["offset"] as? NSNumber,
              let length = args["length"] as? NSNumber else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
            return
        }
        
        // Run on background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let chunk = self?.securityScopedURLHelper.readChunk(
                urlString: urlString,
                offset: offset.int64Value,
                length: length.intValue
            )
            
            DispatchQueue.main.async {
                if let data = chunk {
                    result(FlutterStandardTypedData(bytes: data))
                } else {
                    result(nil)
                }
            }
        }
    }
}

#else
public class SecurityScopedURLMethodChannelHandler: NSObject {}
#endif
