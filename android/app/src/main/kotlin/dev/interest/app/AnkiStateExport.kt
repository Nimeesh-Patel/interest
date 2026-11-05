package dev.interest.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Saves one explicit capture through SAF; no vault path or retained URI grant. */
class AnkiStateExport(private val activity: Activity) {
    private data class Pending(val result: MethodChannel.Result, val bytes: ByteArray)
    private var pending: Pending? = null
    private var channel: MethodChannel? = null

    companion object {
        const val CHANNEL = "dev.interest.app/anki-state-export"
        private const val REQUEST_CODE = 14021
        private const val MAX_BYTES = 8 * 1024 * 1024
    }

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method != "save") return@setMethodCallHandler result.notImplemented()
                if (pending != null) return@setMethodCallHandler result.error(
                    "EXPORT_PENDING", "Another capture export is pending", null)
                val bytes = call.argument<ByteArray>("bytes")
                val name = call.argument<String>("fileName")
                if (bytes == null || bytes.isEmpty() || bytes.size > MAX_BYTES ||
                    name.isNullOrBlank() || !name.endsWith(".json") ||
                    name.contains('/') || name.contains('\\')) {
                    return@setMethodCallHandler result.error(
                        "EXPORT_ARGUMENT", "Export needs a JSON filename and nonempty bytes up to 8 MiB", null)
                }
                val request = Pending(result, bytes.copyOf())
                pending = request
                try {
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/json"
                        putExtra(Intent.EXTRA_TITLE, name)
                    }
                    @Suppress("DEPRECATION")
                    activity.startActivityForResult(intent, REQUEST_CODE)
                } catch (error: Exception) {
                    finish(request) { it.error("EXPORT_START", error.message, null) }
                }
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val request = pending ?: return true
        if (resultCode == Activity.RESULT_CANCELED) {
            finish(request) { it.success(mapOf("status" to "cancelled", "uri" to null)) }
            return true
        }
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || uri.scheme != "content") {
            finish(request) { it.error("EXPORT_RESULT", "Save chooser returned no document URI", null) }
            return true
        }
        Thread {
            try {
                val stream = activity.contentResolver.openOutputStream(uri, "wt")
                    ?: throw IllegalStateException("Document provider returned no output stream")
                stream.use { it.write(request.bytes); it.flush() }
            } catch (error: Exception) {
                finish(request) { it.error("EXPORT_WRITE",
                    "${error.message}; an incomplete document may remain at the chosen location",
                    mapOf("uri" to uri.toString())) }
                return@Thread
            }
            try {
                if (!matches(uri, request.bytes)) {
                    finish(request) { it.error("EXPORT_VERIFY",
                        "Written document differs from the capture; do not use this export",
                        mapOf("uri" to uri.toString())) }
                } else {
                    finish(request) { it.success(mapOf("status" to "verified", "uri" to uri.toString())) }
                }
            } catch (error: Exception) {
                finish(request) { it.success(mapOf("status" to "written_unverified",
                    "uri" to uri.toString(), "error" to error.message)) }
            }
        }.start()
        return true
    }

    private fun matches(uri: Uri, expected: ByteArray): Boolean {
        val input = activity.contentResolver.openInputStream(uri)
            ?: throw IllegalStateException("Document provider returned no verification stream")
        input.use {
            val buffer = ByteArray(8192)
            var position = 0
            while (true) {
                val size = it.read(buffer)
                if (size < 0) return position == expected.size
                if (size == 0) throw IllegalStateException("Verification stream made no progress")
                if (position + size > expected.size) return false
                for (index in 0 until size) {
                    if (buffer[index] != expected[position + index]) return false
                }
                position += size
            }
        }
    }

    private fun finish(request: Pending, callback: (MethodChannel.Result) -> Unit) {
        activity.runOnUiThread {
            if (pending === request) {
                pending = null
                callback(request.result)
            }
        }
    }

    fun dispose() {
        channel?.setMethodCallHandler(null)
        pending?.let { request ->
            pending = null
            request.result.error("EXPORT_INTERRUPTED",
                "Activity closed before export verification; any chosen document is unverified", null)
        }
    }
}
