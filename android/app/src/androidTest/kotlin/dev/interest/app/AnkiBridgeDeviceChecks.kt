package dev.interest.app

import android.app.Activity
import android.app.Instrumentation
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import com.ichi2.anki.FlashCardsContract
import com.ichi2.anki.api.AddContentApi
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/** Device contract checks against the actual installed AnkiDroid provider.
 * Run only on an explicitly supplied device with AnkiDroid permission granted.
 * Uses an existing ordinary deck and only withdraws notes created by this run.
 * No Activity launch, vault sync, source-file edits, or deck creation occurs.
 */
class AnkiBridgeDeviceChecks : Instrumentation() {
    private var requestedDeck: String? = null

    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        requestedDeck = arguments?.getString("deckName")
        start()
    }

    override fun onStart() {
        val report = Bundle()
        val ownedNotes = linkedMapOf<Long, String>()
        var failure: Throwable? = null
        val context = targetContext
        // Native operations use applicationContext; no permission UI is needed
        // because these checks require a previously granted permission.
        lateinit var host: Activity
        runOnMainSync {
            host = object : Activity() {
                override fun getApplicationContext(): Context = context
            }
        }
        val bridge = AnkiBridge(host)
        val handler = AnkiBridge::class.java.getDeclaredMethod(
            "handle", String::class.java, MethodCall::class.java, MethodChannel.Result::class.java,
        ).apply { isAccessible = true }
        fun call(method: String, args: Map<String, Any?> = emptyMap()): Any? {
            var completed = false
            var value: Any? = null
            var error: String? = null
            handler.invoke(bridge, method, MethodCall(method, args), object : MethodChannel.Result {
                override fun success(result: Any?) { completed = true; value = result }
                override fun error(code: String, message: String?, details: Any?) {
                    completed = true
                    error = "$code: $message"
                }
                override fun notImplemented() { error = "Not implemented: $method" }
            })
            check(completed) { "$method did not complete" }
            check(error == null) { error!! }
            return value
        }
        fun deckIds(noteId: Long): List<Long> {
            val uri = Uri.withAppendedPath(FlashCardsContract.Note.CONTENT_URI, "$noteId/cards")
            val cursor = context.contentResolver.query(uri, null, null, null, null)
                ?: error("Native card query unavailable")
            return cursor.use { c ->
                val ids = mutableListOf<Long>()
                while (c.moveToNext()) ids.add(c.getLong(c.getColumnIndexOrThrow(FlashCardsContract.Card.DECK_ID)))
                ids
            }
        }
        try {
            check(context.checkSelfPermission(AnkiBridge.PERMISSION) == PackageManager.PERMISSION_GRANTED) {
                "Grant Interest AnkiDroid permission through the normal app flow first"
            }
            check(call("isAnkiDroidAvailable") == true)
            val api = AddContentApi(context)
            val decks = api.getDeckList() ?: error("Native deck list unavailable")
            val name = requestedDeck ?: error("Supply -e deckName with an existing ordinary deck")
            val target = decks.entries.single { it.value.equals(name, ignoreCase = true) }
            check(target.key != AddContentApi.DEFAULT_DECK_ID) { "Choose a deck other than Default" }
            val token = UUID.randomUUID().toString()
            val source = "obsidian://open?vault=Interest-device-check&file=$token"
            val front = "<p>Interest device check $token</p><a href=\"${source.replace("&", "&amp;")}\">Source</a>"
            val id = (call("addNote", mapOf("deckName" to "Default", "front" to front,
                "back" to "Temporary bridge fixture", "tags" to listOf("interest_device_check"))) as Number).toLong()
            check(id > 0L)
            ownedNotes[id] = source
            check(call("noteExists", mapOf("noteId" to id)) == true)
            check(deckIds(id).let { it.isNotEmpty() && it.all { deck -> deck == AddContentApi.DEFAULT_DECK_ID } })
            check(call("moveNoteToDeck", mapOf("noteId" to id, "deckName" to target.value.lowercase())) == true)
            check(deckIds(id).let { it.isNotEmpty() && it.all { deck -> deck == target.key } })
            check(call("moveNoteToDeck", mapOf("noteId" to id, "deckName" to target.value)) == true)
            check(call("updateNote", mapOf("noteId" to id, "front" to front,
                "back" to "Updated temporary fixture", "tags" to listOf("interest_device_check"))) == true)
            check(api.getNote(id)?.fields?.get(1) == "Updated temporary fixture")
            check(deckIds(id).all { it == target.key })
            check(api.getDeckList() == decks) { "Existing-deck operations changed the deck inventory" }
            report.putString("deck_placement", "PASS: existing named deck, case-insensitive reuse, idempotent move, update")

            val directId = (call("addNote", mapOf("deckName" to target.value, "front" to "$front<p>Direct</p>",
                "back" to "Direct named-deck creation", "tags" to emptyList<String>())) as Number).toLong()
            ownedNotes[directId] = source
            check(deckIds(directId).let { it.isNotEmpty() && it.all { deck -> deck == target.key } })
            report.putString("named_deck_creation", "PASS: new note in an already existing named deck")

            var rejected = false
            try { call("retireNote", mapOf("noteId" to id, "expectedSourceUri" to "$source-other")) }
            catch (_: IllegalStateException) { rejected = true }
            check(rejected) { "A mismatched source was not rejected" }
            check(call("noteExists", mapOf("noteId" to id)) == true)
            for ((noteId, expectedSource) in ownedNotes) {
                check(call("retireNote", mapOf("noteId" to noteId, "expectedSourceUri" to expectedSource)) == true)
                check(call("noteExists", mapOf("noteId" to noteId)) == false)
                check(call("retireNote", mapOf("noteId" to noteId, "expectedSourceUri" to expectedSource)) == true)
            }
            report.putString("withdrawal", "PASS: source guard, HTML-escaped source, deletion, verified absence, repeat")
        } catch (e: Throwable) {
            failure = e
        } finally {
            // Reuse the production source guard. Never bulk-delete or clean up
            // another run's fixture, even if it has the same test tag.
            for ((id, source) in ownedNotes) {
                try { check(call("retireNote", mapOf("noteId" to id, "expectedSourceUri" to source)) == true) }
                catch (e: Throwable) { if (failure == null) failure = e else failure!!.addSuppressed(e) }
            }
            report.putString("owned_note_ids", ownedNotes.keys.joinToString())
            if (failure == null) {
                report.putString("result", "PASS; all owned temporary notes removed; no decks created")
                finish(Activity.RESULT_OK, report)
            } else {
                report.putString("result", "FAIL")
                report.putString("error", failure!!.stackTraceToString())
                finish(Activity.RESULT_CANCELED, report)
            }
        }
    }
}
