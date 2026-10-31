package com.antigravity.auraplayer.service

import android.content.Context
import android.util.Log
import com.antigravity.auraplayer.model.LyricLine
import com.antigravity.auraplayer.utils.MetadataCleaner
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Lyrics written or synced by hand, identical in format and behavior to the iOS and macOS apps.
 * Takes precedence over lyrics found online via LRCLIB.
 */
object CustomLyricsStore {
    private const val TAG = "CustomLyricsStore"
    private var file: File? = null
    private val cache = mutableMapOf<String, Entry>()

    data class Entry(
        val lines: List<String>,
        val timesMs: List<Long?>,
        val modified: Long = System.currentTimeMillis()
    ) {
        val isFullySynced: Boolean
            get() = lines.isNotEmpty() && timesMs.size == lines.size && !timesMs.contains(null)

        val filledTimesMs: List<Long>?
            get() {
                if (lines.isEmpty()) return null
                val known = timesMs.mapIndexedNotNull { i, t -> t?.let { i to it } }
                if (known.size >= 2) {
                    val out = LongArray(lines.size)
                    for ((i, t) in known) { out[i] = t }
                    for (i in lines.indices) {
                        if (i >= timesMs.size || timesMs[i] == null) {
                            val before = known.lastOrNull { it.first < i }
                            val after = known.firstOrNull { it.first > i }
                            when {
                                before != null && after != null -> {
                                    val span = after.second - before.second
                                    val steps = after.first - before.first
                                    out[i] = before.second + (span * (i - before.first) / steps)
                                }
                                before != null -> out[i] = before.second + 4500L * (i - before.first)
                                after != null -> out[i] = (after.second - 4500L * (after.first - i)).coerceAtLeast(0L)
                            }
                        }
                    }
                    return out.toList()
                }
                if (known.size == 1) {
                    val (idx, t) = known[0]
                    return lines.indices.map { i -> (t + (i - idx) * 5000L).coerceAtLeast(0L) }
                }
                // Natural default: 15s intro, 5000ms per line
                return lines.indices.map { i -> 15000L + i * 5000L }
            }
    }

    fun init(context: Context) {
        if (file != null) return
        file = File(context.filesDir, "custom_lyrics.json")
        val f = file!!
        if (!f.exists()) {
            try {
                context.assets.open("custom_lyrics.json").use { input ->
                    f.outputStream().use { output -> input.copyTo(output) }
                }
            } catch (ignored: Exception) { }
        }
        load()
    }

    private fun key(title: String, artist: String): String {
        val cleaned = MetadataCleaner.clean(title, artist)
        val t = cleaned.cleanTitle.lowercase().trim()
        val a = cleaned.primaryArtist.lowercase().trim()
        return "$t|$a"
    }

    @Synchronized
    private fun load() {
        val f = file ?: return
        if (!f.exists()) return
        try {
            val jsonStr = f.readText()
            val root = JSONObject(jsonStr)
            cache.clear()
            val keys = root.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                val obj = root.getJSONObject(k)
                val linesArr = obj.getJSONArray("lines")
                val lines = mutableListOf<String>()
                for (i in 0 until linesArr.length()) lines.add(linesArr.getString(i))
                val timesArr = obj.getJSONArray("times")
                val times = mutableListOf<Long?>()
                for (i in 0 until timesArr.length()) {
                    if (timesArr.isNull(i)) times.add(null)
                    else {
                        val v = timesArr.getDouble(i)
                        // Support both seconds (from Mac/iOS sync) and ms
                        val ms = if (v < 10000.0) (v * 1000).toLong() else v.toLong()
                        times.add(ms)
                    }
                }
                val mod = obj.optLong("modified", System.currentTimeMillis())
                cache[k] = Entry(lines, times, mod)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to load custom lyrics", e)
        }
    }

    @Synchronized
    private fun persist() {
        val f = file ?: return
        try {
            val root = JSONObject()
            for ((k, entry) in cache) {
                val obj = JSONObject()
                val linesArr = JSONArray()
                for (line in entry.lines) linesArr.put(line)
                val timesArr = JSONArray()
                for (t in entry.timesMs) {
                    if (t == null) timesArr.put(JSONObject.NULL)
                    else timesArr.put(t / 1000.0) // save as seconds for multi-platform sync compatibility
                }
                obj.put("lines", linesArr)
                obj.put("times", timesArr)
                obj.put("modified", entry.modified)
                root.put(k, obj)
            }
            f.writeText(root.toString())
        } catch (e: Exception) {
            Log.w(TAG, "Failed to write custom lyrics", e)
        }
    }

    @Synchronized
    fun getLyrics(title: String, artist: String): Pair<List<LyricLine>?, String?>? {
        val entry = cache[key(title, artist)] ?: return null
        if (entry.lines.isEmpty()) return null
        val plain = entry.lines.joinToString("\n")
        val filled = entry.filledTimesMs
        val synced = if (filled != null) {
            entry.lines.zip(filled).map { (text, timeMs) -> LyricLine(timeMs, text) }.sortedBy { it.timeMs }
        } else null
        return Pair(synced, plain)
    }

    @Synchronized
    fun getEntry(title: String, artist: String): Entry? {
        return cache[key(title, artist)]
    }

    @Synchronized
    fun saveLyrics(title: String, artist: String, lines: List<String>, timesMs: List<Long?>) {
        val k = key(title, artist)
        cache[k] = Entry(lines, timesMs, System.currentTimeMillis())
        persist()
    }

    @Synchronized
    fun removeLyrics(title: String, artist: String) {
        cache.remove(key(title, artist))
        persist()
    }
}
