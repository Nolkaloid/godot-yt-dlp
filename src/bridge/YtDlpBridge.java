package org.godotengine.ytdlp.bridge;

import android.content.Context;
import android.util.Log;

import com.yausername.ffmpeg.FFmpeg;
import com.yausername.youtubedl_android.YoutubeDL;
import com.yausername.youtubedl_android.YoutubeDLRequest;
import com.yausername.youtubedl_android.YoutubeDLResponse;
import com.yausername.youtubedl_android.mapper.VideoInfo;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.lang.reflect.Method;
import java.util.Locale;

public final class YtDlpBridge {
	private static final String TAG = "YtDlpBridge";

	private static boolean isYoutubeUrl(String url) {
		String normalized = url == null ? "" : url.toLowerCase(Locale.ROOT);
		return normalized.contains("youtube.com/") || normalized.contains("youtu.be/");
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

	private static boolean isReady = false;
	private static String lastError = "";

	private YtDlpBridge() {
	}

	public static boolean setup(Context context) {
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
			Context appContext = context.getApplicationContext();
			YoutubeDL.getInstance().init(appContext);
			// Keep Android on the nightly extractor channel for current site fixes.
			YoutubeDL.UpdateStatus updateStatus = YoutubeDL.getInstance().updateYoutubeDL(
				appContext,
				YoutubeDL.UpdateChannel._NIGHTLY
			);
			Log.i(TAG, "yt-dlp nightly update status: " + updateStatus);
			FFmpeg.getInstance().init(appContext);
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
			YoutubeDLRequest request = new YoutubeDLRequest(url);
			applyYoutubeWorkarounds(request, false);
			VideoInfo info = YoutubeDL.getInstance().getInfo(request);

			JSONObject result = new JSONObject();
			result.put("title", invokeString(info, "getTitle"));
			result.put("duration", invokeInt(info, "getDuration"));

			String webpageUrl = invokeString(info, "getWebpageUrl");
			String originalUrl = invokeString(info, "getOriginalUrl");
			String resolvedUrl = invokeString(info, "getUrl");

			if (webpageUrl.isEmpty()) {
				webpageUrl = !originalUrl.isEmpty() ? originalUrl : url;
			}
			if (originalUrl.isEmpty()) {
				originalUrl = !webpageUrl.isEmpty() ? webpageUrl : url;
			}
			if (resolvedUrl.isEmpty()) {
				resolvedUrl = !webpageUrl.isEmpty() ? webpageUrl : url;
			}

			result.put("webpage_url", webpageUrl);
			result.put("original_url", originalUrl);
			result.put("url", resolvedUrl);

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
			YoutubeDLRequest request = new YoutubeDLRequest("ytsearch" + numberOfResults + ":" + searchTerm);
			applyYoutubeWorkarounds(request, false);
			request.addOption("--print-json");
			request.addOption("--flat-playlist");

			YoutubeDLResponse response = YoutubeDL.getInstance().execute(request);
			String output = invokeString(response, "getOut");
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
			if (!destinationDir.exists()) {
				destinationDir.mkdirs();
			}

			YoutubeDLRequest request = new YoutubeDLRequest(url);
			applyYoutubeWorkarounds(request, audioOnly);

			if (audioOnly) {
				String normalizedAudioFormat = formatSpec == null || formatSpec.trim().isEmpty()
					? "mp3"
					: formatSpec.trim().toLowerCase();
				if ("auto".equals(normalizedAudioFormat)) {
					request.addOption("--format", "bestaudio/best");
					request.addOption("-x");
					request.addOption("--audio-format", "best");
				} else {
					request.addOption("-x");
					request.addOption("--audio-format", normalizedAudioFormat);
				}
			} else {
				String requestedFormat = formatSpec == null ? "" : formatSpec.trim().toLowerCase();
				boolean nativeFormat = "auto".equals(requestedFormat);
				String normalizedFormatSelector = requestedFormat.isEmpty() || nativeFormat
					? (isYoutubeUrl(url)
						? "bestvideo[vcodec^=vp9]+bestaudio[acodec^=opus]/bestvideo[vcodec^=vp8]+bestaudio[acodec^=opus]/bestvideo+bestaudio"
						: "bestvideo+bestaudio/best")
					: requestedFormat;
				request.addOption("-f", normalizedFormatSelector);
				if (!nativeFormat && isYoutubeUrl(url)) {
					request.addOption("--recode-video", "webm");
					request.addOption("--postprocessor-args", "VideoConvertor+ffmpeg_o:-c:v libvpx-vp9 -b:v 0 -crf 32 -deadline good -cpu-used 4 -c:a libopus");
					request.addOption("--no-keep-video");
				}
				if (!nativeFormat && !isYoutubeUrl(url) && !isDirectWebmUrl(url)) {
					request.addOption("--recode-video", "webm");
					request.addOption("--postprocessor-args", "VideoConvertor+ffmpeg_o:-c:v libvpx-vp9 -b:v 0 -crf 32 -deadline good -cpu-used 4 -c:a libopus");
					request.addOption("--no-keep-video");
				}

				String mergeOutputFormat = inferMergeOutputFormat(normalizedFormatSelector);
				if (!mergeOutputFormat.isEmpty()) {
					request.addOption("--merge-output-format", mergeOutputFormat);
				}
			}

			request.addOption("--no-continue");
			request.addOption("-o", new File(destinationDir, fileName + ".%(ext)s").getAbsolutePath());

			YoutubeDL.getInstance().execute(request);
			lastError = "";
			Log.i(TAG, (audioOnly ? "downloadAudio()" : "downloadVideo()") + " completed successfully.");
			return true;
		} catch (Exception exception) {
			lastError = exception.getMessage() != null
				? exception.getMessage()
				: (audioOnly ? "Failed to download audio." : "Failed to download video.");
			Log.e(TAG, (audioOnly ? "downloadAudio()" : "downloadVideo()") + " failed.", exception);
			return false;
		}
	}

	private static String inferMergeOutputFormat(String formatSelector) {
		String normalized = formatSelector == null ? "" : formatSelector.toLowerCase();
		if (normalized.contains("ext=mp4") || normalized.contains("m4a") || normalized.contains("mp4")) {
			return "mp4";
		}
		if (normalized.contains("ext=webm") || normalized.contains("webm")) {
			return "webm";
		}
		return "";
	}

	private static String invokeString(Object value, String methodName) {
		try {
			Method method = value.getClass().getMethod(methodName);
			Object result = method.invoke(value);
			return result != null ? String.valueOf(result) : "";
		} catch (Exception ignored) {
			return "";
		}
	}

	private static int invokeInt(Object value, String methodName) {
		try {
			Method method = value.getClass().getMethod(methodName);
			Object result = method.invoke(value);
			if (result instanceof Number) {
				return ((Number) result).intValue();
			}
		} catch (Exception ignored) {
		}
		return 0;
	}

	private static void applyYoutubeWorkarounds(YoutubeDLRequest request, boolean audioOnly) {
		request.addOption("--no-update");
		request.addOption("--extractor-args", "youtube:player_client=android_vr,tv,tv_downgraded");
		if (audioOnly) {
			request.addOption("-f", "140/251/250/ba/b");
		}
	}
}
