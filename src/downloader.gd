extends RefCounted

signal download_completed
signal download_failed
signal download_progressed(percentage)

var _is_downloading: bool = false
var _headers = PackedStringArray([
	"User-Agent: Pirulo/1.0 (Godot)",
	"Accept: */*"
])

func download(url: String, file_path: String) -> void:
	if _is_downloading:
		push_error(self, "A download is already in progress.")
	
	_is_downloading = true
	
	var url_regex = RegEx.new()
	url_regex.compile("^(?<host>((?<protocol>https?):\\/\\/)?[^\\/]+\\.[a-z]{2,})(?<path>(?>\\/.*)*)$")
	
	var host: String
	var path: String
	var protocol: String
	
	# Validate the URL
	match url_regex.search(url) as RegExMatch:
		null:
			download_failed.emit()
			return
		
		var result:
			protocol = result.get_string("protocol")
			host = result.get_string("host")
			path = result.get_string("path")
	
	var http_client := HTTPClient.new()
	http_client.connect_to_host(host, 80 if protocol == "http" else 443)
	
	while http_client.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		http_client.poll()
		await (Engine.get_main_loop() as SceneTree).process_frame
	
	# Handle connection failure
	if http_client.get_status() != HTTPClient.STATUS_CONNECTED:
		download_failed.emit()
		return
	
	http_client.request(HTTPClient.METHOD_GET, path, _headers)
	
	while not http_client.has_response():
		http_client.poll()
		await (Engine.get_main_loop() as SceneTree).process_frame
	
	# Handle the response
	match http_client.get_response_code():
		HTTPClient.RESPONSE_FOUND, HTTPClient.RESPONSE_MOVED_PERMANENTLY:
			var response_headers := http_client.get_response_headers_as_dictionary()
			_is_downloading = false
			download(response_headers["Location"], file_path)
			return
	
		HTTPClient.RESPONSE_OK:
			await _store_body_to_file(http_client, file_path)
	
		_:
			download_failed.emit()
			return
	
	_is_downloading = false
	download_completed.emit()


func _store_body_to_file(http_client: HTTPClient, file_path: String) -> void:
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	var percentage_loaded: float = 0.0

	while http_client.get_status() == HTTPClient.STATUS_BODY:
		http_client.poll()
		file.store_buffer(http_client.read_response_body_chunk())
		
		var new_percentage = file.get_length() * 100 / http_client.get_response_body_length()
		
		if percentage_loaded < new_percentage:
			percentage_loaded = new_percentage
			download_progressed.emit(percentage_loaded)
		
		await (Engine.get_main_loop() as SceneTree).process_frame

	file.close()
