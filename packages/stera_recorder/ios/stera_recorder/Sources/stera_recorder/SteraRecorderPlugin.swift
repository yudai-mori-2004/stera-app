import Flutter

/// Registers the AR recorder method channel.
///
/// The handler needs the engine's texture registry for the camera preview, both
/// of which the registrar hands over. It is retained for the lifetime of the
/// engine — the same lifetime it had when the host app's `SceneDelegate`
/// constructed it directly.
public class SteraRecorderPlugin: NSObject, FlutterPlugin {

    private static var handler: ArRecorderMethodChannelHandler?

    public static func register(with registrar: FlutterPluginRegistrar) {
        handler = ArRecorderMethodChannelHandler(
            binaryMessenger: registrar.messenger(),
            textureRegistry: registrar.textures()
        )
    }
}
