package org.godotengine.ytdlp.plugin;

import android.app.Activity;
import android.util.Log;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;
import org.json.JSONObject;

import java.util.concurrent.ConcurrentHashMap;

import org.godotengine.ytdlp.bridge.YtDlpBridge;

public class GodotYtDlpAndroidPlugin extends GodotPlugin {
	private static final String TAG = "GodotYtDlpAndroid";
	private static final String PLUGIN_NAME = "GodotYtDlpAndroid";

	private final ConcurrentHashMap<Long, DownloadState> downloadStates = new ConcurrentHashMap<>();
	private volatile String lastError = "";

	public GodotYtDlpAndroidPlugin(Godot godot) {
		super(godot);
		Log.i(TAG, "Plugin instance created.");
	}

	@Override
	public String getPluginName() {
		Log.d(TAG, "getPluginName() called.");
		return PLUGIN_NAME;
	}

	@UsedByGodot
	public boolean setup_backend() {
		Log.i(TAG, "setup_backend() called. isReady=" + YtDlpBridge.isReady());
		if (YtDlpBridge.isReady()) {
			Log.i(TAG, "Android yt-dlp backend already initialized.");
			lastError = "";
			return true;
		}

		Activity activity = getActivity();
		if (activity == null) {
			lastError = "Android activity is unavailable.";
			Log.e(TAG, lastError);
			return false;
		}

		boolean ready = YtDlpBridge.setup(activity.getApplicationContext());
		lastError = ready ? "" : YtDlpBridge.getLastError();
		if (ready) {
			Log.i(TAG, "Android yt-dlp backend initialized successfully.");
		} else {
			Log.e(TAG, "Android yt-dlp backend failed to initialize: " + lastError);
		}
		return ready;
	}

	@UsedByGodot
	public boolean is_ready() {
		return YtDlpBridge.isReady();
	}

	@UsedByGodot
	public String get_last_error() {
		return !lastError.isEmpty() ? lastError : YtDlpBridge.getLastError();
	}

	@UsedByGodot
	public String extract_info(String url) {
		String result = YtDlpBridge.extractInfo(url);
		lastError = YtDlpBridge.getLastError();
		return result;
	}

	@UsedByGodot
	public String search(String searchTerm, int numberOfResults) {
		String result = YtDlpBridge.search(searchTerm, numberOfResults);
		lastError = YtDlpBridge.getLastError();
		return result;
	}

	@UsedByGodot
	public boolean download_audio(String url, String destination, String fileName, String audioFormat) {
		boolean result = YtDlpBridge.downloadAudio(url, destination, fileName, audioFormat);
		lastError = result ? "" : YtDlpBridge.getLastError();
		return result;
	}

	@UsedByGodot
	public boolean download_video(String url, String destination, String fileName, String formatSelector) {
		boolean result = YtDlpBridge.downloadVideo(url, destination, fileName, formatSelector);
		lastError = result ? "" : YtDlpBridge.getLastError();
		return result;
	}

	@UsedByGodot
	public boolean start_download_audio(long requestId, String url, String destination, String fileName, String audioFormat) {
		Log.i(TAG, "start_download_audio() called. requestId=" + requestId + " url=" + url);
		return startTrackedDownload(
			requestId,
			() -> YtDlpBridge.downloadAudio(url, destination, fileName, audioFormat),
			"Failed to download audio."
		);
	}

	@UsedByGodot
	public boolean start_download_video(long requestId, String url, String destination, String fileName, String formatSelector) {
		Log.i(TAG, "start_download_video() called. requestId=" + requestId + " url=" + url);
		return startTrackedDownload(
			requestId,
			() -> YtDlpBridge.downloadVideo(url, destination, fileName, formatSelector),
			"Failed to download video."
		);
	}

	@UsedByGodot
	public String get_download_state(long requestId) {
		DownloadState state = downloadStates.get(requestId);
		if (state == null) {
			return "{\"status\":\"missing\",\"progress\":0.0,\"error\":\"\"}";
		}

		try {
			JSONObject payload = new JSONObject();
			payload.put("status", state.status);
			payload.put("progress", state.progress);
			payload.put("error", state.error);
			return payload.toString();
		} catch (Exception exception) {
			return "{\"status\":\"failed\",\"progress\":0.0,\"error\":\"Failed to encode download state.\"}";
		}
	}

	@UsedByGodot
	public void clear_download_state(long requestId) {
		downloadStates.remove(requestId);
	}

	private boolean ensureReady() {
		return YtDlpBridge.isReady() || setup_backend();
	}

	private boolean startTrackedDownload(long requestId, DownloadAction action, String failureFallback) {
		if (!ensureReady()) {
			lastError = get_last_error();
			Log.e(TAG, "Tracked download aborted: backend not ready. " + lastError);
			return false;
		}

		DownloadState state = new DownloadState();
		state.status = "downloading";
		state.progress = 0.0;
		state.error = "";
		downloadStates.put(requestId, state);

		Thread worker = new Thread(() -> {
			try {
				boolean succeeded = action.run();
				if (succeeded) {
					state.status = "completed";
					state.error = "";
					state.progress = 100.0;
					lastError = "";
					Log.i(TAG, "Tracked download completed. requestId=" + requestId);
				} else {
					String message = YtDlpBridge.getLastError();
					if (message == null || message.isEmpty()) {
						message = failureFallback;
					}
					state.status = "failed";
					state.error = message;
					lastError = message;
					Log.e(TAG, "Tracked download failed. requestId=" + requestId + " error=" + message);
				}
			} catch (Exception exception) {
				String message = exception.getMessage() != null ? exception.getMessage() : failureFallback;
				state.status = "failed";
				state.error = message;
				lastError = message;
				Log.e(TAG, "Tracked download crashed. requestId=" + requestId, exception);
			}
		});
		worker.setName("GodotYtDlpAndroidDownload-" + requestId);
		worker.start();
		return true;
	}

	private interface DownloadAction {
		boolean run();
	}

	private static final class DownloadState {
		volatile String status;
		volatile double progress;
		volatile String error;
	}
}