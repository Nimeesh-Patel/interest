package com.nimee.people_tracker

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.core.app.ActivityCompat
import com.ichi2.anki.api.AddContentApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val shareChannelName = "people.nimee/share"
    private val ankiChannelName = "com.nimeesh.interest/ankidroid"
    private var pendingShareUrl: String? = null
    private var pendingAnkiPermissionResult: MethodChannel.Result? = null

    companion object {
        private const val ANKI_PERMISSION_REQUEST_CODE = 1001
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingShareUrl = extractShareUrl(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val url = extractShareUrl(intent) ?: return
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, shareChannelName).invokeMethod("onShareIntent", url)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == ANKI_PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingAnkiPermissionResult?.success(granted)
            pendingAnkiPermissionResult = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Share intent channel (unchanged)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "getInitialShareUrl") {
                    result.success(pendingShareUrl)
                    pendingShareUrl = null
                } else {
                    result.notImplemented()
                }
            }

        // AnkiDroid bridge channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ankiChannelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "isAnkiDroidAvailable" -> {
                            val available = try {
                                applicationContext.packageManager
                                    .getPackageInfo("com.ichi2.anki", 0)
                                true
                            } catch (e: PackageManager.NameNotFoundException) {
                                false
                            }
                            result.success(available)
                        }

                        "requestPermission" -> {
                            pendingAnkiPermissionResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf("com.ichi2.anki.permission.READ_WRITE_DATABASE"),
                                ANKI_PERMISSION_REQUEST_CODE,
                            )
                        }

                        "addNote" -> {
                            val deckName = call.argument<String>("deckName") ?: ""
                            val front = call.argument<String>("front") ?: ""
                            val back = call.argument<String>("back") ?: ""
                            val tags = call.argument<List<String>>("tags") ?: emptyList()
                            val api = AddContentApi(applicationContext)
                            val deckId = api.addNewDeck(deckName)
                                ?: return@setMethodCallHandler result.error(
                                    "DECK", "Failed to create deck", null)
                            val modelId = api.addNewBasicModel("com.nimeesh.interest.basic")
                                ?: return@setMethodCallHandler result.error(
                                    "MODEL", "Failed to create model", null)
                            val noteId = api.addNote(modelId, deckId, arrayOf(front, back), tags.toSet())
                            result.success(noteId ?: -1L)
                        }

                        "updateNote" -> {
                            val noteId = call.argument<Long>("noteId") ?: -1L
                            val front = call.argument<String>("front") ?: ""
                            val back = call.argument<String>("back") ?: ""
                            val tags = call.argument<List<String>>("tags") ?: emptyList()
                            val api = AddContentApi(applicationContext)
                            val fieldsOk = api.updateNoteFields(noteId, arrayOf(front, back))
                            val tagsOk = api.updateNoteTags(noteId, tags.toSet())
                            result.success(fieldsOk && tagsOk)
                        }

                        "noteExists" -> {
                            val noteId = call.argument<Long>("noteId") ?: -1L
                            val api = AddContentApi(applicationContext)
                            val note = api.getNote(noteId)
                            result.success(note != null)
                        }

                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("ANKI_ERROR", e.message, null)
                }
            }
    }

    private fun extractShareUrl(intent: Intent): String? {
        if (intent.action != Intent.ACTION_SEND) return null
        if (intent.type != "text/plain") return null
        return intent.getStringExtra(Intent.EXTRA_TEXT)
    }
}
