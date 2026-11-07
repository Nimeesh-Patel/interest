package dev.interest.app

import android.app.Activity
import android.content.ContentValues
import android.net.Uri
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.app.ActivityCompat
import com.ichi2.anki.FlashCardsContract
import com.ichi2.anki.api.AddContentApi
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/// The AnkiDroid ContentProvider bridge (AddContentApi) exposed to Dart over a
/// MethodChannel. Translates projection operations and explicit state queries.
/// Hosted on MainActivity: the sync runs in the foreground app, so the runtime
/// READ_WRITE_DATABASE permission can be requested through the normal Activity
/// flow. `register` wires the channel; the host activity must forward
/// `onRequestPermissionsResult` so the first-run grant completes.
class AnkiBridge(private val activity: Activity) {
    private var pendingPermissionResult: MethodChannel.Result? = null
    private val ctx get() = activity.applicationContext

    companion object {
        const val CHANNEL = "dev.interest.app/ankidroid"
        const val PERMISSION = "com.ichi2.anki.permission.READ_WRITE_DATABASE"
        const val PERMISSION_REQUEST_CODE = 1001
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                handle(call.method, call, result)
            } catch (e: Exception) {
                result.error("ANKI_ERROR", e.message, null)
            }
        }
    }

    /// Forwarded from the host activity's onRequestPermissionsResult; completes
    /// the pending `requestPermission` call with the grant outcome.
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != PERMISSION_REQUEST_CODE) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    private fun handle(method: String, call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (method) {
            "isAnkiDroidAvailable" -> {
                val available = try {
                    ctx.packageManager.getPackageInfo("com.ichi2.anki", 0)
                    true
                } catch (e: PackageManager.NameNotFoundException) {
                    false
                }
                result.success(available)
            }

            "getAnkiDroidVersion" -> {
                val versionName = try {
                    ctx.packageManager.getPackageInfo("com.ichi2.anki", 0).versionName
                } catch (e: PackageManager.NameNotFoundException) {
                    null
                }
                result.success(versionName)
            }

            "queryCardState" -> {
                val query = call.argument<String>("query")
                val requestedLimit = call.argument<Any>("limit")
                if (query.isNullOrBlank() ||
                    (requestedLimit !is Int && requestedLimit !is Long) ||
                    (requestedLimit as Number).toLong() !in 1..AnkiCardStateReader.MAX_LIMIT.toLong()) {
                    return result.error("ARGUMENT",
                        "query must be nonblank and limit an integer from 1 to ${AnkiCardStateReader.MAX_LIMIT}", null)
                }
                val limit = (requestedLimit as Number).toInt()
                // Task-scoped work: queries/rendering never block Flutter's UI
                // thread, and this does not install a background service.
                Thread({
                    try {
                        val observation = AnkiCardStateReader(ctx.contentResolver, ::readNoteFront)
                            .query(query, limit)
                        activity.runOnUiThread { result.success(observation) }
                    } catch (e: Exception) {
                        activity.runOnUiThread {
                            result.error("ANKI_STATE", "${e.javaClass.simpleName}: ${e.message}", null)
                        }
                    }
                }, "Interest-Anki-card-state").start()
            }

            "requestPermission" -> {
                if (ActivityCompat.checkSelfPermission(activity, PERMISSION) ==
                    PackageManager.PERMISSION_GRANTED) {
                    result.success(true)
                } else {
                    if (pendingPermissionResult != null) return result.error(
                        "PERMISSION_PENDING", "An AnkiDroid permission request is already pending", null)
                    pendingPermissionResult = result
                    ActivityCompat.requestPermissions(
                        activity, arrayOf(PERMISSION), PERMISSION_REQUEST_CODE)
                }
            }

            "addNote" -> {
                val deckName = call.argument<String>("deckName") ?: ""
                val front = call.argument<String>("front") ?: ""
                val back = call.argument<String>("back") ?: ""
                val tags = call.argument<List<String>>("tags") ?: emptyList()
                val api = AddContentApi(ctx)
                val deckId = getOrCreateDeck(api, deckName)
                    ?: return result.error("DECK", "Failed to get or create deck: $deckName", null)
                val modelId = getBuiltInBasicModel(api)
                    ?: return result.error(
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
                            val fieldsOk = api.updateNoteFields(existingId, arrayOf(front, back))
                            val tagsOk = api.updateNoteTags(existingId, tags.toSet())
                            if (fieldsOk && tagsOk) result.success(existingId)
                            else result.error("ADD_FAILED", "Recovered duplicate $existingId could not be updated", null)
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
                val noteId = call.argument<Number>("noteId")?.toLong() ?: -1L
                val front = call.argument<String>("front") ?: ""
                val back = call.argument<String>("back") ?: ""
                val tags = call.argument<List<String>>("tags") ?: emptyList()
                val api = AddContentApi(ctx)
                val fieldsOk = api.updateNoteFields(noteId, arrayOf(front, back))
                val tagsOk = api.updateNoteTags(noteId, tags.toSet())
                result.success(fieldsOk && tagsOk)
            }

            "snapshotNotes" -> result.success(snapshotNotes())

            "noteExists" -> {
                val noteId = call.argument<Number>("noteId")?.toLong() ?: -1L
                result.success(readNoteFront(noteId) != null)
            }

            "moveNoteToDeck" -> {
                val noteId = call.argument<Number>("noteId")?.toLong() ?: -1L
                val deckName = call.argument<String>("deckName") ?: ""
                val api = AddContentApi(ctx)
                val deckId = getOrCreateDeck(api, deckName)
                if (deckId == null) result.success(false)
                else result.success(moveCardsToDeck(noteId, deckId))
            }

            "retireNote" -> {
                val noteId = call.argument<Number>("noteId")?.toLong() ?: -1L
                val source = call.argument<String>("expectedSourceUri")
                    ?: return result.error("SOURCE", "Retirement requires the exact source URI", null)
                val front = readNoteFront(noteId)
                if (front == null) return result.success(true)
                val owned = listOf(source, source.replace("&", "&amp;")).any {
                    front.contains("href=\"$it\"") || front.contains("href='$it'")
                }
                if (!owned) return result.error("SOURCE", "Refused retirement: Anki source link does not match this note", null)
                val uri = Uri.withAppendedPath(FlashCardsContract.Note.CONTENT_URI, noteId.toString())
                ctx.contentResolver.delete(uri, null, null)
                result.success(readNoteFront(noteId) == null)
            }

            else -> result.notImplemented()
        }
    }

    private fun getOrCreateDeck(api: AddContentApi, deckName: String): Long? {
        val decks = api.getDeckList() ?: throw IllegalStateException("Could not list AnkiDroid decks")
        val existing = decks.entries
            ?.firstOrNull { it.value.equals(deckName, ignoreCase = true) }
            ?.key
        return existing ?: api.addNewDeck(deckName)
    }

    /// Null means a completed exact-id query returned no rows, never an
    /// unavailable cursor. This distinction is required before ID removal.
    private fun readNoteFront(noteId: Long): String? {
        require(noteId > 0L) { "Invalid Anki note identity" }
        val uri = Uri.withAppendedPath(FlashCardsContract.Note.CONTENT_URI, noteId.toString())
        val cursor = ctx.contentResolver.query(uri,
            arrayOf(FlashCardsContract.Note._ID, FlashCardsContract.Note.FLDS), null, null, null)
            ?: throw IllegalStateException("AnkiDroid note query unavailable")
        cursor.use { c ->
            if (!c.moveToFirst()) return null
            val observedId = c.getLong(c.getColumnIndexOrThrow(FlashCardsContract.Note._ID))
            check(observedId == noteId) { "AnkiDroid returned a different note identity" }
            val fields = c.getString(c.getColumnIndexOrThrow(FlashCardsContract.Note.FLDS))
                ?: throw IllegalStateException("AnkiDroid returned no note fields")
            check(!c.moveToNext()) { "AnkiDroid returned ambiguous note identity" }
            return fields.substringBefore('\u001f')
        }
    }

    /// One bulk observation of every "Basic" note: identity, both fields, tags
    /// and the deck of each card. Two provider searches regardless of
    /// collection size. Any inconsistency fails the whole observation, because
    /// the sync core reads a note absent from this snapshot as absent from the
    /// collection; a partial view must never look like absence.
    private fun snapshotNotes(): Map<String, Any?> {
        val started = System.nanoTime()
        val api = AddContentApi(ctx)
        val modelId = getBuiltInBasicModel(api)
            ?: throw IllegalStateException("No \"Basic\" note type in AnkiDroid")
        val deckNames = api.getDeckList()
            ?: throw IllegalStateException("Could not list AnkiDroid decks")
        val search = "mid:$modelId"
        val notes = linkedMapOf<Long, MutableMap<String, Any?>>()
        val noteCursor = ctx.contentResolver.query(
            FlashCardsContract.Note.CONTENT_URI,
            arrayOf(FlashCardsContract.Note._ID, FlashCardsContract.Note.FLDS, FlashCardsContract.Note.TAGS),
            search, null, null,
        ) ?: throw IllegalStateException("AnkiDroid note search unavailable")
        noteCursor.use { c ->
            val idIndex = c.getColumnIndexOrThrow(FlashCardsContract.Note._ID)
            val fieldsIndex = c.getColumnIndexOrThrow(FlashCardsContract.Note.FLDS)
            val tagsIndex = c.getColumnIndexOrThrow(FlashCardsContract.Note.TAGS)
            while (c.moveToNext()) {
                val id = c.getLong(idIndex)
                check(id > 0 && id !in notes) { "AnkiDroid returned an invalid or repeated note identity" }
                val fields = (c.getString(fieldsIndex)
                    ?: throw IllegalStateException("AnkiDroid returned no fields for note $id"))
                    .split('\u001f')
                check(fields.size == 2) { "Basic note $id does not have exactly two fields" }
                notes[id] = mutableMapOf(
                    "id" to id, "front" to fields[0], "back" to fields[1],
                    "tags" to (c.getString(tagsIndex) ?: ""), "decks" to mutableListOf<String>(),
                )
            }
            check(notes.size == c.count) { "AnkiDroid note search was truncated" }
        }
        val cardCursor = ctx.contentResolver.query(
            Uri.withAppendedPath(FlashCardsContract.AUTHORITY_URI, "cards"),
            arrayOf(FlashCardsContract.Card.NOTE_ID, FlashCardsContract.Card.DECK_ID),
            search, null, null,
        ) ?: throw IllegalStateException("AnkiDroid card search unavailable")
        cardCursor.use { c ->
            val noteIndex = c.getColumnIndexOrThrow(FlashCardsContract.Card.NOTE_ID)
            val deckIndex = c.getColumnIndexOrThrow(FlashCardsContract.Card.DECK_ID)
            while (c.moveToNext()) {
                val note = notes[c.getLong(noteIndex)]
                    ?: throw IllegalStateException("AnkiDroid card search returned a card outside the note search")
                val deck = deckNames[c.getLong(deckIndex)]
                    ?: throw IllegalStateException("AnkiDroid card is in an unlisted deck")
                @Suppress("UNCHECKED_CAST")
                (note["decks"] as MutableList<String>).add(deck)
            }
        }
        check(notes.values.all { (it["decks"] as List<*>).isNotEmpty() }) {
            "An AnkiDroid note has no observable cards"
        }
        return mapOf(
            "notes" to notes.values.toList(),
            "elapsed_ms" to (System.nanoTime() - started) / 1_000_000,
        )
    }

    private fun getBuiltInBasicModel(api: AddContentApi): Long? {
        val models = api.getModelList() ?: return null
        for ((id, name) in models) {
            if (name == "Basic") return id
        }
        return null
    }

    private fun cardsUriFor(noteId: Long): Uri =
        Uri.withAppendedPath(FlashCardsContract.Note.CONTENT_URI, "$noteId/cards")

    private fun moveCardsToDeck(noteId: Long, deckId: Long): Boolean {
        return try {
            val before = readCardDecks(noteId)
            if (before.isEmpty()) return false
            for ((ord, currentDeck) in before) {
                if (currentDeck == deckId) continue
                val values = ContentValues().apply {
                    put(FlashCardsContract.Card.DECK_ID, deckId)
                }
                ctx.contentResolver.update(
                    Uri.withAppendedPath(cardsUriFor(noteId), ord.toString()),
                    values, null, null,
                )
            }
            // A zero-row update is not evidence of placement. Check the actual
            // card set and deck after the writes, including idempotent moves.
            val after = readCardDecks(noteId)
            after.keys == before.keys && after.values.all { it == deckId }
        } catch (e: Exception) {
            false
        }
    }

    private fun readCardDecks(noteId: Long): Map<Int, Long> {
        val cursor = ctx.contentResolver.query(cardsUriFor(noteId), null, null, null, null)
            ?: throw IllegalStateException("AnkiDroid card query unavailable")
        return cursor.use { c ->
            val ordIdx = c.getColumnIndexOrThrow(FlashCardsContract.Card.CARD_ORD)
            val deckIdx = c.getColumnIndexOrThrow(FlashCardsContract.Card.DECK_ID)
            val decks = mutableMapOf<Int, Long>()
            while (c.moveToNext()) {
                val ord = c.getInt(ordIdx)
                check(!decks.containsKey(ord)) { "AnkiDroid returned duplicate card ordinals" }
                decks[ord] = c.getLong(deckIdx)
            }
            decks
        }
    }
}
