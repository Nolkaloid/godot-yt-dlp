# Godot discovers the plugin and its methods through reflection.
-keep class org.godotengine.ytdlp.plugin.GodotYtDlpAndroidPlugin { *; }
# The JavaClassWrapper fallback and metadata helpers also use reflection.
-keep class org.godotengine.ytdlp.bridge.YtDlpBridge { *; }
-keepclassmembers class com.yausername.youtubedl_android.mapper.VideoInfo { public *; }
-keepclassmembers class com.yausername.youtubedl_android.YoutubeDLResponse { public *; }
