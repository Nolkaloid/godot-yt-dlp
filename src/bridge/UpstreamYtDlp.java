package org.godotengine.ytdlp.bridge;

import android.content.Context;
import android.util.AtomicFile;
import android.util.Log;

import com.yausername.ffmpeg.FFmpeg;
import com.yausername.youtubedl_android.YoutubeDL;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.zip.ZipFile;

/** Official desktop yt-dlp/EJS code, executed by the packaged Android runtime. */
final class UpstreamYtDlp {
	private static final String RELEASE_API = "https://api.github.com/repos/yt-dlp/yt-dlp-nightly-builds/releases/latest";
	private final File nativeDirectory;
	private final File packages;
	private final File archive;
	private final File cacheDirectory;

	UpstreamYtDlp(Context context) {
		Context appContext = context.getApplicationContext();
		nativeDirectory = new File(appContext.getApplicationInfo().nativeLibraryDir);
		packages = new File(appContext.getNoBackupFilesDir(), "youtubedl-android/packages");
		archive = new File(appContext.getNoBackupFilesDir(), "godot-yt-dlp/yt-dlp.zip");
		cacheDirectory = appContext.getCacheDir();
	}

	void setup(Context context) throws Exception {
		for (String name : Arrays.asList("libpython.so", "libqjs.so", "libffmpeg.so")) {
			File executable = new File(nativeDirectory, name);
			if (!executable.isFile() || !executable.canExecute()) {
				throw new IOException("Missing executable Android runtime: " + name
					+ ". Re-export with the matching runtime dependencies and extractNativeLibs enabled.");
			}
		}
		// Use the Android libraries only to unpack Python and FFmpeg. Their
		// bundled extractor, updater and request execution path are not used.
		YoutubeDL.getInstance().init(context.getApplicationContext());
		FFmpeg.getInstance().init(context.getApplicationContext());
		if (!archive.getParentFile().isDirectory() && !archive.getParentFile().mkdirs()) {
			throw new IOException("Cannot create the upstream yt-dlp directory.");
		}
		AtomicFile installed = new AtomicFile(archive);
		if (archive.exists() || new File(archive.getPath() + ".bak").exists()) {
			try (InputStream ignored = installed.openRead()) {
				// Recover the last complete archive after an interrupted update.
			}
		}
		try {
			update(installed);
		} catch (Exception exception) {
			if (!validArchive(archive)) {
				throw exception;
			}
			Log.w("UpstreamYtDlp", "Update unavailable; keeping the installed upstream archive.", exception);
		}
		// Check the actual Python/archive combination before advertising readiness.
		execute(Arrays.asList("--version"));
	}

	private void update(AtomicFile installed) throws Exception {
		JSONObject release = new JSONObject(new String(fetch(RELEASE_API, 1024 * 1024), StandardCharsets.UTF_8));
		String tag = release.getString("tag_name");
		if (!tag.matches("[0-9]+(?:\\.[0-9]+)+")) {
			throw new IOException("Unexpected upstream yt-dlp release tag.");
		}
		String base = "https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/download/" + tag + "/";
		String sums = new String(fetch(base + "SHA2-256SUMS", 1024 * 1024), StandardCharsets.UTF_8);
		String expected = "";
		for (String line : sums.split("\\r?\\n")) {
			String[] parts = line.trim().split("\\s+");
			if (parts.length == 2 && (parts[1].equals("yt-dlp") || parts[1].equals("*yt-dlp"))) {
				expected = parts[0];
			}
		}
		if (!expected.matches("[a-fA-F0-9]{64}")) {
			throw new IOException("Upstream yt-dlp checksum is missing.");
		}
		if (archive.isFile() && validArchive(archive)) {
			try (InputStream input = new FileInputStream(archive)) {
				if (expected.equalsIgnoreCase(sha256(read(input, 32 * 1024 * 1024)))) {
					return;
				}
			}
		}
		byte[] bytes = fetch(base + "yt-dlp", 32 * 1024 * 1024);
		if (!expected.equalsIgnoreCase(sha256(bytes))) {
			throw new IOException("Upstream yt-dlp checksum does not match.");
		}
		// Validate before publishing so an interrupted/invalid update cannot
		// replace a working installation. EJS must travel with its yt-dlp version.
		File staging = new File(archive.getParentFile(), "yt-dlp.download");
		try {
			try (FileOutputStream stream = new FileOutputStream(staging)) {
				stream.write(bytes);
			}
			if (!validArchive(staging)) {
				throw new IOException("The upstream archive is missing yt-dlp or its matching EJS scripts.");
			}
			// Nightlies may raise the minimum Python version. Validate against
			// the packaged interpreter before replacing a working installation.
			execute(staging, Arrays.asList("--version"));
			FileOutputStream stream = null;
			try {
				stream = installed.startWrite();
				stream.write(bytes);
				installed.finishWrite(stream);
			} catch (IOException exception) {
				installed.failWrite(stream);
				throw exception;
			}
		} finally {
			if (staging.exists() && !staging.delete()) {
				Log.w("UpstreamYtDlp", "Could not remove the update staging file.");
			}
		}
	}

	private static boolean validArchive(File file) {
		try (ZipFile zip = new ZipFile(file)) {
			return zip.getEntry("__main__.py") != null
				&& zip.getEntry("yt_dlp/version.py") != null
				&& zip.getEntry("yt_dlp_ejs/yt/solver/lib.min.js") != null
				&& zip.getEntry("yt_dlp_ejs/yt/solver/core.min.js") != null;
		} catch (IOException exception) {
			return false;
		}
	}

	private static String sha256(byte[] bytes) throws Exception {
		StringBuilder hex = new StringBuilder();
		for (byte value : MessageDigest.getInstance("SHA-256").digest(bytes)) {
			hex.append(String.format(java.util.Locale.ROOT, "%02x", value & 255));
		}
		return hex.toString();
	}

	private static byte[] fetch(String url, int limit) throws IOException {
		HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
		connection.setConnectTimeout(15000);
		connection.setReadTimeout(30000);
		connection.setRequestProperty("User-Agent", "godot-yt-dlp");
		try {
			if (connection.getResponseCode() != 200) {
				throw new IOException("Upstream yt-dlp update returned HTTP " + connection.getResponseCode());
			}
			try (InputStream stream = connection.getInputStream()) {
				return read(stream, limit);
			}
		} finally {
			connection.disconnect();
		}
	}

	private static byte[] read(InputStream stream, int limit) throws IOException {
		ByteArrayOutputStream output = new ByteArrayOutputStream();
		byte[] buffer = new byte[8192];
		int count;
		while ((count = stream.read(buffer)) != -1) {
			if (count > limit - output.size()) {
				throw new IOException("yt-dlp response exceeded the capture limit.");
			}
			output.write(buffer, 0, count);
		}
		return output.toByteArray();
	}

	String execute(List<String> arguments) throws IOException, InterruptedException {
		return execute(archive, arguments);
	}

	private String execute(File program, List<String> arguments) throws IOException, InterruptedException {
		List<String> command = new ArrayList<>(Arrays.asList(
			new File(nativeDirectory, "libpython.so").getAbsolutePath(), program.getAbsolutePath(),
			"--ignore-config", "--no-plugin-dirs", "--no-cache-dir", "--no-update", "--no-colors",
			"--no-js-runtimes", "--js-runtimes", "quickjs:" + new File(nativeDirectory, "libqjs.so"),
			"--ffmpeg-location", new File(nativeDirectory, "libffmpeg.so").getAbsolutePath()));
		command.addAll(arguments);
		ProcessBuilder builder = new ProcessBuilder(command);
		Map<String, String> env = builder.environment();
		File python = new File(packages, "python/usr");
		env.put("LD_LIBRARY_PATH", new File(python, "lib") + ":" + new File(packages, "ffmpeg/usr/lib"));
		env.put("SSL_CERT_FILE", new File(python, "etc/tls/cert.pem").getAbsolutePath());
		env.put("PYTHONHOME", python.getAbsolutePath());
		env.put("HOME", python.getAbsolutePath());
		env.put("TMPDIR", cacheDirectory.getAbsolutePath());
		env.put("PATH", env.get("PATH") + ":" + nativeDirectory);
		Process process = builder.start();
		process.getOutputStream().close();
		Capture out = new Capture(process.getInputStream(), process);
		Capture err = new Capture(process.getErrorStream(), process);
		out.start();
		err.start();
		try {
			int code = process.waitFor();
			out.join();
			err.join();
			if (out.error != null) throw out.error;
			if (err.error != null) throw err.error;
			if (code != 0) throw new ProcessException(code, err.text);
			return out.text;
		} finally {
			process.destroy();
		}
	}

	static final class ProcessException extends IOException {
		ProcessException(int code, String error) {
			super("yt-dlp exited with code " + code + ".\n" + error);
		}
	}

	private static final class Capture extends Thread {
		private final InputStream stream;
		private final Process process;
		String text = "";
		IOException error;

		Capture(InputStream stream, Process process) {
			this.stream = stream;
			this.process = process;
		}

		@Override public void run() {
			try (InputStream input = stream) {
				text = new String(read(input, 16 * 1024 * 1024), StandardCharsets.UTF_8);
			} catch (IOException exception) {
				error = exception;
				process.destroy();
			}
		}
	}
}
