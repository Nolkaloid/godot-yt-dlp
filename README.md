![logo_light](https://user-images.githubusercontent.com/30960698/176983082-18bf15ee-3144-4a54-bab9-bbb9650e63a3.png#gh-light-mode-only)
![logo_dark](https://user-images.githubusercontent.com/30960698/176983087-022d7ccd-d94c-43da-a8ff-f8f5736d9c3b.png#gh-dark-mode-only)

An implementation of [yt-dlp](https://github.com/yt-dlp/yt-dlp) for **Godot 4.x** that works on Linux, OSX and Windows.\
This project provides a simple API for downloading videos from YouTube (and other websites).

> **:information_source: Use [v2.0.3](https://github.com/Nolkaloid/godot-yt-dlp/tree/v2.0.3) for Godot 3.x**

## Features

- [x] Automatic [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [ffmpeg](https://www.ffmpeg.org/) setup (the latter only on Windows).
- [x] Downloading single videos.
- [x] Converting videos to audio.
- [ ] Tracking download progress. *(yet to be implemented)*
- [ ] Downloading playlists of videos. *(yet to be implemented)*
- [ ] Searching YouTube videos. *(yet to be implemented)*

## Installation

Clone the repository or [download a release](https://github.com/Nolkaloid/godot-yt-dlp/releases/latest), place it into the `addons/` folder in your project and enable the plugin. See the [Godot Docs](https://docs.godotengine.org/en/stable/tutorials/plugins/editor/installing_plugins.html) for a detailed guide.

> If you're using Linux or exporting to Linux make sure that **ffmpeg** is installed on the system  
> Same goes for OSX (undocumented)

## How to use

### Setup

After enabling the plugin a `YtDlp` autoload singleton will be registered.
In order to use it you must first call the `setup()` method that will download all relevant depedencies (up-to-date **yt-dlp** and **ffmpeg** if using Windows).

You can check if `YtDlp` is ready by using the `is_setup()` method. You can also connect or await the `setup_completed` signal to be notified when `YtDlp` is ready to download.

```gdscript
if not YtDlp.is_setup():
    YtDlp.setup()
    await YtDlp.setup_completed
```

### Usage

To download a video use the `download(url)` method, it will create a `Download` object that can be complemented using [method chaining](https://en.wikipedia.org/wiki/Method_chaining) and started with `start()` method.

You can connect or await the `download_completed` signal, to be notified of when the download is completed.

You can check the status of a Download using the `get_status()` method.

```gdscript
# Downloads a video as audio and stores it to "user://audio/ok_computer.mp3"
var download := YtDlp.download("https://youtu.be/Ya5Fv6VTLYM") \
        .set_destination("user://audio/") \
        .set_file_name("ok_computer") \
        .convert_to_audio(YtDlp.Audio.MP3) \
        .start()

assert(download.get_status() == YtDlp.Download.Status.DOWNLOADING)

await download.download_completed
print("Download completed !")
```

## Examples

### Downloading a video and playing it in using a `VideoPlayer`

Soon possible, see: <https://github.com/godotengine/godot-proposals/issues/3286>

### Downloading a video as audio and playing it using an `AudioStreamPlayer`

```gdscript
if not YtDlp.is_setup():
    YtDlp.setup()
    await YtDlp.setup_completed

var download := YtDlp.download("https://youtu.be/Ya5Fv6VTLYM") \
        .set_destination("user://audio/") \
        .set_file_name("ok_computer") \
        .convert_to_audio(YtDlp.Audio.MP3) \
        .start()

await download.download_completed

var stream = AudioStreamMP3.new()
var audio_file = FileAccess.open("user://audio/ok_computer.mp3", FileAccess.READ)

stream.data = audio_file.get_buffer(audio_file.get_length())
audio_file.close()

$AudioStreamPlayer.stream = stream
$AudioStreamPlayer.play()
```

## Reference

### `YtDlp`

#### Signals

##### `setup_completed`

Fired when the setup is completed and `YtDlp` is ready to use

#### Enums

##### Video

- `WEBM` *(default format)*
- `MP4`

###### Audio

- `MP3` *(default format)*
- `FLAC`
- `AAC`
- `VORBIS`
- `OPUS`
- `M4A`
- `WAV`

#### Methods

#### `setup() -> void`

Sets up the `yt-dlp` dependencies.

#### `download(url: String) -> Download`

Creates a new `Download` with the target `url`.

#### `is_setup() -> bool`

Returns `true` if `YtDlp` is ready to use, else returns `false`

### `Download`

#### Signals

##### `download_completed`

Fired when the download is completed.

#### Enums

##### `Status`

- `READY`
- `DOWNLOADING`
- `COMPLETED`

#### Methods

##### `set_destination(destination: String) -> Download`

Sets the destination directory of a download.

##### `set_file_name(file_name: String) -> Download`

Sets the file name of the downloaded file (without file extension).

##### `set_video_format(format: YtDlp.Video) -> Download`

Sets the format of the downloaded video.

##### `convert_to_audio(format: YtDlp.Audio) -> Download`

Marks the download to be converted to audio.

##### `start() -> Download`

Starts the download.

##### `get_status() -> Status:`

Returns the status of the download

## Social

- <https://twitter.com/NoeGameDev>
- <https://www.youtube.com/c/Nolkaloid>
