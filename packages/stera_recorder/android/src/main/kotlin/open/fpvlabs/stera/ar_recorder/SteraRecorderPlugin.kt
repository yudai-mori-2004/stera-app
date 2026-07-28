package open.fpvlabs.stera.ar_recorder

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.view.TextureRegistry

/**
 * Registers the AR recorder method channel.
 *
 * The recorder needs an [android.app.Activity] (ARCore sessions are bound to
 * one) plus the engine's texture registry, so the handler is built on activity
 * attach and disposed on detach — the same window the host app's
 * `MainActivity.configureFlutterEngine`/`onDestroy` used before this moved into
 * a plugin.
 */
class SteraRecorderPlugin : FlutterPlugin, ActivityAware {

    private var binaryMessenger: BinaryMessenger? = null
    private var textureRegistry: TextureRegistry? = null
    private var handler: ArRecorderMethodChannelHandler? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        binaryMessenger = binding.binaryMessenger
        textureRegistry = binding.textureRegistry
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        disposeHandler()
        binaryMessenger = null
        textureRegistry = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        val messenger = binaryMessenger ?: return
        val textures = textureRegistry ?: return
        handler = ArRecorderMethodChannelHandler(binding.activity, messenger, textures)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        disposeHandler()
    }

    override fun onDetachedFromActivity() {
        disposeHandler()
    }

    private fun disposeHandler() {
        handler?.let {
            println("🧹 SteraRecorderPlugin: Disposing AR recorder")
            it.dispose()
        }
        handler = null
    }
}
