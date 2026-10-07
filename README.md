![logo_light](https://user-images.githubusercontent.com/30960698/176983082-18bf15ee-3144-4a54-bab9-bbb9650e63a3.png#gh-light-mode-only)
![logo_dark](https://user-images.githubusercontent.com/30960698/176983087-022d7ccd-d94c-43da-a8ff-f8f5736d9c3b.png#gh-dark-mode-only)

An implementation of [yt-dlp](https://github.com/yt-dlp/yt-dlp) for **Godot 4.x** that works on Linux, macOS, Windows and Android.\
This project provides a simple API for downloading videos from YouTube (and other websites).

> **:information_source: Use [v2.0.3](https://github.com/Nolkaloid/godot-yt-dlp/tree/v2.0.3) for Godot 3.x**

## Features

- [x] Automatic [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [ffmpeg](https://www.ffmpeg.org/) setup (the latter only on Windows).
- [x] Downloading single videos.
- [x] Converting videos to audio.
- [ ] Tracking download progress. *(yet to be implemented)*
- [ ] Downloading playlists of videos. *(yet to be implemented)*

## Installation

Clone the repository or [download a release](https://github.com/Nolkaloid/godot-yt-dlp/releases/latest), place it into the `addons/` folder in your project and enable the plugin. See the [Godot Docs](https://docs.godotengine.org/en/stable/tutorials/plugins/editor/installing_plugins.html) for a detailed guide.

> If you're using Linux or exporting to Linux make sure that **ffmpeg** is installed on the system  
> Same goes for OSX (undocumented)

### Android and building the AARs

The Android support was contributed by **RSDNTWK** and adapted from the
**Threads of Illusions** game project.

Android requires Godot 4.2+, Android 7.0/API 24+, and **Use Gradle Build** in the
export preset. Install the Android build template and keep this addon enabled.
The plugin packages the matching AAR and resolves yt-dlp/FFmpeg from Maven.
Use a writable destination such as `user://audio/`.

To rebuild from source, install **JDK 17**, **Android SDK platform 35** and
**Build Tools 35.0.0**. Set `JAVA_HOME` and `ANDROID_HOME` (or use `sdk.dir` in
`android/local.properties`). Run from the repository root:

```powershell
# Windows
.\android\gradlew.bat -p android clean copyAars
```

```sh
# Linux / macOS
sh android/gradlew -p android clean copyAars
```

The Gradle 8.11.1 wrapper downloads dependencies on the first build, compiles
`src/bridge/` and `src/plugin/`, and writes debug/release AARs to `bin/`.
No existing AAR or custom Godot checkout is needed. Run the same command with
`lint` instead of `clean copyAars` for Android checks.

Build settings and the manifest live in `android/`. Dependency versions are in
`android/gradle.properties`; keep `youtubedlVersion` synchronized with
`godot_yt_dlp.gd`. Use `-PgodotVersion=<version>` to override the compile-only
Godot dependency (default `4.4.1.stable`). Rebuild both AARs after Java or manifest
changes. Godot and the Maven runtime dependencies are not embedded in the AARs.

## How to use

### Setup

After enabling the plugin a `YtDlp` autoload singleton will be registered.
Call `setup()` to initialize the runtime and update **yt-dlp** from the nightly channel. Windows also downloads **ffmpeg**; Android initializes its bundled runtime on a worker thread.

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

`Video.AUTO` selects the best available video without a resolution cap or forced
conversion, and `Audio.AUTO` extracts the best native audio format. Desktop
`Video.WEBM` prefers VP9/VP8 and Opus on YouTube, probes available hardware
encoders for conversion, and falls back to libvpx. Direct WebM URLs skip recoding.
Android retains its existing VP9/Opus WebM conversion for non-`AUTO` video
requests, except direct WebM URLs; choosing `MP4`, `MOV`, `MKV`, or `OGV` does not
guarantee that output container on Android.

For a bounded setup wait, use `await YtDlp.ensure_ready()`. It returns a boolean
after setup completes or the 120-second wait expires; timing out does not cancel
setup. `is_runtime_available()` checks for the desktop executable or a ready
Android backend.

### Abandoning a request

Both `Download` and `Search` provide `stop()`, adapted from
[upstream PR #13 by iamrequest](https://github.com/Nolkaloid/godot-yt-dlp/pull/13).
It sets the status to `INTERRUPTED` and suppresses the completion signal, including
when called while a desktop or Android worker is running. The worker is joined
and released after it returns. A download stopped before `start()` never starts.

This abandons the result; it does **not** terminate an active yt-dlp/FFmpeg
process or undo file writes. Use distinct output filenames for concurrent
downloads, and do not await a completion signal after calling `stop()`.

## Examples

### Downloading a video and playing it in using a `VideoPlayer`

The only supported format in Godot (core) is Ogg Theora, which you won't get straight from YouTube.
To actually playback the videos can use the following projects:

- https://github.com/EIRTeam/EIRTeam.FFmpeg
- https://github.com/DeeJayLSP/godot-mpg

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

### Searching for a video and downloading it

>[!IMPORTANT]
> Only available in the `master` branch

```gdscript
if not YtDlp.is_setup():
    YtDlp.setup()
    await YtDlp.setup_completed

var search: YtDlp.Search = YtDlp.search("Lemaitre RebMoe - OK Computer", 1)
await search.search_completed

var search_results = search.get_results()
var download := YtDlp.download(search_results[0].url) \
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
- `MOV`, `MKV`, `OGV` *(currently use the same generic video selector; they do not force these containers)*
- `AUTO`

###### Audio

- `MP3` *(default format)*
- `FLAC`
- `AAC`
- `VORBIS`
- `OPUS`
- `M4A`
- `WAV`
- `AUTO`

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
- `FAILED`
- `INTERRUPTED`

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

##### `stop() -> void`

Abandons a pending or running download and suppresses `download_completed`.
Also available on `Search`, where it suppresses `search_completed`.

##### `get_status() -> Status:`

Returns the status of the download

## Social

- <https://bsky.app/profile/nolkaloid.bsky.social>
- <https://www.youtube.com/c/Nolkaloid>
