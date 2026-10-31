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
            if (parsedSynced != null || plainLyrics != null) {
                return@withContext Pair(parsedSynced, plainLyrics)
            }
            val saavn = fetchFromJioSaavn(cleanTrack, cleanArtist)
            if (saavn.first != null || saavn.second != null) return@withContext saavn
            fetchFromLyricsOvh(cleanTrack, cleanArtist)
        } catch (e: Exception) {
            val saavn = fetchFromJioSaavn(cleanTrack, cleanArtist)
            if (saavn.first != null || saavn.second != null) return@withContext saavn
            fetchFromLyricsOvh(cleanTrack, cleanArtist)
        }
    }

    private fun fetchFromLyricsOvh(title: String, artist: String): Pair<List<LyricLine>?, String?> {
        try {
            val cleanTitle = title.replace(Regex("""\s*[\(\[].*$"""), "").trim()
            val cleanArt = artist.split(Regex("""\s*(&|,|feat\.?|ft\.?)\s*""", RegexOption.IGNORE_CASE))[0].trim()
            val encArt = URLEncoder.encode(cleanArt, "UTF-8")
            val encTitle = URLEncoder.encode(cleanTitle, "UTF-8")
            val url = "https://api.lyrics.ovh/v1/$encArt/$encTitle"
            val req = Request.Builder().url(url).header("User-Agent", "Mozilla/5.0").build()
            val resp = client.newCall(req).execute()
            if (!resp.isSuccessful) return Pair(null, null)
            val json = JSONObject(resp.body?.string() ?: return Pair(null, null))
            val text = json.optString("lyrics", "")
            if (text.length > 30) {
                val lines = text.split("\n").map { it.trim() }.filter { it.isNotEmpty() }
                val synced = lines.mapIndexed { i, l ->
                    LyricLine(timeMs = 15000L + i * 5000L, text = l)
                }
                return Pair(synced, text)
            }
        } catch (ignored: Exception) {}
        return Pair(null, null)
    }

    private fun fetchFromJioSaavn(title: String, artist: String): Pair<List<LyricLine>?, String?> {
        try {
            val query = URLEncoder.encode("$title $artist", "UTF-8")
            val searchUrl = "https://www.jiosaavn.com/api.php?__call=autocomplete.get&_format=json&_marker=0&cc=in&includeMetaTags=1&query=$query"
            val req = Request.Builder().url(searchUrl).header("User-Agent", "Mozilla/5.0").build()
            val resp = client.newCall(req).execute()
            if (!resp.isSuccessful) return Pair(null, null)
            val json = JSONObject(resp.body?.string() ?: return Pair(null, null))
            val songs = json.optJSONObject("songs")?.optJSONArray("data") ?: return Pair(null, null)
            if (songs.length() == 0) return Pair(null, null)
            val songUrl = songs.getJSONObject(0).optString("url")
            if (songUrl.isNullOrEmpty()) return Pair(null, null)

            val pageReq = Request.Builder().url(songUrl).header("User-Agent", "Mozilla/5.0").build()
            val pageResp = client.newCall(pageReq).execute()
            if (!pageResp.isSuccessful) return Pair(null, null)
            val html = pageResp.body?.string() ?: return Pair(null, null)

            val m = Pattern.compile("\"lyrics\":\\{(\"content\":\".*?\"),\"copyright\"").matcher(html)
            if (m.find()) {
                val frag = JSONObject("{" + m.group(1) + "}")
                val content = frag.optString("content", "")
                if (content.isNotBlank()) {
                    val lines = content.split("\n").map { it.trim() }.filter { it.isNotEmpty() }
                    val synced = lines.mapIndexed { i, text ->
                        LyricLine(timeMs = 15000L + i * 5000L, text = text)
                    }
                    return Pair(synced, content)
                }
            }
        } catch (ignored: Exception) {}
        return Pair(null, null)
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
