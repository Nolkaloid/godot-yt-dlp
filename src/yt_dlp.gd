extends Node

signal setup_completed
signal _update_completed

enum Video { MP4, WEBM }
enum Audio { AAC, FLAC, MP3, M4A, OPUS, VORBIS, WAV }

const Downloader = preload("res://addons/godot-yt-dlp/src/downloader.gd")
const yt_dlp_sources: Dictionary = {
	"Linux": "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp",
	"Windows": "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe",
	"macOS": "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos",
}
const ffmpeg_sources: Dictionary = {
	"ffmpeg": "https://github.com/Nolkaloid/godot-youtube-dl/releases/latest/download/ffmpeg.exe",
	"ffprobe": "https://github.com/Nolkaloid/godot-youtube-dl/releases/latest/download/ffprobe.exe",
}

var _downloader: Downloader
var _thread: Thread = Thread.new()
var _is_setup: bool = false


func is_setup() -> bool:
	return _is_setup


func download(url: String) -> Download:
	if not _is_setup:
		push_error(self, "Not set up.")
		return null

	return Download.new(url)


func search(search_term: String, number_of_results: int) -> Search:
	if not _is_setup:
		push_error(self, "Not set up.")
		return null

	return Search.new(search_term, number_of_results)


func setup() -> void:
	_downloader = Downloader.new()
	var executable_name: String = "yt-dlp.exe" if OS.get_name() == "Windows" else "yt-dlp"

	if not FileAccess.file_exists("user://%s" % executable_name):
		_downloader.download(yt_dlp_sources[OS.get_name()], "user://%s" % executable_name)
		await _downloader.download_completed
	else:
		_thread.start(_update_yt_dlp.bind(executable_name))
		await _update_completed
		# Wait for the next idle frame to join thread
		await (Engine.get_main_loop() as SceneTree).process_frame
		_thread.wait_to_finish()

	if OS.get_name() == "Windows":
		await _setup_ffmpeg()
	else:
		OS.execute("chmod", PackedStringArray(["+x", OS.get_user_data_dir() + "/yt-dlp"]))

	_is_setup = true
	setup_completed.emit()


func _setup_ffmpeg() -> void:
	if not FileAccess.file_exists("user://ffmpeg.exe"):
		_downloader.download(ffmpeg_sources["ffmpeg"], "user://ffmpeg.exe")
		await _downloader.download_completed

	if not FileAccess.file_exists("user://ffprobe.exe"):
		_downloader.download(ffmpeg_sources["ffprobe"], "user://ffprobe.exe")
		await _downloader.download_completed


func _update_yt_dlp(filename: String) -> void:
	OS.execute("%s/%s" % [OS.get_user_data_dir(), filename], ["--update"])
	_thread_finished.call_deferred(_update_completed)


func _thread_finished(name: Signal) -> void:
	if name != null:
		name.emit()


class Download extends RefCounted:
	signal download_completed

	enum Status {
		READY,
		DOWNLOADING,
		COMPLETED,
	}

	var _status: Status = Status.READY
	var _thread: Thread = null

	# Fields
	var _url: String
	var _destination: String = "user://"
	var _file_name: String = "godot_yt_dlp_download_"
	var _convert_to_audio: bool = false
	var _video_format: Video = Video.WEBM
	var _audio_format: Audio = Audio.MP3

	func _init(url: String):
		_url = url
		_file_name += Time.get_datetime_string_from_system()

	func set_destination(destination: String) -> Download:
		_destination = destination
		return self

	func set_file_name(file_name: String) -> Download:
		_file_name = file_name
		return self

	func set_video_format(format: Video) -> Download:
		_video_format = format
		return self

	func convert_to_audio(format: Audio) -> Download:
		_audio_format = format
		_convert_to_audio = true
		return self

	func get_status() -> Status:
		return _status

	func start() -> Download:
		if not _status == Status.READY:
			push_error(self, "Download previously started.")
			return self

		_status = Status.DOWNLOADING

		_destination = ProjectSettings.globalize_path(_destination)
		_thread = Thread.new()
		_thread.start(_execute_on_thread)
		reference()
		return self

	func _execute_on_thread() -> void:
		var executable: String = (
			OS.get_user_data_dir() + ("/yt-dlp.exe" if OS.get_name() == "Windows" else "/yt-dlp")
		)

		var options_and_arguments: Array = []

		if _convert_to_audio:
			var format: String = (Audio.keys()[_audio_format] as String).to_lower()
			options_and_arguments.append_array(["-x", "--audio-format", format])
		else:
			var format: String

			match _video_format:
				Video.WEBM:
					format = "bestvideo[ext=webm]+bestaudio"
				Video.MP4:
					format = "bestvideo[ext=mp4]+m4a"

			options_and_arguments.append_array(["--format", format])

		var file_path: String = (
			"{destination}{file_name}.%(ext)s"
			. format(
				{
					"destination": _destination,
					"file_name": _file_name,
				}
			)
		)

		options_and_arguments.append_array(["--no-continue", "-o", file_path, _url])

		var output: Array = []
		OS.execute(executable, PackedStringArray(options_and_arguments), output)

		self._thread_finished.call_deferred()

	func _thread_finished():
		_status = Status.COMPLETED
		self.download_completed.emit()
		_thread.wait_to_finish()
		unreference()


class Search extends RefCounted:
	signal search_completed

	enum Status {
		IDLE,
		SEARCHING,
		COMPLETED,
		FAILED,
	}

	var _status: Status = Status.IDLE
	var _thread: Thread = null

	var _search_term: String
	var _number_of_results: int
	var _results: Array[Dictionary] = []

	func _init(search_term: String, number_of_results: int = 1):
		if number_of_results < 1:
			push_error(self, "Number of desired results must be at least 1.")
			self._status = Status.FAILED
			search_completed.emit()
			return

		self._search_term = search_term
		self._number_of_results = number_of_results

		_thread = Thread.new()
		_thread.start(_execute_on_thread)
		reference()

	func get_status() -> Status:
		return _status

	func get_results() -> Array[Dictionary]:
		if _status != Status.COMPLETED:
			push_error(self, "Cannot get results before search completion.")
			return []

		return self._results.duplicate(true)

	func _execute_on_thread() -> void:
		var executable: String = (
			OS.get_user_data_dir() + ("/yt-dlp.exe" if OS.get_name() == "Windows" else "/yt-dlp")
		)

		var query: String = '"ytsearch{expected_results}:{search_term}"'.format(
			{"expected_results": self._number_of_results, "search_term": self._search_term}
		)

		self._status = Status.SEARCHING

		var output: Array[String] = []
		OS.execute(executable, ["--print-json", "--flat-playlist", query], output)

		if output.size() > 0:
			var json_dump: String = output[0]
			self._results.assign(
				(
					Array(json_dump.split("\n", false)).map(
						func(s: String): return JSON.parse_string(s)
					)
					as Array[Dictionary]
				)
			)
			self._status = Status.COMPLETED
		else:
			self._results = []
			push_error(self, "Search failed.")
			self._status = Status.FAILED

		self._thread_finished.call_deferred()

	func _thread_finished():
		self.search_completed.emit()
		_thread.wait_to_finish()
		unreference()
