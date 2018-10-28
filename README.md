An implementation of [youtube-dl](https://github.com/rg3/youtube-dl/) for the Godot engine that works on **Linux**, **OSX** and **Windows**

## Features
 - [x] Automatic [youtube-dl](https://github.com/rg3/youtube-dl/) and [ffmpeg] setup.
 - [x] Downloading single videos from YouTube.
 - [x] Converting videos to audio.
 - [ ] Downloading playlists of videos from YouTube. *(yet to be implemented)*
 - [ ] Searching YouTube videos. *(yet to be implemented)*
 
## Installation
- Clone the repository and place the youtube-dl folder in your project folder.
- Go to the project settings under **Network/Ssl/Certificates** and select the `ca-certificates.crt` in the youtube-dl folder.

**[IMPORTANT] Note that when exporting your project you will have to add the certificates to the export see [here](http://docs.godotengine.org/en/3.0/tutorials/networking/ssl_certificates.html).**

## How to use
### Setup:
Create a new YouTube-DL object like this:
```gdscript
var youtube_dl = YouTubeDl.new()
```
Usually you will want to connect it's signals immediately like this:
```gdscript
youtube_dl.connect("ready", self, "ready_to_dl")
youtube_dl.connect("download_complete", self, "yt_dowload_complete")
```
 - The `ready` signal is emitted when the YouTubeDL object has finished the initial setup and is ready to download YouTube videos. 
 - The  `download_complete` signal is emitted when the YouTubeDL object has finished downloading a video/audio.
### Usage:
To download a YouTube video use the `download` function:
```gdscript
youtube_dl.download(url, destination_path, filename, convert_to_audio, video_format, audio_format)
```
 - `string` **url:** The YouTube video url 
 - `string` **destination_path:** The folder where you want the video to be downloaded
 - `string` **filename:** Specify the filename without extension, can be leaved blank
 - `bool` **convert_to_audio:** If true the video will be converted to the specified audio format
 - `int`  **video_format:** Used to specify the video format to download, use built-in constants like ```gdscript
YouTubeDl.VIDEO_WEBM```
 ### Supported formats:
 #### Video:
 - webm **(only for non 60fps videos)**
 - mp4
 #### Audio:
 - mp3
 - flac
 - aac
 - vorbis (ogg)
 - opus (ogg)
 - m4a
 - wav
