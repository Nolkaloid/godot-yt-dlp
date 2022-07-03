# warning-ignore-all:return_value_discarded
extends Reference

signal download_completed
signal download_failed
signal download_progress(percentage)

const _headers: Array = [
	"User-Agent: Mozilla/5.0",
	"Accept: */*",
]

func download(url: String, file_path: String = "user://") -> void:
	# RegEx for parsing the URL
	var url_regex = RegEx.new()
	url_regex.compile("^https?:\\/\\/(?<host>[^\\/]+\\.[a-z]{2,})(?<path>(?>\\/.*)*)$")
	
	var host: String
	var path: String
	
	# Validate the URL
	match url_regex.search(url) as RegExMatch:
		null:
			push_error("[downloader] Invalid URL")
			emit_signal("download_failed")
			return
		
		var result:
			host = result.get_string("host")
			path = result.get_string("path")
	
	var http_client := HTTPClient.new()
	
	print("[downloader] Connecting to %s" % host)
	http_client.connect_to_host(host, -1, true)
	
	# Connection to the host
	while http_client.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		http_client.poll()
		yield(Engine.get_main_loop(), "idle_frame")
	
	# Handle connection failure
	if http_client.get_status() != HTTPClient.STATUS_CONNECTED:
		push_error("[downloader] Connection failed: status=%d" % http_client.get_status())
		emit_signal("download_failed")
		return
	
	print("[downloader] Requesting resource at %s" % path)
	http_client.request(HTTPClient.METHOD_GET, path, _headers)
	
	# Request the resource
	while http_client.get_status() == HTTPClient.STATUS_REQUESTING:
		http_client.poll()
		yield(Engine.get_main_loop(), "idle_frame")
	
	# Handle the response
	match http_client.get_response_code():
		HTTPClient.RESPONSE_FOUND, HTTPClient.RESPONSE_MOVED_PERMANENTLY:
			var response_headers := http_client.get_response_headers_as_dictionary()
			download(response_headers["Location"], file_path)
			return
		
		HTTPClient.RESPONSE_OK:
			print("[downloader] Storing response body into %s" % file_path)
			yield(_store_body_to_file(http_client, file_path), "completed")
		
		_:
			push_error("[downloader] Request failed with code %d" % http_client.get_response_code())
			emit_signal("download_failed")
			return
	
	emit_signal("download_completed")


func _store_body_to_file(http_client: HTTPClient, file_path: String) -> void:
	var file: File = File.new()
	file.open(file_path, File.WRITE)
	
	var percentage_loaded: float = 0.0
	
	while http_client.get_status() == HTTPClient.STATUS_BODY:
		http_client.poll()
		file.store_buffer(http_client.read_response_body_chunk())
		
		var new_percentage := file.get_len() / float(http_client.get_response_body_length())
		
		if percentage_loaded < new_percentage:
			percentage_loaded = new_percentage
			emit_signal("download_progress", percentage_loaded)
		
		yield(Engine.get_main_loop(), "idle_frame")
	
	file.close()
