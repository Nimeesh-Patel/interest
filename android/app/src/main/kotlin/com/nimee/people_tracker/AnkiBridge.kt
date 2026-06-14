package com.nimee.people_tracker

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.content.ContextCompat
import com.ichi2.anki.FlashCardsContract
import com.ichi2.anki.api.AddContentApi
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/// The AnkiDroid ContentProvider bridge (AddContentApi) exposed to Dart over a
/// MethodChannel. Translates the seven AnkiTransport operations; nothing else.
/// Context-based, so it runs from the headless SyncService engine (no Activity).
///
/// `requestPermission` here is a pure *check*, not a request: granting AnkiDroid's
/// runtime READ_WRITE_DATABASE permission needs a visible Activity, which the
/// service has none of. SyncActivity (the deep-link trampoline) obtains the grant
/// before the service ever runs, so by the time Dart asks, the answer is settled.
class AnkiBridge(context: Context) {
    private val ctx: Context = context.applicationContext

    companion object {
        const val CHANNEL = "com.nimeesh.interest/ankidroid"
        const val PERMISSION = "com.ichi2.anki.permission.READ_WRITE_DATABASE"
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

            "requestPermission" -> {
                val granted = ContextCompat.checkSelfPermission(ctx, PERMISSION) ==
                    PackageManager.PERMISSION_GRANTED
                result.success(granted)
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
                val api = AddContentApi(ctx)
                val fieldsOk = api.updateNoteFields(noteId, arrayOf(front, back))
                val tagsOk = api.updateNoteTags(noteId, tags.toSet())
                result.success(fieldsOk && tagsOk)
            }

            "noteExists" -> {
                val noteId = call.argument<Long>("noteId") ?: -1L
                val api = AddContentApi(ctx)
                result.success(api.getNote(noteId) != null)
            }

            "getCardDeck" -> {
                val noteId = call.argument<Long>("noteId") ?: -1L
                val api = AddContentApi(ctx)
                result.success(getCardDeckName(api, noteId))
            }

            "moveNoteToDeck" -> {
                val noteId = call.argument<Long>("noteId") ?: -1L
                val deckName = call.argument<String>("deckName") ?: ""
                val api = AddContentApi(ctx)
                val deckId = getOrCreateDeck(api, deckName)
                if (deckId == null) result.success(false)
                else result.success(moveCardsToDeck(noteId, deckId))
            }

            else -> result.notImplemented()
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

    private fun cardsUriFor(noteId: Long): Uri =
        Uri.withAppendedPath(FlashCardsContract.Note.CONTENT_URI, "$noteId/cards")

    private fun getCardDeckName(api: AddContentApi, noteId: Long): String? {
        return try {
            ctx.contentResolver.query(cardsUriFor(noteId), null, null, null, null)?.use { c ->
                if (!c.moveToFirst()) return null
                val idx = c.getColumnIndex(FlashCardsContract.Card.DECK_ID)
                if (idx < 0) return null
                api.getDeckList()?.get(c.getLong(idx))
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun moveCardsToDeck(noteId: Long, deckId: Long): Boolean {
        return try {
            val ords = mutableListOf<Int>()
            ctx.contentResolver.query(cardsUriFor(noteId), null, null, null, null)?.use { c ->
                val ordIdx = c.getColumnIndex(FlashCardsContract.Card.CARD_ORD)
                if (ordIdx < 0) return false
                while (c.moveToNext()) ords.add(c.getInt(ordIdx))
            }
            if (ords.isEmpty()) return false
            for (ord in ords) {
                val values = ContentValues().apply {
                    put(FlashCardsContract.Card.DECK_ID, deckId)
                }
                ctx.contentResolver.update(
                    Uri.withAppendedPath(cardsUriFor(noteId), ord.toString()),
                    values, null, null,
                )
            }
            true
        } catch (e: Exception) {
            false
        }
    }
}
