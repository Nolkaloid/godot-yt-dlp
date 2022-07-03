# warning-ignore-all:return_value_discarded
class_name YtDlp
extends Reference


signal ready
signal download_completed
signal _update_completed

enum Video {MP4, WEBM}
enum Audio {AAC, FLAC, MP3, M4A, OPUS, VORBIS, WAV}

const Downloader = preload("./downloader.gd")
const yt_dlp_sources: Dictionary = {
	"X11": "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp",
	"Windows": "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe",
	"OSX": "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos",
}
const ffmpeg_sources: Dictionary = {
	"ffmpeg": "https://github.com/Nolkaloid/godot-youtube-dl/releases/latest/download/ffmpeg.exe",
	"ffprobe": "https://github.com/Nolkaloid/godot-youtube-dl/releases/latest/download/ffprobe.exe",
}

var _downloader: Downloader
var _thread: Thread = Thread.new()
var _is_ready: bool = false


func _init() -> void:
	print("[yt-dlp] Downloading the latest yt-dlp version")
	
	_downloader = Downloader.new()

	var executable_name: String = "yt-dlp.exe" if OS.get_name() == "Windows" else "yt-dlp"
	
	# Downloads yt-dlp if non-existant otherwise attempt to update it
	if not File.new().file_exists("user://%s" % executable_name):
		_downloader.download(yt_dlp_sources[OS.get_name()], "user://%s" % executable_name)
		yield(_downloader, "download_completed")
	else:
		_thread.start(self, "_update_yt_dlp", [executable_name])
		yield(self, "_update_completed")
		# Waits for the next idle frame to join thread
		yield(Engine.get_main_loop(), "idle_frame") 
		_thread.wait_to_finish()
	
	if OS.get_name() == "Windows":
		yield(_setup_ffmpeg(), "completed")
	else:
		OS.execute("chmod", PoolStringArray(["+x", OS.get_user_data_dir() + "/yt-dlp"]))
	
	print("[yt-dlp] Ready!")
	_is_ready = true
	emit_signal("ready")


func download(url: String, destination: String, file_name: String, convert_to_audio: bool = false,
		video_format: int = Video.WEBM, audio_format: int = Audio.VORBIS) -> void:
	
	if destination[-1] != '/':
		destination += '/'
	
	if _is_ready:
		_is_ready = false
		
		# Increment the reference count while the thread is running
		reference()
		
		_thread.start(self, "_execute_on_thread",
				[url, destination, file_name, convert_to_audio, video_format, audio_format])
	else:
		push_error("[yt-dlp] Not ready yet")


func _setup_ffmpeg() -> void:
	print("[yt-dlp] Downloading ffmpeg and ffprobe")
	var file = File.new()

	if not file.file_exists("user://ffmpeg.exe"):
		_downloader.download(ffmpeg_sources["ffmpeg"], "user://ffmpeg.exe")
		yield(_downloader, "download_completed")
	
	if not file.file_exists("user://ffprobe.exe"):
		_downloader.download(ffmpeg_sources["ffprobe"], "user://ffprobe.exe")
		yield(_downloader, "download_completed")


func _update_yt_dlp(arguments: Array) -> void:
	OS.execute("%s/%s" % [OS.get_user_data_dir(), arguments[0]], ["--update"])
	emit_signal("_update_completed")


func _execute_on_thread(arguments: Array) -> void:
	var url: String = arguments[0]
	var destination: String = arguments[1]
	var file_name: String = arguments[2]
	var convert_to_audio: bool = arguments[3]
	var video_format: int = arguments[4]
	var audio_format: int = arguments[5]
	
	var executable: String = OS.get_user_data_dir() + \
			("/yt-dlp.exe" if OS.get_name() == "Windows" else "/yt-dlp")
	
	var options_and_arguments: Array = []
	
	if convert_to_audio:
		var format: String = (Audio.keys()[audio_format] as String).to_lower()
		options_and_arguments.append_array(["-x", "--audio-format", format])
	else:
		var format: String
		
		match video_format:
			Video.WEBM:
				format = "bestvideo[ext=webm]+bestaudio"
			Video.MP4:
				format = "bestvideo[ext=mp4]+m4a"
		
		options_and_arguments.append_array(["--format", format])
	
	var file_path: String = "{destination}{file_name}.%(ext)s" \
			.format({
				"destination": destination,
				"file_name": file_name,
			})
	
	options_and_arguments.append_array(["--no-continue", "-o", file_path, url])
	
	var output: Array = []
	OS.execute(executable, options_and_arguments, true, output)
	
	call_deferred("_thread_finished")


func _thread_finished():
	emit_signal("download_completed")
	_thread.wait_to_finish()
	_is_ready = true
	
	# Decrement the reference count once the thread is done
	unreference()
