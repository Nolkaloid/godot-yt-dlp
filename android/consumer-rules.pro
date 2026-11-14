# Godot discovers the plugin and its methods through reflection.
-keep class org.godotengine.ytdlp.plugin.GodotYtDlpAndroidPlugin { *; }
# JavaClassWrapper also discovers the static bridge through reflection.
-keep class org.godotengine.ytdlp.bridge.YtDlpBridge { *; }
