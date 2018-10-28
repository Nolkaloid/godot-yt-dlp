
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
var your_youtube_dl_variable = Youtube-Dl.new()
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
