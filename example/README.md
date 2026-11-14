# Cross-platform example

A small **Godot 4.4+** project for Windows, Linux, macOS and Android. Use an
official Godot editor and the matching official export templates. No custom
engine, custom templates, account credentials or external playback extension
is required.

## Run

Create `example/addons/godot-yt-dlp/` and copy these files and directories from
the repository root into it:

- `plugin.cfg`
- `godot_yt_dlp.gd`
- `LICENSE`
- `src/`
- `bin/`

Import `example/project.godot` in the official Godot 4.4+ project manager.
The addon and autoload are already enabled in the project settings. No Python
script, test runner or other helper is needed.

The local addon copy is ignored by Git so the repository keeps a single source
of truth. Refresh that copy after changing the plugin or rebuilding the AARs.

1. Run the scene and press **Setup runtime**. First setup downloads tools and
   needs internet access; Windows also downloads FFmpeg.
2. Enter a short public HTTP/HTTPS media URL.
3. Choose **Video** or **Audio**, then a requested format. The output label
   shows what this Godot build will actually receive.
4. Leave **Use compatible formats** checked to exercise the automatic
   Theora/Vorbis video or MP3 audio fallback. Press **Download and play**.
5. The log displays errors or the saved file path. Use **Stop playback** and
   **Play again** to test playback controls.

Only pressing Setup or Download starts network work. Downloads are stored in
`user://downloads/` and kept between runs. No resolution cap is added. Stop
playback stops the player, not an in-progress download; wait for downloads and
conversion to finish before closing the example.

On desktop, install a supported JavaScript runtime for YouTube, such as
[Deno 2.3 or newer](https://github.com/yt-dlp/yt-dlp/wiki/EJS), on `PATH`.
Linux and macOS also need `ffmpeg` and `ffprobe` on `PATH`, with `libtheora` and
`libvorbis` encoding support for vanilla video. Android packages its Python,
QuickJS and FFmpeg dependencies automatically through the enabled plugin.

## Export

Install the **official export templates matching your editor version** through
Godot's Export Template Manager. Open **Project → Export** and select one of the
four included presets. No preset specifies a custom engine template.
Create the output directories below, or choose an export path in the editor.

| Preset | Additional setup | Output |
| --- | --- | --- |
| Windows | Official templates; desktop runtime requirements above | `exports/windows/yt-dlp-example.exe` |
| Linux | Official templates; system FFmpeg and JavaScript runtime | `exports/linux/yt-dlp-example.x86_64` |
| macOS | Official templates; system FFmpeg and JavaScript runtime | `exports/macos/yt-dlp-example.zip` |
| Android | JDK 17, Android SDK, and **Project → Install Android Build Template** from the official templates | `exports/android/yt-dlp-example.apk` |

The Android preset enables Gradle, internet access, ARM64 and minimum API 24.
Keep the addon enabled when exporting. Configure Java/SDK paths in Godot's
[Android editor settings](https://docs.godotengine.org/en/4.4/tutorials/export/exporting_for_android.html).
Use a debug export for local device testing. Signing/notarization credentials
are deliberately absent; configure your own for distribution. macOS exports
are unsigned local-test builds.

Web and iOS are not supported by this plugin; no presets are supplied for them.

## Test the plugin

Repeat these checks on each target platform using a short public clip:

| Action | Expected result in vanilla Godot |
| --- | --- |
| Setup runtime | Ready, or a visible setup failure/timeout |
| Video: WEBM, compatibility enabled | Output `.ogv`; completed video plays with audio |
| Audio: OPUS, compatibility enabled | Output `.mp3`; completed audio plays |
| Video: OGV / Audio: MP3 explicitly | Native format remains selected |
| Stop playback, then Play again | Playback stops and restarts |
| Invalid URL | Input rejected, or a download error is shown without playing an old file |
| Compatibility disabled, AUTO | Native output retained; playback may require an extension |

An installed extension can register additional stream loaders. The same UI
then retains supported newer formats and loads them through `ResourceLoader`.
The example never refers to a particular custom-engine stream class.

The demo uses `ensure_ready()`, `get_output_extension()`,
`set_format_fallback_enabled()`, `download_completed`, `get_status()` and
`get_error_message()`. See `main.gd` for the complete flow, including raw
MP3/Vorbis/WAV loading and `VideoStreamTheora` playback of downloaded OGV files.
