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

Android runs the **official upstream yt-dlp code used on desktop**, using its
portable Python archive and matching bundled EJS scripts. The Android Maven
libraries supply Python, QuickJS and FFmpeg; their extractor updater and request
execution path are bypassed. Setup fetches the official nightly archive, verifies
its release SHA-256 checksum, and installs it atomically. A previously installed
archive remains usable if an update cannot be fetched; first setup needs internet
access. Setup also checks the packaged executables and runs `yt-dlp --version`.

YouTube client selection, visitor headers and JavaScript challenges are handled
by upstream yt-dlp, without the old forced Android/TV clients or fixed audio IDs.
See [yt-dlp's EJS documentation](https://github.com/yt-dlp/yt-dlp/wiki/EJS).
`extract_info()` preserves the full metadata, including `http_headers`, formats
and per-stream headers. Code that fetches resolved media URLs itself must also
send the corresponding headers; signed URLs expire.

Downloads retry a YouTube HTTP 403 once, re-extracting the original URL with the
same format and destination. Failures are available through
`Download.get_error_message()`. Repeated setup calls reuse the ready runtime.

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

Format compatibility is selected by the shared API on **Windows, Linux, macOS
and Android**. Requested formats are retained when the running Godot build
registers a suitable stream loader. Otherwise, video falls back to Ogg Theora
with Vorbis audio (`.ogv`), and audio falls back to MP3. Core Vorbis (`.ogg`) and
WAV audio remain available. No resolution cap is applied.

`Video.AUTO` prefers supported WebM, MP4, MKV or MOV, then OGV. `Audio.AUTO`
prefers supported Opus, M4A, AAC or FLAC, then MP3. Selection is fixed when
`start()` is called. Use `download.get_output_extension()` to obtain the selected
extension; an explicit unsupported request may therefore produce a different
extension than requested.

For external players, or extensions that do not register stream loaders, use
`.set_format_fallback_enabled(false)`. This preserves the requested format;
with fallback disabled, `AUTO` keeps yt-dlp's best native format and
`get_output_extension()` returns an empty string because it is not known yet.
Format detection describes registered loader support, not every possible codec
or profile within a container.

`Video.OGV` converts to Theora/Vorbis for vanilla Godot. WebM uses VP9/Opus
conversion (desktop also probes hardware encoders); direct WebM URLs skip
recoding. MP4/MOV requests select those output containers, with H.264/AAC when
conversion is needed. MKV requests remux into Matroska.

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

The [cross-platform example project](example/README.md) includes a runnable UI,
audio/video playback, format-fallback demonstrations, and export
presets for Windows, Linux, macOS and Android using official Godot templates.
Install the addon in the example as described there, then open
`example/project.godot` in Godot 4.4+.

### Downloading a video for vanilla Godot

Select `Video.OGV` to convert the download to Godot's native Theora/Vorbis format.
Your FFmpeg build must include `libtheora` and `libvorbis` (the bundled Android
runtime supports both).

```gdscript
if not await YtDlp.ensure_ready():
    return

var download := YtDlp.download(video_url) \
        .set_destination("user://") \
        .set_file_name("video") \
        .set_video_format(YtDlp.Video.OGV) \
        .start()
await download.download_completed
if download.get_status() != YtDlp.Download.Status.COMPLETED:
    push_error(download.get_error_message())
    return

var stream := VideoStreamTheora.new()
stream.file = "user://video.ogv"
$VideoStreamPlayer.stream = stream
$VideoStreamPlayer.play()
```

For other video formats, use a suitable playback extension, for example:

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

- `WEBM` *(preferred default; falls back to `OGV` without a registered decoder)*
- `MP4`
- `OGV` *(Theora/Vorbis `.ogv` for vanilla Godot)*
- `MOV`, `MKV`
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

##### `set_format_fallback_enabled(enabled: bool) -> Download`

Enabled by default on all supported platforms. Converts unsupported video to
OGV and unsupported audio to MP3 based on registered Godot stream support.
Disable it when downloading for an external player or retaining native formats.

##### `get_output_extension() -> String`

Returns the selected extension without a dot, such as `ogv`, `mp3`, or `ogg`.
Before `start()`, this reflects the current registered loaders; after `start()`
it reflects the fixed selection. Returns an empty string for unrestricted `AUTO`.

##### `start() -> Download`

Starts the download.

##### `stop() -> void`

Abandons a pending or running download and suppresses `download_completed`.
Also available on `Search`, where it suppresses `search_completed`.

##### `get_status() -> Status:`

Returns the status of the download

##### `get_error_message() -> String`

Returns the last download failure, or an empty string when there is no failure.
Check `get_status()` after `download_completed`; the signal also fires on failure.

## Social

- <https://bsky.app/profile/nolkaloid.bsky.social>
- <https://www.youtube.com/c/Nolkaloid>
