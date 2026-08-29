package dev.interest.app

import android.app.Activity
import android.os.Bundle
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.Toast
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class QuickCaptureActivity : Activity() {

    private lateinit var etTitle: EditText
    private lateinit var etNote: EditText

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.quick_capture_activity)

        etTitle = findViewById(R.id.et_title)
        etNote = findViewById(R.id.et_note)

        findViewById<Button>(R.id.btn_save).setOnClickListener { save() }
        findViewById<Button>(R.id.btn_cancel).setOnClickListener { finish() }

        // Show keyboard on title field immediately
        etTitle.requestFocus()
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE)
    }

    private fun getVaultPath(): String? {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        return prefs.getString("flutter.vault_path", null)
    }

    private fun nowIso(): String {
        val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        sdf.timeZone = TimeZone.getTimeZone("UTC")
        return sdf.format(Date())
    }

    private fun loadTemplateBody(vaultPath: String): String? {
        return try {
            val file = File("$vaultPath/Interesting/Templates/default.md")
            if (!file.exists()) return null
            val text = file.readText()
            // Strip YAML frontmatter block (--- ... ---)
            if (text.startsWith("---")) {
                val end = text.indexOf("---", 3)
                if (end >= 0) text.substring(end + 3).trimStart('\n', '\r')
                else text
            } else text
        } catch (_: Exception) {
            null
        }
    }

    private fun safeBaseName(name: String): String =
        name.replace(Regex("[/\\\\:*?\"<>|]"), "_").trim()

    // collection: makes the note an entity (visible in the Collections tab);
    // category: remains the AnkiDroid deck mapping. Both are required.
    private fun buildMarkdown(name: String, note: String?, vaultPath: String): String {
        val iso = nowIso()
        val frontmatter = "---\ncollection: Quick Capture\ncategory: Default\ncreated_at: $iso\nupdated_at: $iso\n---"

        // Load body from default.md template; replace {{title}} placeholder
        val rawBody = loadTemplateBody(vaultPath)
            ?.replace("{{title}}", name)
            ?: "# $name\n\n## Why Interesting\n\n## Related\n\n## Sources\n"

        // Ensure body starts with H1
        val body = if (rawBody.trimStart().startsWith("# ")) rawBody
                   else "# $name\n\n$rawBody"

        // Insert note into ## Why Interesting section if provided
        val finalBody = if (!note.isNullOrBlank()) {
            body.replace(
                Regex("(## Why Interesting[ \\t]*\\n)"),
                "$1\n- $note\n"
            )
        } else body

        return "$frontmatter\n$finalBody"
    }

    private fun save() {
        val title = etTitle.text.toString().trim()
        if (title.isEmpty()) {
            Toast.makeText(this, R.string.toast_empty_title, Toast.LENGTH_SHORT).show()
            return
        }
        val note = etNote.text.toString().trim().ifEmpty { null }

        val vaultPath = getVaultPath()
        if (vaultPath == null) {
            Toast.makeText(this, R.string.toast_open_app, Toast.LENGTH_LONG).show()
            return
        }

        // New notes land at the vault root — the same write target as the
        // app's own entity creation (MarkdownStorageService.saveEntity).
        val dir = File(vaultPath)
        val base = safeBaseName(title)
        val markdown = buildMarkdown(title, note, vaultPath)

        // Collision handling matches the app: "Name.md", "Name 2.md", "Name 3.md"…
        var file = File(dir, "$base.md")
        var n = 2
        while (file.exists()) {
            file = File(dir, "$base $n.md")
            n++
        }

        try {
            file.writeText(markdown)
            Toast.makeText(this, R.string.toast_saved, Toast.LENGTH_SHORT).show()
            finish()
        } catch (e: Exception) {
            Toast.makeText(this, R.string.toast_error, Toast.LENGTH_LONG).show()
        }
    }
}
