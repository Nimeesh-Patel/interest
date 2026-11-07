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
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Device contract checks against the actual installed AnkiDroid provider.
 * Run only on an explicitly supplied device with AnkiDroid permission granted.
 * `-e mode card-state` performs only state queries; the default projection
 * checks use an existing ordinary deck and withdraw only their own new notes.
 * No Activity launch, vault sync, source-file edits, or deck creation occurs.
 */
class AnkiBridgeDeviceChecks : Instrumentation() {
    private var requestedDeck: String? = null
    private var readOnlyState = false
    private var snapshotOnly = false

    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        requestedDeck = arguments?.getString("deckName")
        readOnlyState = arguments?.getString("mode") == "card-state"
        snapshotOnly = arguments?.getString("mode") == "snapshot"
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
            val completed = CountDownLatch(1)
            var value: Any? = null
            var error: String? = null
            handler.invoke(bridge, method, MethodCall(method, args), object : MethodChannel.Result {
                override fun success(result: Any?) { value = result; completed.countDown() }
                override fun error(code: String, message: String?, details: Any?) {
                    error = "$code: $message"
                    completed.countDown()
                }
                override fun notImplemented() { error = "Not implemented: $method"; completed.countDown() }
            })
            check(completed.await(30, TimeUnit.SECONDS)) { "$method did not complete" }
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
        if (snapshotOnly) {
            // Read-only: one bulk snapshot, cross-checked note by note against
            // the per-note provider reads the sync used before.
            try {
                check(context.checkSelfPermission(AnkiBridge.PERMISSION) == PackageManager.PERMISSION_GRANTED) {
                    "Grant Interest AnkiDroid permission through the normal app flow first"
                }
                val snap = call("snapshotNotes") as Map<*, *>
                val notes = snap["notes"] as List<*>
                check(notes.isNotEmpty()) { "Snapshot returned no notes" }
                var owned = 0
                for (raw in notes) {
                    val n = raw as Map<*, *>
                    val id = (n["id"] as Number).toLong()
                    val front = n["front"] as String
                    if (front.contains("obsidian://open?")) owned++
                    val uri = Uri.withAppendedPath(FlashCardsContract.Note.CONTENT_URI, id.toString())
                    val single = context.contentResolver.query(uri,
                        arrayOf(FlashCardsContract.Note.FLDS), null, null, null)
                        ?: error("Per-note query unavailable")
                    single.use { c ->
                        check(c.moveToFirst()) { "Snapshot note $id absent from per-note read" }
                        val fields = c.getString(0).split('\u001f')
                        check(fields[0] == front && fields[1] == n["back"]) { "Snapshot fields differ for $id" }
                    }
                    val decks = (n["decks"] as List<*>).toSet()
                    val expected = deckIds(id).toSet().size
                    check(decks.isNotEmpty() && decks.size <= expected) { "Snapshot decks differ for $id" }
                }
                report.putString("notes", notes.size.toString())
                report.putString("owned_notes", owned.toString())
                report.putString("snapshot_ms", snap["elapsed_ms"].toString())
                report.putString("result", "PASS: bulk snapshot matches per-note reads; no mutations")
            } catch (e: Throwable) {
                report.putString("result", "FAIL")
                report.putString("error", e.stackTraceToString())
            }
            finish(Activity.RESULT_OK, report)
            return
        }
        if (readOnlyState) {
            try {
                check(context.checkSelfPermission(AnkiBridge.PERMISSION) == PackageManager.PERMISSION_GRANTED) {
                    "Grant Interest AnkiDroid permission through the normal app flow first"
                }
                // This mode creates, answers, moves and deletes no cards.
                for (query in listOf("is:due", "rated:1", "is:new")) {
                    val observed = call("queryCardState", mapOf("query" to query, "limit" to 2)) as Map<*, *>
                    check(observed["query"] == query)
                    check(observed["status"] in listOf("complete", "partial")) {
                        "Native card observation unavailable: ${observed["errors"]}"
                    }
                    check((observed["observed_at_ms"] as Number).toLong() > 0)
                    val total = (observed["total"] as Number).toInt()
                    val rows = observed["cards"] as List<*>
                    check(rows.size == minOf(total, 2)) { "Native card details were not all observable" }
                    for (row in rows) {
                        row as Map<*, *>
                        check((row["card_id"] as Number).toLong() > 0)
                        check((row["note_id"] as Number).toLong() > 0)
                        check((row["ordinal"] as Number).toInt() >= 0)
                        val state = row["state"] as Map<*, *>
                        check(listOf("queue", "due", "interval", "reps", "lapses")
                            .all { state[it] is Number })
                        check(row["source_front_html"] is String || row["source_error"] is String)
                    }
                    if (observed["status"] == "complete") {
                        check(rows.size == total && (observed["errors"] as List<*>).isEmpty())
                    }
                }
                val empty = call("queryCardState", mapOf("query" to "cid:0", "limit" to 1)) as Map<*, *>
                check(empty["status"] == "complete" && empty["total"] == 0 &&
                    (empty["cards"] as List<*>).isEmpty())
                var rejected = false
                try { call("queryCardState", mapOf("query" to "is:due", "limit" to 0)) }
                catch (_: IllegalStateException) { rejected = true }
                check(rejected) { "Invalid result bound was accepted" }
                report.putString("result", "PASS: bounded native state/identities, empty search and invalid bound; no mutations")
                finish(Activity.RESULT_OK, report)
            } catch (e: Throwable) {
                report.putString("result", "FAIL")
                report.putString("error", e.stackTraceToString())
                finish(Activity.RESULT_CANCELED, report)
            }
            return
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
