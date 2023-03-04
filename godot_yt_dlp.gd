@tool
extends EditorPlugin


const AUTOLOAD_NAME = "YtDlp"


func _enter_tree():
	add_autoload_singleton(AUTOLOAD_NAME, "res://addons/godot-yt-dlp/src/yt_dlp.gd")


func _exit_tree():
	remove_autoload_singleton(AUTOLOAD_NAME)
