import Foundation
import Flutter
import UIKit

/// Handles Flutter MethodChannel calls for VideoPicker operations.
/// Equivalent to Android's VideoPickerMethodChannelHandler.
class VideoPickerMethodChannelHandler: NSObject {
    
    private static let channelName = "custom_document_picker"
    
    private var videoPicker: VideoPicker
    private let methodChannel: FlutterMethodChannel
    private var pendingResult: FlutterResult?
    private var isPickingMultiple: Bool = false
    
    init(viewController: UIViewController, binaryMessenger: FlutterBinaryMessenger) {
        self.videoPicker = VideoPickerImpl(viewController: viewController)
        self.methodChannel = FlutterMethodChannel(
            name: VideoPickerMethodChannelHandler.channelName,
            binaryMessenger: binaryMessenger
        )
        
        super.init()
        
        // Set self as delegate
        videoPicker.delegate = self
        
        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call: call, result: result)
        }
    }
    
    private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "pickVideos":
            handlePickVideos(result: result)
        case "pickSingleVideo":
            handlePickSingleVideo(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Method Handlers
    
    private func handlePickVideos(result: @escaping FlutterResult) {
        if pendingResult != nil {
            result(FlutterError(code: "ALREADY_ACTIVE", message: "A picker is already active", details: nil))
            return
        }
        
        pendingResult = result
        isPickingMultiple = true
        videoPicker.pickVideos()
    }
    
    private func handlePickSingleVideo(result: @escaping FlutterResult) {
        if pendingResult != nil {
            result(FlutterError(code: "ALREADY_ACTIVE", message: "A picker is already active", details: nil))
            return
        }
        
        pendingResult = result
        isPickingMultiple = false
        videoPicker.pickSingleVideo()
    }
}

// MARK: - VideoPickerDelegate

extension VideoPickerMethodChannelHandler: VideoPickerDelegate {
    
    func didPickVideos(_ urls: [String]?) {
        pendingResult?(urls)
        pendingResult = nil
    }
    
    func didPickSingleVideo(_ url: String?) {
        pendingResult?(url)
        pendingResult = nil
    }
}
