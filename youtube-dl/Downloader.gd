extends Reference

class_name Downloader

signal request_completed
signal request_progress(percent)
onready var thread


func download(url : String, destination : String ="user://", filename : String = "downloaded_file"):
	thread = Thread.new()
	thread.start(self, "req", [url, destination, filename])
	

func req(arguments):
	
	var percent_loaded = 0

	var url = arguments[0]
	var destination = arguments[1]
	var filename = arguments[2]
	
	var http = HTTPClient.new()
	var file = File.new()
	# Regex to process the url
	var re = RegEx.new()
	re.compile("(https:\\/\\/[^\\/]*)(.*)")

	if not re.search_all(url): # Checks if the url is valid
		print("[ERROR] Invalid url")
		return
	
	
	
	var server = re.search(url).get_string(1)
	print("Connecting to: ", server)
	
	url = re.search(url).get_string(2)


	# Connection to host
	http.connect_to_host(server, -1, true)

	#Poll until ice cream
	
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

	
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		# Keep polling until the request is going on
		http.poll()
	

	assert(http.get_status() == HTTPClient.STATUS_BODY or http.get_status() == HTTPClient.STATUS_CONNECTED)

	
	var response_headers = http.get_response_headers_as_dictionary()
	

#	file.open("user://header.json", File.WRITE)
#	file.store_string(JSON.print(response_headers))
#	file.close()


	if http.get_response_code() == 200: # If the request was successful
		
		file.open(destination + filename, File.WRITE)
		file.close()
		file.open(destination + filename, File.READ_WRITE)
	
		while http.get_status() == HTTPClient.STATUS_BODY:
			
			http.poll()
			file.store_buffer(http.read_response_body_chunk())

			if percent_loaded < file.get_len()*100 / http.get_response_body_length():
				percent_loaded = file.get_len()*100 / http.get_response_body_length()
				emit_signal("request_progress", percent_loaded)
				
		file.close()
		

	elif http.get_response_code() == 302:
		for i in response_headers: response_headers[i.capitalize()] = response_headers[i]
		req([response_headers["Location"], destination, filename])
		return

	else:
		print("[ERROR] Request not successful: ", http.get_response_code())
		return

	emit_signal("request_completed")
	return
