package com.antigravity.auraplayer.service

import com.antigravity.auraplayer.model.LyricLine
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.net.URLEncoder
import java.util.concurrent.TimeUnit
import java.util.regex.Pattern

object LyricsService {
    private val client = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(8, TimeUnit.SECONDS)
        .build()

    suspend fun fetchLyrics(
        trackName: String,
        artistName: String,
        durationSeconds: Double = 0.0
    ): Pair<List<LyricLine>?, String?> = withContext(Dispatchers.IO) {
        // User-provided or edited lyrics always take precedence
        CustomLyricsStore.getLyrics(trackName, artistName)?.let { return@withContext it }

        val cleanMetadata = com.antigravity.auraplayer.utils.MetadataCleaner.clean(trackName, artistName)
        val cleanTrack = cleanMetadata.cleanTitle
        val cleanArtist = cleanMetadata.primaryArtist

        val encTrack = URLEncoder.encode(cleanTrack, "UTF-8")
        val encArtist = URLEncoder.encode(cleanArtist, "UTF-8")

        var url = "https://lrclib.net/api/get?track_name=$encTrack&artist_name=$encArtist"
        if (durationSeconds > 10) {
            url += "&duration=${durationSeconds.toInt()}"
        }

        try {
            val request = Request.Builder()
                .url(url)
                .header("User-Agent", "AuraPlayer/1.0 (Android)")
                .build()

            val response = client.newCall(request).execute()
            if (!response.isSuccessful) {
                return@withContext Pair(null, null)
            }

            val body = response.body?.string() ?: return@withContext Pair(null, null)
            val json = JSONObject(body)

            val syncedLyrics = if (json.has("syncedLyrics") && !json.isNull("syncedLyrics")) {
                json.getString("syncedLyrics")
            } else null

            val plainLyrics = if (json.has("plainLyrics") && !json.isNull("plainLyrics")) {
                json.getString("plainLyrics")
            } else null

            val parsedSynced = syncedLyrics?.let { parseLRC(it) }
            Pair(parsedSynced, plainLyrics)
        } catch (e: Exception) {
            Pair(null, null)
        }
    }

    private fun parseLRC(lrcText: String): List<LyricLine> {
        val lines = lrcText.split("\n")
        val pattern = Pattern.compile("\\[(\\d+):(\\d+(?:\\.\\d+)?)\\](.*)")
        val result = mutableListOf<LyricLine>()

        for (line in lines) {
            val matcher = pattern.matcher(line)
            if (matcher.find()) {
                val mins = matcher.group(1)?.toLongOrNull() ?: 0L
                val secs = matcher.group(2)?.toDoubleOrNull() ?: 0.0
                val text = matcher.group(3)?.trim() ?: ""
                val totalMs = (mins * 60 * 1000) + (secs * 1000).toLong()
                if (text.isNotEmpty()) {
                    result.add(LyricLine(timeMs = totalMs, text = text))
                }
            }
        }
        return result.sortedBy { it.timeMs }
    }

}
