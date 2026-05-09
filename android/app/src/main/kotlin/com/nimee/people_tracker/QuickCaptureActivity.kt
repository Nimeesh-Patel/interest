package com.nimee.people_tracker

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

    private fun slugify(name: String): String {
        val slug = name.trim()
            .lowercase(Locale.US)
            .replace(Regex("\\s+"), "-")
            .replace(Regex("[^a-z0-9\\-]"), "")
        return slug.ifEmpty { "entity" }
    }

    private fun uniqueId(base: String, entitiesDir: File): String {
        if (!File(entitiesDir, "$base.md").exists()) return base
        var n = 2
        while (File(entitiesDir, "$base-$n.md").exists()) n++
        return "$base-$n"
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

    private fun safeFileName(name: String): String =
        name.replace(Regex("[/\\\\:*?\"<>|]"), "_") + ".md"

    private fun buildMarkdown(id: String, name: String, note: String?, vaultPath: String): String {
        val iso = nowIso()
        val frontmatter = "---\nalias: $id\ncategory: Default\ncreated_at: $iso\nupdated_at: $iso\n---"

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

        val entitiesDir = File("$vaultPath/Interesting/Entities")
        entitiesDir.mkdirs()

        val base = slugify(title)
        val id = uniqueId(base, entitiesDir)
        val markdown = buildMarkdown(id, title, note, vaultPath)
        val fileName = safeFileName(title)

        try {
            File(entitiesDir, fileName).writeText(markdown)
            Toast.makeText(this, R.string.toast_saved, Toast.LENGTH_SHORT).show()
            finish()
        } catch (e: Exception) {
            Toast.makeText(this, R.string.toast_error, Toast.LENGTH_LONG).show()
        }
    }
}
