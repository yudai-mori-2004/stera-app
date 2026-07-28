import Flutter
import UIKit

@objc class SceneDelegate: FlutterSceneDelegate {

    private var securityScopedURLHandler: SecurityScopedURLMethodChannelHandler?
    private var videoMetadataHandler: VideoMetadataMethodChannelHandler?
    private var iosWindowedUploaderHandler: IosWindowedUploaderMethodChannelHandler?
    private var videoPickerHandler: VideoPickerMethodChannelHandler?

    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        super.scene(scene, willConnectTo: session, options: connectionOptions)

        guard let controller = window?.rootViewController as? FlutterViewController else {
            print("❌ SceneDelegate: rootViewController is not FlutterViewController")
            return
        }

        GeneratedPluginRegistrant.register(with: controller)

        let messenger = controller.binaryMessenger

        securityScopedURLHandler = SecurityScopedURLMethodChannelHandler(
            binaryMessenger: messenger
        )

        videoMetadataHandler = VideoMetadataMethodChannelHandler(
            binaryMessenger: messenger
        )

        // Phase 2 windowed engine — the sole upload engine (the legacy
        // IosBackgroundUploader triad was removed).
        iosWindowedUploaderHandler = IosWindowedUploaderMethodChannelHandler(
            binaryMessenger: messenger
        )

        // The AR recorder lives in the stera_recorder plugin and registers
        // itself through GeneratedPluginRegistrant above.

        videoPickerHandler = VideoPickerMethodChannelHandler(
            viewController: controller,
            binaryMessenger: messenger
        )

        print("✅ SceneDelegate: handlers registered")
    }
}
