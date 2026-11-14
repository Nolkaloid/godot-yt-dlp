package org.godotengine.ytdlp.bridge;

import android.content.Context;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.IOException;
import java.net.URI;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;

public final class YtDlpBridge {
	private static final String TAG = "YtDlpBridge";

	private static boolean isYoutubeUrl(String url) {
		try {
			String host = URI.create(url.contains("://") ? url : "https://" + url).getHost();
			if (host == null) {
				return false;
			}
			host = host.toLowerCase(Locale.ROOT);
			return host.equals("youtube.com") || host.endsWith(".youtube.com")
				|| host.equals("youtu.be") || host.endsWith(".youtu.be");
		} catch (IllegalArgumentException | NullPointerException ignored) {
			return false;
		}
	}

	private static boolean isDirectWebmUrl(String url) {
		if (isYoutubeUrl(url) || url == null) {
			return false;
		}
		String path = url.toLowerCase(Locale.ROOT);
		int queryIndex = path.indexOf('?');
		if (queryIndex >= 0) {
			path = path.substring(0, queryIndex);
		}
		int fragmentIndex = path.indexOf('#');
		if (fragmentIndex >= 0) {
			path = path.substring(0, fragmentIndex);
		}
		return path.endsWith(".webm");
	}

	private static volatile boolean isReady = false;
	private static UpstreamYtDlp runtime;
	private static volatile String lastError = "";

	private YtDlpBridge() {
	}

	public static synchronized boolean setup(Context context) {
		Log.i(TAG, "setup() called. isReady=" + isReady);
		if (isReady) {
			return true;
		}
		if (context == null) {
			lastError = "Android context is unavailable.";
			Log.e(TAG, lastError);
			return false;
		}

		try {
			runtime = new UpstreamYtDlp(context);
			runtime.setup(context);
			isReady = true;
			lastError = "";
			Log.i(TAG, "setup() completed successfully.");
			return true;
		} catch (Exception exception) {
			lastError = exception.getMessage() != null
				? exception.getMessage()
				: "Failed to initialize Android yt-dlp bridge.";
			isReady = false;
			Log.e(TAG, "setup() failed.", exception);
			return false;
		}
	}

	public static boolean isReady() {
		return isReady;
	}

	public static String getLastError() {
		return lastError;
	}

	public static String extractInfo(String url) {
		Log.i(TAG, "extractInfo() called for URL: " + url);
		if (!isReady) {
			lastError = "Android yt-dlp bridge is not ready.";
			Log.e(TAG, lastError);
			return "{}";
		}

		try {
			List<String> request = createRequest(url);
			add(request, "--dump-single-json");
			add(request, "--no-playlist");
			add(request, "--skip-download");
			String output = runtime.execute(request);
			// Preserve yt-dlp's formats and per-stream HTTP headers, as on desktop.
			// A resolved URL alone is not sufficient for every media request.
			JSONObject result = new JSONObject(output);
			// Keep the legacy URL fallback for callers which only display/open a
			// watch link. Separate audio/video media URLs live in requested_formats.
			if (result.isNull("webpage_url") || result.optString("webpage_url").isEmpty()) {
				result.put("webpage_url", url);
			}
			if (result.isNull("original_url") || result.optString("original_url").isEmpty()) {
				result.put("original_url", result.getString("webpage_url"));
			}
			if (result.isNull("url") || result.optString("url").isEmpty()) {
				result.put("url", result.getString("webpage_url"));
			}
			lastError = "";
			return result.toString();
		} catch (Exception exception) {
			lastError = exception.getMessage() != null
				? exception.getMessage()
				: "Failed to extract stream info.";
			Log.e(TAG, "extractInfo() failed.", exception);
			return "{}";
		}
	}

	public static String search(String searchTerm, int numberOfResults) {
		Log.i(TAG, "search() called for term=" + searchTerm + " results=" + numberOfResults);
		if (!isReady) {
			lastError = "Android yt-dlp bridge is not ready.";
			Log.e(TAG, lastError);
			return "[]";
		}

		try {
			List<String> request = createRequest("ytsearch" + numberOfResults + ":" + searchTerm);
			add(request, "--print-json");
			add(request, "--flat-playlist");

			String output = runtime.execute(request);
			JSONArray results = new JSONArray();

			for (String line : output.split("\\r?\\n")) {
				if (line == null || line.trim().isEmpty()) {
					continue;
				}

				JSONObject source = new JSONObject(line);
				JSONObject entry = new JSONObject();
				entry.put("title", source.optString("title", ""));
				entry.put("id", source.optString("id", ""));
				entry.put("url", source.optString("url", ""));
				entry.put("webpage_url", source.optString("webpage_url", source.optString("url", "")));
				results.put(entry);
			}

			lastError = "";
			return results.toString();
		} catch (Exception exception) {
			lastError = exception.getMessage() != null
				? exception.getMessage()
				: "Failed to search yt-dlp.";
			Log.e(TAG, "search() failed.", exception);
			return "[]";
		}
	}

	public static boolean downloadAudio(String url, String destination, String fileName, String audioFormat) {
		Log.i(TAG, "downloadAudio() called for URL=" + url + " destination=" + destination);
		return downloadMedia(url, destination, fileName, true, audioFormat);
	}

	public static boolean downloadVideo(String url, String destination, String fileName, String formatSelector) {
		Log.i(TAG, "downloadVideo() called for URL=" + url + " destination=" + destination);
		return downloadMedia(url, destination, fileName, false, formatSelector);
	}

	private static boolean downloadMedia(String url, String destination, String fileName, boolean audioOnly, String formatSpec) {
		if (!isReady) {
			lastError = "Android yt-dlp bridge is not ready.";
			Log.e(TAG, lastError);
			return false;
		}

		try {
			File destinationDir = new File(destination);
			if (!destinationDir.isDirectory() && !destinationDir.mkdirs()) {
				throw new IOException("Cannot create download directory: " + destinationDir);
			}

			for (int attempt = 0; ; attempt++) {
				// Build a fresh request and re-extract the original URL after a CDN 403.
				// Keep the requested format and destination, as on desktop.
				List<String> request = createDownloadRequest(url, destinationDir, fileName, audioOnly, formatSpec);
				try {
					runtime.execute(request);
					break;
				} catch (UpstreamYtDlp.ProcessException exception) {
					if (attempt != 0 || !isYoutubeUrl(url) || exception.getMessage() == null
						|| !exception.getMessage().contains("HTTP Error 403")) {
						throw exception;
					}
					Log.i(TAG, "YouTube returned HTTP 403; re-extracting once.");
					Thread.sleep(500);
				}
			}
			if (!audioOnly && "ogv".equalsIgnoreCase(formatSpec)) {
				// yt-dlp names its Ogg conversion .ogg; Godot imports video as .ogv.
				File converted = new File(destinationDir, fileName + ".ogg");
				if (!converted.isFile() || !converted.renameTo(new File(destinationDir, fileName + ".ogv"))) {
					throw new IOException("Cannot publish the converted Ogg Theora video.");
				}
			}
			lastError = "";
			Log.i(TAG, (audioOnly ? "downloadAudio()" : "downloadVideo()") + " completed successfully.");
			return true;
		} catch (Exception exception) {
			if (exception instanceof InterruptedException) {
				Thread.currentThread().interrupt();
			}
			lastError = exception.getMessage() != null
				? exception.getMessage()
				: (audioOnly ? "Failed to download audio." : "Failed to download video.");
			Log.e(TAG, (audioOnly ? "downloadAudio()" : "downloadVideo()") + " failed.", exception);
			return false;
		}
	}

	private static List<String> createDownloadRequest(String url, File destinationDir, String fileName, boolean audioOnly, String formatSpec) {
		List<String> request = createRequest(url);

		if (audioOnly) {
			String normalizedAudioFormat = formatSpec == null || formatSpec.trim().isEmpty()
				? "mp3"
				: formatSpec.trim().toLowerCase(Locale.ROOT);
			if ("auto".equals(normalizedAudioFormat)) {
				add(request, "--format", "bestaudio/best");
				add(request, "-x");
				add(request, "--audio-format", "best");
			} else {
				add(request, "-x");
				add(request, "--audio-format", normalizedAudioFormat);
			}
		} else if ("ogv".equalsIgnoreCase(formatSpec)) {
			add(request, "-f", "bestvideo+bestaudio/best", "--recode-video", "ogg",
				"--postprocessor-args", "VideoConvertor+ffmpeg_o:-c:v libtheora -q:v 6 -g:v 64 -pix_fmt yuv420p -c:a libvorbis -q:a 6 -ac 2",
				"--no-keep-video");
		} else if ("mp4".equalsIgnoreCase(formatSpec) || "mov".equalsIgnoreCase(formatSpec)) {
			add(request, "-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best",
				"--recode-video", formatSpec.toLowerCase(Locale.ROOT),
				"--postprocessor-args", "VideoConvertor+ffmpeg_o:-c:v libx264 -crf 23 -pix_fmt yuv420p -c:a aac",
				"--no-keep-video");
		} else if ("mkv".equalsIgnoreCase(formatSpec)) {
			add(request, "-f", "bestvideo+bestaudio/best", "--remux-video", "mkv");
		} else {
			String requestedFormat = formatSpec == null ? "" : formatSpec.trim().toLowerCase(Locale.ROOT);
			boolean nativeFormat = "auto".equals(requestedFormat);
			String normalizedFormatSelector = requestedFormat.isEmpty() || nativeFormat || "webm".equals(requestedFormat)
				? (!nativeFormat && isYoutubeUrl(url)
					? "bestvideo[vcodec^=vp9]+bestaudio[acodec^=opus]/bestvideo[vcodec^=vp8]+bestaudio[acodec^=opus]/bestvideo+bestaudio"
					: "bestvideo+bestaudio/best")
				: requestedFormat;
			add(request, "-f", normalizedFormatSelector);
			if (!nativeFormat && isYoutubeUrl(url)) {
				add(request, "--recode-video", "webm");
				add(request, "--postprocessor-args", "VideoConvertor+ffmpeg_o:-c:v libvpx-vp9 -b:v 0 -crf 32 -deadline good -cpu-used 4 -c:a libopus");
				add(request, "--no-keep-video");
			}
			if (!nativeFormat && !isYoutubeUrl(url) && !isDirectWebmUrl(url)) {
				add(request, "--recode-video", "webm");
				add(request, "--postprocessor-args", "VideoConvertor+ffmpeg_o:-c:v libvpx-vp9 -b:v 0 -crf 32 -deadline good -cpu-used 4 -c:a libopus");
				add(request, "--no-keep-video");
			}

			String mergeOutputFormat = inferMergeOutputFormat(normalizedFormatSelector);
			if (!mergeOutputFormat.isEmpty()) {
				add(request, "--merge-output-format", mergeOutputFormat);
			}
		}

		add(request, "--no-continue");
		add(request, "-o", new File(destinationDir, fileName + ".%(ext)s").getAbsolutePath());

		return request;
	}

	private static String inferMergeOutputFormat(String formatSelector) {
		String normalized = formatSelector == null ? "" : formatSelector.toLowerCase(Locale.ROOT);
		if (normalized.contains("ext=mp4") || normalized.contains("m4a") || normalized.contains("mp4")) {
			return "mp4";
		}
		if (normalized.contains("ext=webm") || normalized.contains("webm")) {
			return "webm";
		}
		return "";
	}

	private static List<String> createRequest(String url) {
		// Client selection, visitor headers and EJS challenges belong to the
		// official upstream extractor, just as they do on desktop.
		return new ArrayList<>(Arrays.asList(url));
	}

	private static void add(List<String> request, String... arguments) {
		request.addAll(Arrays.asList(arguments));
	}
}
