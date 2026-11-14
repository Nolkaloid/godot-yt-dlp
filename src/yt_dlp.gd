extends Node

signal setup_completed
signal _update_completed

enum Video { MP4, WEBM, MOV, MKV, OGV, AUTO }
enum Audio { AAC, FLAC, MP3, M4A, OPUS, VORBIS, WAV, AUTO }

const AndroidBridge = preload("res://addons/godot-yt-dlp/src/android_bridge.gd")
const Downloader = preload("res://addons/godot-yt-dlp/src/downloader.gd")
const yt_dlp_sources: Dictionary = {
	"Linux": "https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/yt-dlp_linux",
	"Windows": "https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/yt-dlp.exe",
	"macOS": "https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/yt-dlp_macos",
}
const ffmpeg_sources: Dictionary = {
	"Windows": "https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
}

var _downloader: Downloader
var _thread: Thread = Thread.new()
var _is_setup: bool = false
var _setup_in_progress: bool = false
const SETUP_TIMEOUT_MS := 120000


func ensure_ready() -> bool:
	if OS.has_feature("web"):
		return false
	if is_setup() and is_runtime_available():
		return true
	# Subscribe first because an already-ready Android backend can finish inline.
	var state := {"finished": false}
	var on_finished := func(): state["finished"] = true
	setup_completed.connect(on_finished)
	setup()
	var deadline := Time.get_ticks_msec() + SETUP_TIMEOUT_MS
	while not state["finished"] and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	setup_completed.disconnect(on_finished)
	return is_setup() and is_runtime_available()


func is_setup() -> bool:
	return _is_setup


func is_runtime_available() -> bool:
	if AndroidBridge.is_android_platform():
		return AndroidBridge.is_ready()

	var executable_name: String = "yt-dlp.exe" if OS.get_name() == "Windows" else "yt-dlp"
	return FileAccess.file_exists("user://%s" % executable_name)


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


func extract_info(url: String) -> Dictionary:
	if not _is_setup:
		push_error(self, "Not set up.")
		return {}

	if AndroidBridge.is_android_platform():
		return AndroidBridge.extract_info(url)

	var executable_name: String = "yt-dlp.exe" if OS.get_name() == "Windows" else "yt-dlp"
	var executable_path := "user://%s" % executable_name
	if not FileAccess.file_exists(executable_path):
		return {}

	var output: Array = []
	var arguments := PackedStringArray([
		"--print-json",
		"--no-playlist",
		"--no-warnings",
		"--skip-download",
		"--socket-timeout", "10",
		"--retries", "1",
		"--extractor-retries", "1",
		url
	])
	OS.execute(ProjectSettings.globalize_path(executable_path), arguments, output)

	if output.is_empty():
		return {}

	for line in str(output[0]).split("\n", false):
		var parsed = JSON.parse_string(line)
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed

	return {}


func setup() -> void:
	if is_setup() and is_runtime_available():
		setup_completed.emit()
		return
	if _setup_in_progress:
		return
	_setup_in_progress = true
	_downloader = Downloader.new()
	if AndroidBridge.is_android_platform():
		if AndroidBridge.is_ready():
			_finish_android_setup(true, "")
			return
		var error := _thread.start(_setup_android_backend)
		if error != OK:
			_finish_android_setup.call_deferred(false, "Failed to start setup thread: %s" % error_string(error))
		return

	var executable_name: String = "yt-dlp.exe" if OS.get_name() == "Windows" else "yt-dlp"

	if not FileAccess.file_exists("user://%s" % executable_name):
		_downloader.download(yt_dlp_sources[OS.get_name()], "user://%s" % executable_name)
		await _downloader.download_completed
	else:
		_thread.start(_update_yt_dlp.bind(executable_name))
		await _update_completed
		await (Engine.get_main_loop() as SceneTree).process_frame
		_thread.wait_to_finish()

	if OS.get_name() == "Windows":
		await _setup_ffmpeg()
	else:
		OS.execute("chmod", PackedStringArray(["+x", OS.get_user_data_dir() + "/yt-dlp"]))

	_is_setup = true
	_setup_in_progress = false
	setup_completed.emit()


func _setup_android_backend() -> void:
	var succeeded := AndroidBridge.setup_backend()
	_finish_android_setup.call_deferred(succeeded, AndroidBridge.get_last_error())


func _finish_android_setup(succeeded: bool, error_message: String) -> void:
	if _thread.is_started():
		_thread.wait_to_finish()
	_is_setup = succeeded
	_setup_in_progress = false
	if not succeeded:
		push_error(self, error_message)
	setup_completed.emit()


func _cleanup_ffmpeg_release_archive(ffmpeg_release_filepath: String) -> void:
	if not FileAccess.file_exists(ffmpeg_release_filepath):
		return

	var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(ffmpeg_release_filepath))
	if remove_error != OK and FileAccess.file_exists(ffmpeg_release_filepath):
		push_warning("Couldn't remove temporary ffmpeg archive: %s" % error_string(remove_error))


func _setup_ffmpeg() -> void:
	const ffmpeg_release_filepath = "user://ffmpeg-release.zip"
	if FileAccess.file_exists("user://ffmpeg.exe") and FileAccess.file_exists("user://ffprobe.exe"):
		_cleanup_ffmpeg_release_archive(ffmpeg_release_filepath)
		return

	_downloader.download(ffmpeg_sources["Windows"], ffmpeg_release_filepath)
	await _downloader.download_completed

	var zip_reader := ZIPReader.new()
	var error := zip_reader.open(ffmpeg_release_filepath)
	if error != OK:
		push_error(self, "Couldn't extract ffmpeg release: %s" % error_string(error))
		_cleanup_ffmpeg_release_archive(ffmpeg_release_filepath)
		return

	var filepaths := Array(zip_reader.get_files()).filter(
		func(s): return s.contains("bin/ffmpeg") or s.contains("bin/ffprobe")
	)

	for f in filepaths:
		var filename := f.get_file() as String
		var file := FileAccess.open("user://%s" % filename, FileAccess.WRITE)
		file.store_buffer(zip_reader.read_file(f))
		file.close()

	zip_reader.close()
	_cleanup_ffmpeg_release_archive(ffmpeg_release_filepath)


func _update_yt_dlp(filename: String) -> void:
	# Keep existing installations on the nightly channel as well as downloading
	# nightly for first-time setup. This is needed for current extractor fixes.
	OS.execute("%s/%s" % [OS.get_user_data_dir(), filename], ["--update-to", "nightly"])
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
		FAILED,
		INTERRUPTED,
	}

	var _status: Status = Status.READY
	var _thread: Thread = null

	var _url: String
	var _destination: String = "user://"
	var _file_name: String = "godot_yt_dlp_download_"
	var _convert_to_audio: bool = false
	var _video_format: Video = Video.WEBM
	var _audio_format: Audio = Audio.MP3
	var _requested_video_format: Video = Video.WEBM
	var _requested_audio_format: Audio = Audio.MP3
	var _format_fallback_enabled := true
	var _is_stopped: bool = false
	var _stop_mutex := Mutex.new()
	var _error_message := ""

	func _is_youtube_url(url: String) -> bool:
		var address := url.to_lower()
		if not address.contains("://"):
			address = "https://" + address
		var host := address.get_slice("://", 1).get_slice("/", 0).get_slice("?", 0).get_slice("#", 0).get_slice(":", 0)
		return host == "youtube.com" or host.ends_with(".youtube.com") or host == "youtu.be" or host.ends_with(".youtu.be")

	func _is_direct_webm_url(url: String) -> bool:
		var path := url.to_lower().split("?", false)[0].split("#", false)[0]
		return not _is_youtube_url(url) and path.ends_with(".webm")

	func _vp9_encoder_arguments(ffmpeg_path: String) -> String:
		var encoder_output: Array = []
		var encoder_code := OS.execute(ffmpeg_path, PackedStringArray(["-hide_banner", "-encoders"]), encoder_output)
		var encoder_list := "\n".join(encoder_output)
		var candidates: Array[String] = []
		if encoder_code == 0:
			if encoder_list.contains("vp9_nvenc"):
				candidates.append("-c:v vp9_nvenc -cq 32")
			if encoder_list.contains("vp9_amf"):
				candidates.append("-c:v vp9_amf -quality speed -qp_i 32 -qp_p 32")
			if OS.get_name() == "Windows" and encoder_list.contains("vp9_qsv"):
				candidates.append("-c:v vp9_qsv -global_quality 32")
			if OS.get_name() == "Linux" and encoder_list.contains("vp9_vaapi") and FileAccess.file_exists("/dev/dri/renderD128"):
				candidates.append("-vaapi_device /dev/dri/renderD128 -vf format=nv12,hwupload -c:v vp9_vaapi -global_quality 32")

		for candidate in candidates:
			var test_output: Array = []
			var test_args := PackedStringArray([
				"-hide_banner", "-loglevel", "error", "-f", "lavfi",
				"-i", "color=c=black:s=64x64:r=1", "-frames:v", "1"
			])
			test_args.append_array(candidate.split(" "))
			test_args.append_array(["-an", "-f", "webm", ("NUL" if OS.get_name() == "Windows" else "/dev/null")])
			if OS.execute(ffmpeg_path, test_args, test_output) == 0:
				return candidate

		# libvpx remains the portable fallback. Row-based threading improves CPU use.
		return "-c:v libvpx-vp9 -b:v 0 -crf 32 -deadline good -cpu-used 6 -row-mt 1 -threads 0"

	func _init(url: String):
		_url = url
		_file_name += Time.get_datetime_string_from_system().replace(":", "-")

	func set_destination(destination: String) -> Download:
		_destination = destination
		return self

	func set_file_name(file_name: String) -> Download:
		_file_name = file_name
		return self

	func set_video_format(format: Video) -> Download:
		_requested_video_format = format
		return self

	func convert_to_audio(format: Audio) -> Download:
		_requested_audio_format = format
		_convert_to_audio = true
		return self

	func set_format_fallback_enabled(enabled: bool) -> Download:
		_format_fallback_enabled = enabled
		return self

	func get_output_extension() -> String:
		if _status == Status.READY:
			_select_output_formats()
		if _convert_to_audio:
			return _audio_extension(_audio_format)
		return _video_extension(_video_format)

	func _video_extension(format: Video) -> String:
		return "" if format == Video.AUTO else (Video.keys()[format] as String).to_lower()

	func _audio_extension(format: Audio) -> String:
		if format == Audio.AUTO:
			return ""
		return "ogg" if format == Audio.VORBIS else (Audio.keys()[format] as String).to_lower()

	func _supported_extensions(resource_type: String) -> PackedStringArray:
		var extensions := ResourceLoader.get_recognized_extensions_for_type(resource_type)
		# Some extensions register loaders for their concrete stream type only.
		for stream_type in ClassDB.get_inheriters_from_class(resource_type):
			extensions.append_array(ResourceLoader.get_recognized_extensions_for_type(stream_type))
		if resource_type == "AudioStream":
			# Core audio loaders advertise imported resource suffixes (.mp3str,
			# .oggvorbisstr, .sample); their stream classes decode the raw formats.
			var native_audio := {"AudioStreamMP3": "mp3", "AudioStreamOggVorbis": "ogg", "AudioStreamWAV": "wav"}
			for stream_type in native_audio:
				if ClassDB.can_instantiate(stream_type):
					extensions.append(native_audio[stream_type])
		return extensions

	func _select_output_formats() -> void:
		_video_format = _requested_video_format
		_audio_format = _requested_audio_format
		if not _format_fallback_enabled:
			return
		# Ask registered resource loaders rather than depend on a custom engine
		# or extension class. Snapshot this on the main thread before starting.
		var video_extensions := _supported_extensions("VideoStream")
		var audio_extensions := _supported_extensions("AudioStream")
		if _video_format == Video.AUTO:
			_video_format = Video.OGV
			for candidate in [Video.WEBM, Video.MP4, Video.MKV, Video.MOV]:
				if _video_extension(candidate) in video_extensions:
					_video_format = candidate
					break
		elif not _video_extension(_video_format) in video_extensions:
			_video_format = Video.OGV
		if _audio_format == Audio.AUTO:
			_audio_format = Audio.MP3
			for candidate in [Audio.OPUS, Audio.M4A, Audio.AAC, Audio.FLAC]:
				if _audio_extension(candidate) in audio_extensions:
					_audio_format = candidate
					break
		elif not _audio_extension(_audio_format) in audio_extensions:
			_audio_format = Audio.MP3

	func get_status() -> Status:
		return _status

	func get_error_message() -> String:
		return _error_message

	func stop() -> void:
		if _status in [Status.READY, Status.DOWNLOADING]:
			_stop_mutex.lock()
			_is_stopped = true
			_stop_mutex.unlock()
			_status = Status.INTERRUPTED

	func _should_stop() -> bool:
		_stop_mutex.lock()
		var stopped := _is_stopped
		_stop_mutex.unlock()
		return stopped

	func start() -> Download:
		if _status == Status.INTERRUPTED:
			return self
		if not _status == Status.READY:
			push_error(self, "Download previously started.")
			return self

		_select_output_formats()
		_status = Status.DOWNLOADING
		_destination = ProjectSettings.globalize_path(_destination)
		_thread = Thread.new()
		reference()
		var thread_error := _thread.start(_execute_on_thread)
		if thread_error != OK:
			_status = Status.FAILED
			call_deferred("_thread_finished", false, "Failed to start download thread: %s" % error_string(thread_error))
			return self
		return self

	func _execute_on_thread() -> void:
		if _should_stop():
			self._thread_finished.call_deferred()
			return
		if AndroidBridge.is_android_platform():
			var android_ok := false
			if _convert_to_audio:
				var android_format: String = "auto" if _audio_format == Audio.AUTO else (Audio.keys()[_audio_format] as String).to_lower()
				android_ok = AndroidBridge.download_audio(
					_url,
					_destination,
					_file_name,
					android_format
				)
			else:
				var android_video_format: String = (Video.keys()[_video_format] as String).to_lower()
				android_ok = AndroidBridge.download_video(
					_url,
					_destination,
					_file_name,
					android_video_format
				)
			if not android_ok:
				self._thread_finished.call_deferred(false, AndroidBridge.get_last_error())
				return
			self._thread_finished.call_deferred(true, "")
			return

		var executable: String = (
			OS.get_user_data_dir() + ("/yt-dlp.exe" if OS.get_name() == "Windows" else "/yt-dlp")
		)

		var options_and_arguments: Array = []

		match OS.get_name():
			"Windows":
				options_and_arguments.append_array(["--ffmpeg-location", ProjectSettings.globalize_path("user://ffmpeg.exe")])
			"Linux", "macOS":
				var output := []
				OS.execute("which", ["ffmpeg"], output)
				var ffmpeg_path = output[0].get_base_dir()
				options_and_arguments.append_array(["--ffmpeg-location", ffmpeg_path])

		if _convert_to_audio:
			if _audio_format == Audio.AUTO:
				# Extract the best native audio stream while allowing yt-dlp to
				# choose a supported output format instead of leaving audio in WebM.
				options_and_arguments.append_array(["--format", "bestaudio/best", "-x", "--audio-format", "best"])
			else:
				var audio_format_name: String = (Audio.keys()[_audio_format] as String).to_lower()
				options_and_arguments.append_array(["-x", "--audio-format", audio_format_name])
		else:
			var video_format_name: String
			match _video_format:
				Video.AUTO:
					video_format_name = "bestvideo+bestaudio/best"
				Video.WEBM:
					video_format_name = "bestvideo[vcodec^=vp9]+bestaudio[acodec^=opus]/bestvideo[vcodec^=vp8]+bestaudio[acodec^=opus]/bestvideo+bestaudio" if _is_youtube_url(_url) else "bestvideo+bestaudio/best"
				Video.MP4:
					video_format_name = "bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best"
				Video.MOV, Video.MKV, Video.OGV:
					video_format_name = "bestvideo+bestaudio/best"
			options_and_arguments.append_array(["--format", video_format_name])

		var file_path := _destination.path_join(_file_name + ".%(ext)s")

		if not _convert_to_audio and _video_format == Video.OGV:
			options_and_arguments.append_array([
				"--recode-video", "ogg", "--postprocessor-args",
				"VideoConvertor+ffmpeg_o:-c:v libtheora -q:v 6 -g:v 64 -pix_fmt yuv420p -c:a libvorbis -q:a 6 -ac 2",
				"--no-keep-video"
			])
		elif not _convert_to_audio and _video_format in [Video.MP4, Video.MOV]:
			options_and_arguments.append_array([
				"--recode-video", _video_extension(_video_format), "--postprocessor-args",
				"VideoConvertor+ffmpeg_o:-c:v libx264 -crf 23 -pix_fmt yuv420p -c:a aac",
				"--no-keep-video"
			])
		elif not _convert_to_audio and _video_format == Video.MKV:
			options_and_arguments.append_array(["--remux-video", "mkv"])
		elif not _convert_to_audio and _video_format == Video.WEBM:
			if _is_youtube_url(_url):
				var vp9_encoder_args := _vp9_encoder_arguments(ProjectSettings.globalize_path("user://ffmpeg.exe") if OS.get_name() == "Windows" else "ffmpeg")
				options_and_arguments.append_array([
					"--recode-video", "webm",
					"--postprocessor-args",
					"VideoConvertor+ffmpeg_o:%s -c:a libopus" % vp9_encoder_args,
					"--no-keep-video"
				])
			elif not _is_direct_webm_url(_url):
				var vp9_encoder_args := _vp9_encoder_arguments(ProjectSettings.globalize_path("user://ffmpeg.exe") if OS.get_name() == "Windows" else "ffmpeg")
				options_and_arguments.append_array([
					"--recode-video", "webm",
					"--postprocessor-args",
					"VideoConvertor+ffmpeg_o:%s -c:a libopus" % vp9_encoder_args,
					"--no-keep-video"
				])
		options_and_arguments.append_array(["--no-continue", "-o", file_path, _url])

		if _should_stop():
			self._thread_finished.call_deferred()
			return
		var output: Array = []
		var exit_code := -1
		for attempt in 2:
			if _should_stop():
				break
			output.clear()
			exit_code = OS.execute(executable, PackedStringArray(options_and_arguments), output, true)
			if exit_code == 0 or attempt == 1 or not _is_youtube_url(_url) or not "\n".join(output).contains("HTTP Error 403"):
				break
			# Re-extract once for fresh media URLs, preserving format and destination.
			OS.delay_msec(500)
		if exit_code == 0 and not _convert_to_audio and _video_format == Video.OGV:
			# yt-dlp uses .ogg for this container; Godot imports video as .ogv.
			var rename_error := DirAccess.rename_absolute(_destination.path_join(_file_name + ".ogg"), _destination.path_join(_file_name + ".ogv"))
			if rename_error != OK:
				self._thread_finished.call_deferred(false, "Cannot publish the converted Ogg Theora video: %s" % error_string(rename_error))
				return
		self._thread_finished.call_deferred(exit_code == 0, "" if exit_code == 0 else "yt-dlp exited with code %d. %s" % [exit_code, _failure_detail("\n".join(output))])

	func _failure_detail(output: String) -> String:
		var detail := ""
		for line in output.split("\n", false):
			var clean := line.strip_edges()
			if clean.begins_with("ERROR:") or (detail.is_empty() and not clean.is_empty()):
				detail = clean
		return detail.left(2048)

	func _thread_finished(succeeded := true, error_message := ""):
		if _thread != null and _thread.is_started():
			_thread.wait_to_finish()
		if _should_stop():
			_status = Status.INTERRUPTED
			unreference()
			return
		_status = Status.COMPLETED if succeeded else Status.FAILED
		_error_message = ""
		if not succeeded:
			_error_message = _failure_detail(str(error_message))
			if _error_message.is_empty():
				_error_message = "Download failed."
			push_error(self, _error_message)
		self.download_completed.emit()
		unreference()


class Search extends RefCounted:
	signal search_completed

	enum Status {
		IDLE,
		SEARCHING,
		COMPLETED,
		FAILED,
		INTERRUPTED,
	}

	var _status: Status = Status.IDLE
	var _thread: Thread = null

	var _search_term: String
	var _number_of_results: int
	var _results: Array[Dictionary] = []
	var _is_stopped: bool = false

	func _init(search_term: String, number_of_results: int = 1):
		if number_of_results < 1:
			push_error(self, "Number of desired results must be at least 1.")
			self._status = Status.FAILED
			search_completed.emit()
			return

		self._search_term = search_term
		self._number_of_results = number_of_results

		_thread = Thread.new()
		_status = Status.SEARCHING
		reference()
		var error := _thread.start(_execute_on_thread)
		if error != OK:
			_thread_finished.call_deferred([], false, "Failed to start search thread: %s" % error_string(error))

	func get_status() -> Status:
		return _status

	func get_results() -> Array[Dictionary]:
		if _status != Status.COMPLETED:
			push_error(self, "Cannot get results before search completion.")
			return []

		return self._results.duplicate(true)

	func stop() -> void:
		if _status == Status.SEARCHING:
			_is_stopped = true
			_status = Status.INTERRUPTED

	func _execute_on_thread() -> void:
		if AndroidBridge.is_android_platform():
			var results := AndroidBridge.search(_search_term, _number_of_results)
			var error_message := AndroidBridge.get_last_error()
			self._thread_finished.call_deferred(results, error_message.is_empty(), error_message)
			return

		var executable: String = (
			OS.get_user_data_dir() + ("/yt-dlp.exe" if OS.get_name() == "Windows" else "/yt-dlp")
		)

		var query: String = 'ytsearch{expected_results}:{search_term}'.format(
			{"expected_results": self._number_of_results, "search_term": self._search_term}
		)

		var output: Array[String] = []
		var exit_code := OS.execute(executable, ["--print-json", "--flat-playlist", query], output)
		var results: Array[Dictionary] = []
		for chunk in output:
			for line in chunk.split("\n", false):
				var parsed = JSON.parse_string(line)
				if not parsed is Dictionary:
					self._thread_finished.call_deferred([], false, "Invalid search response.")
					return
				results.append(parsed)
		self._thread_finished.call_deferred(results, exit_code == 0, "Search failed." if exit_code != 0 else "")

	func _thread_finished(results: Array, succeeded: bool, error_message: String):
		if _thread != null and _thread.is_started():
			_thread.wait_to_finish()
		if _is_stopped:
			_status = Status.INTERRUPTED
		else:
			_results.assign(results)
			_status = Status.COMPLETED if succeeded else Status.FAILED
			if not succeeded:
				push_error(self, error_message)
			self.search_completed.emit()
		unreference()
