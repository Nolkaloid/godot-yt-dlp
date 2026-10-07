@tool
extends EditorPlugin


const AUTOLOAD_NAME = "YtDlp"

var export_plugin: AndroidExportPlugin = null


func _enter_tree():
	add_autoload_singleton(AUTOLOAD_NAME, "res://addons/godot-yt-dlp/src/yt_dlp.gd")
	export_plugin = AndroidExportPlugin.new()
	add_export_plugin(export_plugin)


func _exit_tree():
	if export_plugin != null:
		remove_export_plugin(export_plugin)
		export_plugin = null
	remove_autoload_singleton(AUTOLOAD_NAME)


class AndroidExportPlugin extends EditorExportPlugin:
	var _plugin_name = "godot-yt-dlp"

	func _get_addon_dir_relative_to_addons() -> String:
		var script_path := ""
		var script_variant = get_script()
		if script_variant != null:
			script_path = str(script_variant.resource_path)
		if script_path == "":
			return _plugin_name

		var script_dir := script_path.get_base_dir()
		var addons_prefix := "res://addons/"
		if script_dir.begins_with(addons_prefix):
			return script_dir.substr(addons_prefix.length())
		return _plugin_name

	func _get_debug_aar_relative_path() -> String:
		return "%s/bin/godot-ytdlp-android-debug.aar" % _get_addon_dir_relative_to_addons()

	func _get_release_aar_relative_path() -> String:
		return "%s/bin/godot-ytdlp-android-release.aar" % _get_addon_dir_relative_to_addons()

	func _get_debug_aar_check_path() -> String:
		return "res://addons/%s" % _get_debug_aar_relative_path()

	func _get_release_aar_check_path() -> String:
		return "res://addons/%s" % _get_release_aar_relative_path()

	func _get_android_aar_relative_path(debug: bool) -> String:
		return _get_debug_aar_relative_path() if debug else _get_release_aar_relative_path()

	func _get_android_aar_check_path(debug: bool) -> String:
		return _get_debug_aar_check_path() if debug else _get_release_aar_check_path()

	func _supports_platform(platform):
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(platform, debug):
		var aar_relative := _get_android_aar_relative_path(debug)
		var aar_check := _get_android_aar_check_path(debug)
		if not FileAccess.file_exists(aar_check):
			var build_label := "debug" if debug else "release"
			push_warning("godot-yt-dlp Android %s AAR is missing at %s" % [build_label, aar_check])
		return PackedStringArray([aar_relative])

	func _get_android_dependencies(platform, debug):
		return PackedStringArray([
			"io.github.junkfood02.youtubedl-android:library:0.18.1",
			"io.github.junkfood02.youtubedl-android:ffmpeg:0.18.1"
		])

	func _get_android_dependencies_maven_repos(platform, debug):
		return PackedStringArray([
			"https://repo1.maven.org/maven2"
		])

	func _get_name():
		return _plugin_name