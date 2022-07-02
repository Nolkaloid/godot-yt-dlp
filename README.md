![logo_light](https://user-images.githubusercontent.com/30960698/176983082-18bf15ee-3144-4a54-bab9-bbb9650e63a3.png#gh-light-mode-only)
![logo_dark](https://user-images.githubusercontent.com/30960698/176983087-022d7ccd-d94c-43da-a8ff-f8f5736d9c3b.png#gh-dark-mode-only)

An implementation of [yt-dlp](https://github.com/yt-dlp/yt-dlp) for the Godot engine that works on **Linux**, **OSX** and **Windows**.

## Features
 - [x] Automatic [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [ffmpeg](https://www.ffmpeg.org/) setup (the latter only on Windows).
 - [x] Downloading single videos from YouTube.
 - [x] Converting videos to audio.
 - [ ] Downloading playlists of videos from YouTube. *(yet to be implemented)*
 - [ ] Searching YouTube videos. *(yet to be implemented)*
 
## Installation

- Clone or download the repository and place the `yt-dlp` folder somewhere in your project.

> If you're using Linux or exporting to Linux make sure that **ffmpeg** is installed on the system
> Same goes for OSX (undocumented)

## How to use

### Setup:

Create a new `YtDlp` object like this:

```gdscript
var yt_dlp = YtDlp.new()
```

Usually you'll want to connect its signals immediately like this:

```gdscript
yt_dlp.connect("ready", self, "some_function")
yt_dlp.connect("download_completed", self, "some_other_function")
```

 - The `ready` signal is emitted when YtDlp has finished the initial setup and is ready to download videos. 
 - The `download_completed` signal is emitted when YtDlp has finished downloading a video/audio.

> You could also use `yield` to wait for the signals

### Usage:

To download a YouTube video use the `download` function:

```gdscript
yt_dlp.download(
  url: String,
  destination: String,
  file_name: String,
  convert_to_audio: bool = false,
  video_format: int = Video.WEBM,
  audio_format: int = Audio.VORBIS
)
```
 - `String` **url:** The video url 
 - `String` **destination:** The folder where you want the video to be downloaded
 - `String` **file_name:** Specify the filename without extension, can be leaved blank
 - `bool` **convert_to_audio:** If true the video will be converted to audio
 - `int`  **video_format:** Used to specify the video format to download, use the built-in enum `YtDlp.Video`.
 - `int` **audio_format:** Used to specify the audio format for conversion, use the built-in enum `YtDlp.Audio`.
 
 #### Supported formats audio/video formats:
 
 ##### Video:
 - `WEBM` *(default)*
 - `MP4`
 
 ##### Audio:
 - `MP3`
 - `FLAC`
 - `AAC`
 - `VORBIS` *(default)*
 - `OPUS`
 - `M4A`
 - `WAV`
 
 ### Examples:
 
 #### Downloading a video:
```gdscript
var yt_dlp := YtDlp.new()
yield(yt_dlp, "ready")

yt_dlp.download("https://youtu.be/dQw4w9WgXcQ",
		"/home/nolka/videos/", "video_clip")

yield(yt_dlp, "download_completed")
print("Done!")
```

#### Downloading a video as audio and playing it in an `AudioStreamPlayer`:

```gdscript
var yt_dlp := YtDlp.new()
yield(yt_dlp, "ready")

yt_dlp.download("https://youtu.be/PSPbY00UZ9w",
			OS.get_user_data_dir(), "audio_clip", true)

yield(yt_dlp, "download_completed")

var ogg_file := File.new()
ogg_file.open("user://audio_clip.ogg", File.READ)

var stream := AudioStreamOGGVorbis.new()
stream.data = ogg_file.get_buffer(ogg_file.get_len())

ogg_file.close()

$AudioStreamPlayer.stream = stream
$AudioStreamPlayer.play()
```

### Social:
- https://twitter.com/NoeGameDev
- https://www.youtube.com/c/Nolkaloid
