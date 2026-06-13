package com.nimee.people_tracker

import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.util.Log
import androidx.core.app.ActivityCompat
import com.ichi2.anki.FlashCardsContract
import com.ichi2.anki.api.AddContentApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val shareChannelName = "people.nimee/share"
    private val ankiChannelName = "com.nimeesh.interest/ankidroid"
    private val deeplinkChannelName = "com.nimeesh.interest/deeplink"
    private var pendingShareUrl: String? = null
    private var pendingDeeplinkNote: String? = null
    private var pendingSyncAnki: Boolean = false
    private var pendingAnkiPermissionResult: MethodChannel.Result? = null

    companion object {
        private const val ANKI_PERMISSION_REQUEST_CODE = 1001
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingShareUrl = extractShareUrl(intent)
        pendingDeeplinkNote = extractDeeplinkNote(intent)
        pendingSyncAnki = extractSyncAnki(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractShareUrl(intent)?.let { url ->
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, shareChannelName).invokeMethod("onShareIntent", url)
            }
        }
        extractDeeplinkNote(intent)?.let { noteName ->
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, deeplinkChannelName).invokeMethod("openNote", noteName)
            }
        }
        if (extractSyncAnki(intent)) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, deeplinkChannelName).invokeMethod("syncAnki", null)
            }
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

        // Share intent channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "getInitialShareUrl") {
                    result.success(pendingShareUrl)
                    pendingShareUrl = null
                } else {
                    result.notImplemented()
                }
            }

        // Deep-link channel (interest://note/<name>, interest://sync-anki)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deeplinkChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialDeeplinkNote" -> {
                        result.success(pendingDeeplinkNote)
                        pendingDeeplinkNote = null
                    }
                    "getInitialSyncAnki" -> {
                        result.success(pendingSyncAnki)
                        pendingSyncAnki = false
                    }
                    else -> result.notImplemented()
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

                        "getAnkiDroidVersion" -> {
                            val versionName = try {
                                applicationContext.packageManager
                                    .getPackageInfo("com.ichi2.anki", 0)
                                    .versionName
                            } catch (e: PackageManager.NameNotFoundException) {
                                null
                            }
                            result.success(versionName)
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
                            val deckId = getOrCreateDeck(api, deckName)
                                ?: return@setMethodCallHandler result.error(
                                    "DECK", "Failed to get or create deck: $deckName", null)
                            val modelId = getBuiltInBasicModel(api)
                                ?: return@setMethodCallHandler result.error(
                                    "BASIC_MODEL_NOT_FOUND",
                                    "Basic model not found in AnkiDroid — open AnkiDroid and ensure it is installed correctly.",
                                    null)
                            try {
                                val noteId = api.addNote(modelId, deckId, arrayOf(front, back), tags.toSet())
                                if (noteId == null || noteId <= 0L) {
                                    val dupeMap = api.findDuplicateNotes(modelId, listOf(front))
                                    val dupList = dupeMap?.get(0)
                                    if (dupList != null && dupList.isNotEmpty()) {
                                        val existingId = dupList.first().id
                                        api.updateNoteFields(existingId, arrayOf(front, back))
                                        result.success(existingId)
                                    } else {
                                        result.error("ADD_FAILED", "addNote returned null, not a duplicate", null)
                                    }
                                } else {
                                    result.success(noteId)
                                }
                            } catch (e: Exception) {
                                Log.e("AnkiSync", "Failed to add note: ${e.javaClass.name}: ${e.message}")
                                Log.e("AnkiSync", Log.getStackTraceString(e))
                                result.error("ADD_FAILED", "${e.javaClass.name}: ${e.message}", null)
                            }
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

                        "getCardDeck" -> {
                            val noteId = call.argument<Long>("noteId") ?: -1L
                            val api = AddContentApi(applicationContext)
                            result.success(getCardDeckName(api, noteId))
                        }

                        "moveNoteToDeck" -> {
                            val noteId = call.argument<Long>("noteId") ?: -1L
                            val deckName = call.argument<String>("deckName") ?: ""
                            val api = AddContentApi(applicationContext)
                            val deckId = getOrCreateDeck(api, deckName)
                            if (deckId == null) {
                                result.success(false)
                            } else {
                                result.success(moveCardsToDeck(noteId, deckId))
                            }
                        }

                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("ANKI_ERROR", e.message, null)
                }
            }
    }

    private fun getOrCreateDeck(api: AddContentApi, deckName: String): Long? {
        val existing = api.getDeckList()?.entries
            ?.firstOrNull { it.value.equals(deckName, ignoreCase = true) }
            ?.key
        return existing ?: api.addNewDeck(deckName)
    }

    private fun getBuiltInBasicModel(api: AddContentApi): Long? {
        val models = api.getModelList() ?: return null
        for ((id, name) in models) {
            if (name == "Basic") return id
        }
        return null
    }

    /// The cards of a note via the ContentProvider: notes/<id>/cards.
    private fun cardsUriFor(noteId: Long): Uri =
        Uri.withAppendedPath(FlashCardsContract.Note.CONTENT_URI, "$noteId/cards")

    /// Name of the deck the note's first card lives in, or null if it can't be
    /// resolved. Used by the sync core to detect a category (deck) change.
    private fun getCardDeckName(api: AddContentApi, noteId: Long): String? {
        return try {
            contentResolver.query(cardsUriFor(noteId), null, null, null, null)?.use { c ->
                if (!c.moveToFirst()) return null
                val idx = c.getColumnIndex(FlashCardsContract.Card.DECK_ID)
                if (idx < 0) return null
                api.getDeckList()?.get(c.getLong(idx))
            }
        } catch (e: Exception) {
            null
        }
    }

    /// Moves every card of the note into [deckId] by updating each card's
    /// DECK_ID through the ContentProvider. Returns false (no-op) on any error.
    private fun moveCardsToDeck(noteId: Long, deckId: Long): Boolean {
        return try {
            val ords = mutableListOf<Int>()
            contentResolver.query(cardsUriFor(noteId), null, null, null, null)?.use { c ->
                val ordIdx = c.getColumnIndex(FlashCardsContract.Card.CARD_ORD)
                if (ordIdx < 0) return false
                while (c.moveToNext()) ords.add(c.getInt(ordIdx))
            }
            if (ords.isEmpty()) return false
            for (ord in ords) {
                val values = ContentValues().apply {
                    put(FlashCardsContract.Card.DECK_ID, deckId)
                }
                contentResolver.update(
                    Uri.withAppendedPath(cardsUriFor(noteId), ord.toString()),
                    values, null, null,
                )
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun extractShareUrl(intent: Intent): String? {
        if (intent.action != Intent.ACTION_SEND) return null
        if (intent.type != "text/plain") return null
        return intent.getStringExtra(Intent.EXTRA_TEXT)
    }

    private fun extractDeeplinkNote(intent: Intent): String? {
        if (intent.action != Intent.ACTION_VIEW) return null
        val uri = intent.data ?: return null
        if (uri.scheme != "interest" || uri.host != "note") return null
        return uri.lastPathSegment  // Android Uri auto-decodes %20 → space
    }

    private fun extractSyncAnki(intent: Intent): Boolean {
        if (intent.action != Intent.ACTION_VIEW) return false
        val uri = intent.data ?: return false
        return uri.scheme == "interest" && uri.host == "sync-anki"
    }
}
