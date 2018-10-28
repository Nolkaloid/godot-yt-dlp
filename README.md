
An implementation of [youtube-dl](https://github.com/rg3/youtube-dl/) for the Godot engine that works on **Linux**, **OSX** and **Windows**

## Features:
 - [x] Automatic [youtube-dl](https://github.com/rg3/youtube-dl/) and [ffmpeg] setup.
 - [x] Downloading single videos from Youtube.
 - [x] Converting videos to audio.
 - [ ] Downloading playlists of videos from Youtube. *(yet to be implemented)*
 - [ ] Searching Youtube videos. *(yet to be implemented)*
 
## Installation:
- Clone the repository and place the youtube-dl folder in your project folder.
- Go to the project settings under **Network/Ssl/Certificates** and select the `ca-certificates.crt` in the youtube-dl folder.

**[IMPORTANT] Note that when exporting your project you will have to add the certificates to the export see [here](http://docs.godotengine.org/en/3.0/tutorials/networking/ssl_certificates.html).**

## How to use:

Create a new Youtube-DL object like this:
```gdscript
var youtube_dl = YoutubeDl.new()
```
Usually you will want to connect it's signals immediately like this:
```gdscript
youtube_dl.connect("ready", self, "ready_to_dl")
youtube_dl.connect("download_complete", self, "yt_dowload_complete")
```



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
