# ARCore ProGuard Rules
# These rules ensure ARCore classes are not removed or obfuscated by R8

# Keep all ARCore classes
-keep class com.google.ar.** { *; }
-keep class com.google.ar.core.** { *; }

# Keep ARCore native libraries
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep EGL/GL classes used by ARCore
-keep class android.opengl.** { *; }

# Keep MediaCodec classes used for video encoding
-keep class android.media.MediaCodec { *; }
-keep class android.media.MediaFormat { *; }
-keep class android.media.MediaMuxer { *; }

# Keep sensor classes
-keep class android.hardware.Sensor** { *; }

# Keep texture/surface classes
-keep class android.graphics.SurfaceTexture { *; }
-keep class android.view.Surface { *; }
-keep class android.view.SurfaceView { *; }
