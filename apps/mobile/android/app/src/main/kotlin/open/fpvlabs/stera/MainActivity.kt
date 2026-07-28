package open.fpvlabs.stera

import android.content.Intent
import open.fpvlabs.stera.content_uri_helper.ContentUriMethodChannelHandler
import open.fpvlabs.stera.gallery_manager.GalleryManagerMethodChannelHandler
import open.fpvlabs.stera.video_metadata_extractor.VideoMetadataMethodChannelHandler
import open.fpvlabs.stera.video_picker.VideoPickerMethodChannelHandler
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var videoPickerHandler: VideoPickerMethodChannelHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val binaryMessenger = flutterEngine.dartExecutor.binaryMessenger

        // Content URI Helper Channel
        ContentUriMethodChannelHandler(applicationContext, binaryMessenger)

        // Video Metadata Extractor Channel
        VideoMetadataMethodChannelHandler(applicationContext, binaryMessenger)

        // Video Picker Channel
        videoPickerHandler = VideoPickerMethodChannelHandler(this, binaryMessenger)

        // Gallery Manager Channel
        GalleryManagerMethodChannelHandler(applicationContext, binaryMessenger)

        // AR Recorder lives in the stera_recorder plugin and registers itself
        // through GeneratedPluginRegistrant.
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        videoPickerHandler?.onActivityResult(requestCode, resultCode, data)
    }
}
