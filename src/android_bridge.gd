extends RefCounted

const SINGLETON_NAME := "GodotYtDlpAndroid"
const BRIDGE_CLASS_NAME := "org.godotengine.ytdlp.bridge.YtDlpBridge"


static func is_android_platform() -> bool:
	return OS.get_name() == "Android"


static func has_backend() -> bool:
	return _get_java_bridge() != null or (is_android_platform() and Engine.has_singleton(SINGLETON_NAME))


static func get_backend():
	var java_bridge = _get_java_bridge()
	if java_bridge != null:
		return java_bridge
	if not has_backend():
		return null
	return Engine.get_singleton(SINGLETON_NAME)


static func _get_java_class_wrapper():
	if not is_android_platform():
		return null
	if not Engine.has_singleton("JavaClassWrapper"):
		return null
	return Engine.get_singleton("JavaClassWrapper")


static func _get_android_runtime():
	if not is_android_platform():
		return null
	if not Engine.has_singleton("AndroidRuntime"):
		return null
	return Engine.get_singleton("AndroidRuntime")


static func _get_java_bridge():
	var wrapper = _get_java_class_wrapper()
	if wrapper == null:
		return null
	var bridge = wrapper.wrap(BRIDGE_CLASS_NAME)
	if bridge == null:
		return null
	return bridge


static func get_backend_debug_state() -> String:
	var singleton_list := PackedStringArray()
	if Engine.has_method("get_singleton_list"):
		singleton_list = Engine.get_singleton_list()
	return "AndroidBridge state: os=%s expected_singleton=%s java_bridge=%s has_backend=%s singletons=%s" % [
		OS.get_name(),
		SINGLETON_NAME,
		str(_get_java_bridge() != null),
		str(has_backend()),
		str(singleton_list)
	]


static func get_backend_capabilities() -> String:
	var java_bridge = _get_java_bridge()
	if java_bridge != null:
		return "AndroidBridge capabilities: java_bridge=true setup=true is_ready=true extract_info=true search=true download_audio=true download_video=true start_download_audio=false start_download_video=false get_download_state=false clear_download_state=false"
	var backend: Variant = get_backend()
	if backend == null:
		return "AndroidBridge capabilities: backend=null"
	return "AndroidBridge capabilities: setup_backend=%s is_ready=%s extract_info=%s search=%s download_audio=%s download_video=%s start_download_audio=%s start_download_video=%s get_download_state=%s clear_download_state=%s" % [
		str(backend.has_method("setup_backend") or backend.has_method("setup")),
		str(backend.has_method("is_ready") or backend.has_method("isReady")),
		str(backend.has_method("extract_info") or backend.has_method("extractInfo")),
		str(backend.has_method("search")),
		str(backend.has_method("download_audio") or backend.has_method("downloadAudio")),
		str(backend.has_method("download_video") or backend.has_method("downloadVideo")),
		str(backend.has_method("start_download_audio")),
		str(backend.has_method("start_download_video")),
		str(backend.has_method("get_download_state")),
		str(backend.has_method("clear_download_state"))
	]


static func setup_backend() -> bool:
	var java_bridge = _get_java_bridge()
	if java_bridge != null:
		var android_runtime = _get_android_runtime()
		if android_runtime == null:
			return false
		return bool(java_bridge.setup(android_runtime.getApplicationContext()))

	var backend: Variant = get_backend()
	if backend == null:
		return false
	if backend.has_method("setup_backend"):
		return bool(backend.call("setup_backend"))
	return true


static func is_ready() -> bool:
	var java_bridge = _get_java_bridge()
	if java_bridge != null:
		return bool(java_bridge.isReady())

	var backend: Variant = get_backend()
	if backend == null:
		return false
	if backend.has_method("is_ready"):
		return bool(backend.call("is_ready"))
	return true


static func extract_info(url: String) -> Dictionary:
	var java_bridge = _get_java_bridge()
	if java_bridge != null:
		return _dictionary_from_variant(java_bridge.extractInfo(url))

	var backend: Variant = get_backend()
	if backend == null:
		return {}
	if backend.has_method("extract_info"):
		return _dictionary_from_variant(backend.call("extract_info", url))
	return {}


static func search(search_term: String, number_of_results: int) -> Array[Dictionary]:
	var java_bridge = _get_java_bridge()
	if java_bridge != null:
		return _dictionary_array_from_variant(java_bridge.search(search_term, number_of_results))

	var backend: Variant = get_backend()
	if backend == null:
		return []
	if backend.has_method("search"):
		return _dictionary_array_from_variant(backend.search(search_term, number_of_results))
	return []


static func download_audio(url: String, destination: String, file_name: String, audio_format: String) -> bool:
	var java_bridge = _get_java_bridge()
	if java_bridge != null:
		return bool(java_bridge.downloadAudio(url, destination, file_name, audio_format))

	var backend: Variant = get_backend()
	if backend == null:
		return false
	if backend.has_method("download_audio"):
		return bool(backend.call("download_audio", url, destination, file_name, audio_format))
	return false


static func download_video(url: String, destination: String, file_name: String, format_selector: String) -> bool:
	var java_bridge = _get_java_bridge()
	if java_bridge != null and java_bridge.has_method("downloadVideo"):
		return bool(java_bridge.downloadVideo(url, destination, file_name, format_selector))

	var backend: Variant = get_backend()
	if backend == null:
		return false
	if backend.has_method("download_video"):
		return bool(backend.call("download_video", url, destination, file_name, format_selector))
	return false


static func start_download_audio(request_id: int, url: String, destination: String, file_name: String, audio_format: String) -> bool:
	if _get_java_bridge() != null:
		return false

	var backend: Variant = get_backend()
	if backend == null:
		return false
	if backend.has_method("start_download_audio"):
		return bool(backend.call("start_download_audio", request_id, url, destination, file_name, audio_format))
	return false


static func start_download_video(request_id: int, url: String, destination: String, file_name: String, format_selector: String) -> bool:
	if _get_java_bridge() != null:
		return false

	var backend: Variant = get_backend()
	if backend == null:
		return false
	if backend.has_method("start_download_video"):
		return bool(backend.call("start_download_video", request_id, url, destination, file_name, format_selector))
	return false


static func get_download_state(request_id: int) -> Dictionary:
	if _get_java_bridge() != null:
		return {}

	var backend: Variant = get_backend()
	if backend == null:
		return {}
	if backend.has_method("get_download_state"):
		return _dictionary_from_variant(backend.call("get_download_state", request_id))
	return {}


static func clear_download_state(request_id: int) -> void:
	if _get_java_bridge() != null:
		return

	var backend: Variant = get_backend()
	if backend == null:
		return
	if backend.has_method("clear_download_state"):
		backend.call("clear_download_state", request_id)


static func get_last_error() -> String:
	var java_bridge = _get_java_bridge()
	if java_bridge != null:
		return str(java_bridge.getLastError())

	var backend: Variant = get_backend()
	if backend == null:
		return "Android yt-dlp backend is unavailable. Engine.has_singleton(\"%s\") returned false, which usually means the Android plugin AAR or its Java dependencies were not packaged into the export, or the addon plugin is not enabled in the project." % SINGLETON_NAME
	if backend.has_method("get_last_error"):
		return str(backend.call("get_last_error"))
	return ""


static func _dictionary_from_variant(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	if typeof(value) == TYPE_STRING:
		var parsed := JSON.parse_string(str(value))
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
	return {}


static func _dictionary_array_from_variant(value: Variant) -> Array[Dictionary]:
	var source: Array = []
	if typeof(value) == TYPE_ARRAY:
		source = value
	elif typeof(value) == TYPE_STRING:
		var parsed := JSON.parse_string(str(value))
		if typeof(parsed) == TYPE_ARRAY:
			source = parsed

	var results: Array[Dictionary] = []
	for entry in source:
		if typeof(entry) == TYPE_DICTIONARY:
			results.append(entry)
	return results