extends Reference

class_name Downloader

signal request_completed
signal request_progress(percent)




func download_from_web(url : String, destination : String ="user://", filename : String = "downloaded_file"):
	var thread = Thread.new()
	thread.start(self, "_dl_thread", [url, destination, filename])

func _dl_thread(arguments):
	
	var percent_loaded = 0

	var url = arguments[0]
	var destination = arguments[1]
	var filename = arguments[2]
	
	var file = File.new()
	var http = HTTPClient.new()
	# Regex to process the url
	var re = RegEx.new()
	re.compile("(https:\\/\\/[^\\/]*)(.*)")

	if not re.search_all(url): # Checks if the url is valid
		print("[ERROR] Invalid url")
		return

	var server = re.search(url).get_string(1)
	url = re.search(url).get_string(2)


	# Connection to host
	http.connect_to_host(server, -1, true)

	#Poll until ice cream
	print("Connecting...")
	while http.get_status() == HTTPClient.STATUS_RESOLVING or http.get_status() == HTTPClient.STATUS_CONNECTING:
		http.poll()
	
	if http.get_status() == HTTPClient.STATUS_CONNECTED:
		print("Connection established") # If the connection is successful continue

	else:
		print("[ERROR] Connection failed: ", http.get_status()) # Else return from the function
		return


	# Setup headers
	var headers = [
		"User-Agent: Mozilla/5.0",
		"Accept: */*"
	]


	# Make the request
	http.request(HTTPClient.METHOD_GET, url, headers)

	print("Requesting...")
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		# Keep polling until the request is going on
		http.poll()

	assert(http.get_status() == HTTPClient.STATUS_BODY or http.get_status() == HTTPClient.STATUS_CONNECTED)

	
	var response_headers = http.get_response_headers_as_dictionary()
	

#	file.open("user://header.json", File.WRITE)
#	file.store_string(JSON.print(response_headers))
#	file.close()
	
	file.open(destination + filename, File.WRITE)
	file.close()
	file.open(destination + filename, File.READ_WRITE)


	if http.get_response_code() == HTTPClient.RESPONSE_OK: # If the request was successful
	
		while http.get_status() == HTTPClient.STATUS_BODY:
			
			http.poll()
			file.store_buffer(http.read_response_body_chunk())

			if percent_loaded < file.get_len()*100 / http.get_response_body_length():
				percent_loaded = file.get_len()*100 / http.get_response_body_length()
				emit_signal("request_progress", percent_loaded)
	
	elif http.get_response_code() == HTTPClient.RESPONSE_FOUND:
		print("Redirect to ", response_headers["Location"])
		download_from_web(response_headers["Location"], destination, filename)
		return

	else:
		print("[ERROR] Request not successful: ", http.get_response_code())
		return

	file.close()
	print("Done!")
	emit_signal("request_completed")