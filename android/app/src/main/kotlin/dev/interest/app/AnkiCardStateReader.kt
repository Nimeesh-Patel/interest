package dev.interest.app

import android.annotation.SuppressLint
import android.content.ContentResolver
import android.database.Cursor
import android.net.Uri
import com.ichi2.anki.FlashCardsContract

/** Dated native observations only. This reader has no scheduler or write path. */
internal class AnkiCardStateReader(
    private val resolver: ContentResolver,
    private val sourceFront: (Long) -> String?,
) {
    companion object {
        const val MAX_LIMIT = 1000

        // These documented provider columns are newer than the api-v1.1.0
        // compile dependency. The actual provider must accept each projection;
        // missing runtime support is reported, never treated as an empty set.
        private val cardsUri = Uri.withAppendedPath(FlashCardsContract.AUTHORITY_URI, "cards")
        private val stateColumns = arrayOf(
            "deck_id", "original_deck_id", "type", "queue", "due",
            "original_due", "interval", "reps", "lapses",
        )
        private val detailColumns = arrayOf("_id", "note_id", "ord", *stateColumns)
    }

    fun query(query: String, limit: Int): Map<String, Any?> {
        require(query.isNotBlank()) { "Anki query must not be blank" }
        require(limit in 1..MAX_LIMIT) { "limit must be between 1 and $MAX_LIMIT" }
        val errors = mutableListOf<Map<String, Any?>>()
        val cards = mutableListOf<Map<String, Any?>>()
        val ids = mutableListOf<Long>()
        val total: Int
        try {
            val cursor = resolver.query(cardsUri, arrayOf("_id"), query, null, null)
                ?: throw IllegalStateException("AnkiDroid card search returned no cursor")
            cursor.use { c ->
                total = c.count
                check(total >= 0) { "AnkiDroid returned an invalid card count" }
                c.getColumnIndexOrThrow("_id")
                val seen = mutableSetOf<Long>()
                while (ids.size < limit && c.moveToNext()) {
                    val id = integer(c, "_id")
                    check(id > 0 && seen.add(id)) { "AnkiDroid returned an invalid or repeated card identity" }
                    ids.add(id)
                }
                check(ids.size == minOf(total, limit)) { "AnkiDroid card search was truncated unexpectedly" }
            }
        } catch (e: Exception) {
            return observation(query, "unavailable", null, cards,
                listOf(error("search", e)))
        }

        // The provider materializes its complete matching ID list. This limit
        // bounds returned/detail work; it does not bound native search cost.
        if (total > limit) errors.add(mapOf(
            "stage" to "limit", "message" to "Showing at most $limit of $total native matches",
        ))
        val fronts = mutableMapOf<Long, Pair<String?, String?>>()
        for (id in ids) {
            val card = try {
                readCard(id)
            } catch (e: Exception) {
                errors.add(error("card", e) + ("card_id" to id))
                continue
            }
            val noteId = card["note_id"] as Long
            val front = fronts.getOrPut(noteId) {
                try {
                    val html = sourceFront(noteId)
                        ?: throw IllegalStateException("Source note was absent during capture")
                    Pair(html, null)
                } catch (e: Exception) {
                    errors.add(error("source", e) + ("note_id" to noteId))
                    Pair(null, describe(e))
                }
            }
            card["source_front_html"] = front.first
            if (front.second != null) card["source_error"] = front.second
            cards.add(card)
        }
        return observation(query, if (errors.isEmpty()) "complete" else "partial",
            total, cards, errors)
    }

    private fun readCard(id: Long): MutableMap<String, Any?> {
        val cursor = resolver.query(Uri.withAppendedPath(cardsUri, id.toString()),
            detailColumns, null, null, null)
            ?: throw IllegalStateException("AnkiDroid card detail returned no cursor")
        return cursor.use { c ->
            check(c.moveToFirst()) { "Card $id disappeared during capture" }
            check(integer(c, "_id") == id) { "AnkiDroid returned a different card identity" }
            val noteId = integer(c, "note_id")
            val ordinal = integer(c, "ord")
            check(noteId > 0 && ordinal in 0..Int.MAX_VALUE.toLong()) {
                "AnkiDroid returned invalid note/template identity"
            }
            val state = stateColumns.associateWith { integer(c, it) }
            check(!c.moveToNext()) { "AnkiDroid returned multiple rows for card $id" }
            mutableMapOf(
                "card_id" to id, "note_id" to noteId, "ordinal" to ordinal.toInt(),
                "state" to state,
            )
        }
    }

    private fun integer(cursor: Cursor, column: String): Long {
        val index = cursor.getColumnIndexOrThrow(column)
        check(!cursor.isNull(index) && cursor.getType(index) == Cursor.FIELD_TYPE_INTEGER) {
            "AnkiDroid column '$column' is not a native integer"
        }
        return cursor.getLong(index)
    }

    // The bundled API lint targets Anki's internal Collection clock. This
    // external observer records its own wall-clock time, not scheduler time.
    @SuppressLint("DirectSystemCurrentTimeMillisUsage")
    private fun observation(
        query: String,
        status: String,
        total: Int?,
        cards: List<Map<String, Any?>>,
        errors: List<Map<String, Any?>>,
    ): Map<String, Any?> = mapOf(
        "query" to query, "status" to status,
        "observed_at_ms" to System.currentTimeMillis(), "total" to total,
        "cards" to cards, "errors" to errors,
    )

    private fun describe(error: Exception) =
        "${error.javaClass.simpleName}: ${error.message ?: "AnkiDroid observation failed"}"

    private fun error(stage: String, error: Exception): Map<String, Any?> = mapOf(
        "stage" to stage, "message" to describe(error),
        "error_type" to error.javaClass.simpleName,
    )
}
