extends Control

const Plugin = preload("res://addons/godot-yt-dlp/src/yt_dlp.gd")
const DOWNLOAD_DIRECTORY := "user://downloads/"

@onready var backend: Plugin = get_node("/root/YtDlp")
@onready var url_input: LineEdit = %URL
@onready var mode: OptionButton = %Mode
@onready var format: OptionButton = %Format
@onready var fallback: CheckBox = %Fallback
@onready var selection: Label = %Selection
@onready var setup_button: Button = %Setup
@onready var download_button: Button = %Download
@onready var play_button: Button = %Play
@onready var stop_button: Button = %Stop
@onready var video_player: VideoStreamPlayer = %Video
@onready var audio_player: AudioStreamPlayer = $Audio
@onready var log_output: RichTextLabel = %Log

var _busy := false
var _job: Plugin.Download
var _last_path := ""
var _last_was_audio := false
var _file_name := ""


func _ready() -> void:
	%Platform.text = "%s · Godot %s" % [OS.get_name(), Engine.get_version_info().string]
	mode.add_item("Video", 0)
	mode.add_item("Audio", 1)
	mode.item_selected.connect(_populate_formats)
	format.item_selected.connect(func(_index): _refresh_selection())
	fallback.toggled.connect(func(_enabled): _refresh_selection())
	url_input.text_changed.connect(func(_text): _sync_controls())
	setup_button.pressed.connect(_setup_runtime)
	download_button.pressed.connect(_start_download)
	play_button.pressed.connect(_play_download)
	stop_button.pressed.connect(_stop_playback)
	backend.setup_completed.connect(_sync_controls)
	audio_player.finished.connect(_sync_controls)
	video_player.finished.connect(_sync_controls)
	_populate_formats()
	_log("Choose Setup runtime, then enter a short public media URL. Downloads stay in this app's user directory.")
	if OS.has_feature("web"):
		_log("Web exports cannot run yt-dlp. Use Windows, Linux, macOS or Android.")
	_sync_controls()


func _populate_formats(_index := 0) -> void:
	format.clear()
	var formats: Dictionary = Plugin.Audio if mode.get_selected_id() == 1 else Plugin.Video
	format.add_item("AUTO", formats["AUTO"])
	for name in formats:
		if name != "AUTO":
			format.add_item(name, formats[name])
	_refresh_selection()


func _configured_download() -> Plugin.Download:
	var request := Plugin.Download.new(url_input.text.strip_edges())
	request.set_format_fallback_enabled(fallback.button_pressed)
	if mode.get_selected_id() == 1:
		request.convert_to_audio(format.get_selected_id())
	else:
		request.set_video_format(format.get_selected_id())
	return request


func _refresh_selection() -> void:
	var extension := _configured_download().get_output_extension()
	selection.text = "Output: .%s" % extension if not extension.is_empty() else "Output: native format, determined after download"
	_sync_controls()


func _sync_controls() -> void:
	setup_button.disabled = _busy or OS.has_feature("web")
	download_button.disabled = _busy or not backend.is_setup() or url_input.text.strip_edges().is_empty()
	mode.disabled = _busy
	format.disabled = _busy
	fallback.disabled = _busy
	url_input.editable = not _busy
	play_button.disabled = _busy or _last_path.is_empty()
	stop_button.disabled = not (audio_player.playing or video_player.is_playing())


func _setup_runtime() -> void:
	_busy = true
	_sync_controls()
	_log("Setting up yt-dlp and checking for updates…")
	var ready: bool = await backend.ensure_ready()
	_busy = false
	_log("Runtime ready." if ready else "Setup failed or the wait expired. Check the Godot console and internet connection. A timeout does not cancel setup.")
	_sync_controls()


func _start_download() -> void:
	var url := url_input.text.strip_edges()
	if not (url.begins_with("https://") or url.begins_with("http://")):
		_log("Enter a complete HTTP or HTTPS media URL.")
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DOWNLOAD_DIRECTORY)) != OK:
		_log("Cannot create the download directory.")
		return
	_stop_playback()
	_last_path = ""
	_last_was_audio = mode.get_selected_id() == 1
	_file_name = "sample_%d" % Time.get_ticks_usec()
	_job = _configured_download()
	_job.set_destination(DOWNLOAD_DIRECTORY).set_file_name(_file_name)
	_job.download_completed.connect(_download_finished, CONNECT_ONE_SHOT)
	_busy = true
	_log("Downloading %s → %s. Conversion may take time." % [format.get_item_text(format.selected), selection.text])
	_sync_controls()
	_job.start()


func _download_finished() -> void:
	_busy = false
	if _job.get_status() != Plugin.Download.Status.COMPLETED:
		_log("Download failed: " + _job.get_error_message())
		_job = null
		_sync_controls()
		return
	var extension := _job.get_output_extension()
	if extension.is_empty():
		# Unrestricted AUTO does not know its extension before downloading.
		var matches := PackedStringArray()
		for name in DirAccess.get_files_at(DOWNLOAD_DIRECTORY):
			if name.begins_with(_file_name + ".") and name.get_extension() not in ["part", "ytdl", "json"]:
				matches.append(DOWNLOAD_DIRECTORY.path_join(name))
		if matches.size() == 1:
			_last_path = matches[0]
	else:
		_last_path = DOWNLOAD_DIRECTORY.path_join(_file_name + "." + extension)
	_job = null
	if _last_path.is_empty() or not FileAccess.file_exists(_last_path):
		_last_path = ""
		_log("Download finished, but the output could not be identified. Check " + ProjectSettings.globalize_path(DOWNLOAD_DIRECTORY))
		_sync_controls()
		return
	_log("Saved: " + ProjectSettings.globalize_path(_last_path))
	_play_download()


func _play_download() -> void:
	_stop_playback()
	if _last_was_audio:
		var stream: AudioStream
		match _last_path.get_extension():
			"mp3":
				var mp3 := AudioStreamMP3.new()
				mp3.data = FileAccess.get_file_as_bytes(_last_path)
				stream = mp3
			"ogg":
				stream = AudioStreamOggVorbis.load_from_file(_last_path)
			"wav":
				stream = AudioStreamWAV.load_from_file(_last_path)
			_:
				stream = ResourceLoader.load(_last_path, "", ResourceLoader.CACHE_MODE_IGNORE) as AudioStream
		if stream == null:
			_log("Saved successfully, but no audio loader could open this file. Enable fallback for vanilla playback.")
		else:
			audio_player.stream = stream
			audio_player.play()
			_log("Playing audio.")
	else:
		var stream: VideoStream
		if _last_path.get_extension() == "ogv":
			var theora := VideoStreamTheora.new()
			theora.file = _last_path
			stream = theora
		else:
			stream = ResourceLoader.load(_last_path, "", ResourceLoader.CACHE_MODE_IGNORE) as VideoStream
		if stream == null:
			_log("Saved successfully, but no video loader could open this file. Enable fallback for vanilla playback.")
		else:
			video_player.stream = stream
			video_player.play()
			_log("Playing video.")
	_sync_controls()


func _stop_playback() -> void:
	audio_player.stop()
	video_player.stop()
	_sync_controls()


func _log(message: String) -> void:
	log_output.add_text(message + "\n")
