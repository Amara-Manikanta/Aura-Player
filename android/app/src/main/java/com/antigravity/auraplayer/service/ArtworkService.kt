package com.antigravity.auraplayer.service

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

object ArtworkService {
    private val client = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .readTimeout(8, TimeUnit.SECONDS)
        .build()

    suspend fun fetchArtwork(trackName: String, artistName: String): String? = withContext(Dispatchers.IO) {
        val cleanTrack = trackName
            .replace(Regex("\\[.*?\\]"), "")
            .replace(Regex("\\(.*?\\)"), "")
            .trim()
        val query = "$cleanTrack $artistName"
        val encoded = URLEncoder.encode(query, "UTF-8")
        val url = "https://itunes.apple.com/search?term=$encoded&entity=song&limit=1"

        try {
            val request = Request.Builder()
                .url(url)
                .header("User-Agent", "AuraPlayer/1.0 (Android)")
                .build()

            val response = client.newCall(request).execute()
            if (!response.isSuccessful) return@withContext null

            val body = response.body?.string() ?: return@withContext null
            val json = JSONObject(body)
            val results = json.optJSONArray("results") ?: return@withContext null

            if (results.length() > 0) {
                val item = results.getJSONObject(0)
                val artwork100 = item.optString("artworkUrl100")
                if (artwork100.isNotEmpty()) {
                    return@withContext artwork100.replace("100x100bb", "600x600bb")
                }
            }
            null
        } catch (e: Exception) {
            null
        }
    }
}
