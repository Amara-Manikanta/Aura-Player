package com.antigravity.auraplayer.data

import android.content.Context
import android.util.Log
import com.antigravity.auraplayer.model.MediaTrack
import com.antigravity.auraplayer.model.MediaType
import com.antigravity.auraplayer.model.Playlist
import com.antigravity.auraplayer.model.TrackSourceType
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject

/**
 * Reads the Mac app's library (bundled as assets/playlists.json) into Android playlists:
 * the same 17 playlists and 3,432 songs, with play counts, added dates, albums and trims.
 */
object MacLibraryImporter {
    private const val TAG = "AuraPlayer/Import"

    /** Swift encodes dates as seconds since 1 Jan 2001 */
    private const val APPLE_EPOCH_OFFSET_SEC = 978_307_200L

    fun load(context: Context): List<Playlist> = try {
        val text = context.assets.open("playlists.json").bufferedReader().use { it.readText() }
        Json.parseToJsonElement(text).jsonArray.map { it.jsonObject.toPlaylist() }
            .also { list -> Log.i(TAG, "Mac library: ${list.size} playlists, ${list.sumOf { it.tracks.size }} songs") }
    } catch (e: Exception) {
        Log.w(TAG, "couldn't read the bundled Mac library", e)
        emptyList()
    }

    private fun JsonObject.toPlaylist() = Playlist(
        id = str("id") ?: java.util.UUID.randomUUID().toString(),
        name = (str("name") ?: "Playlist").trim(),
        iconName = str("iconName") ?: "playlist_play",
        tracks = (this["tracks"] as? JsonArray)?.map { it.jsonObject.toTrack() } ?: emptyList(),
        isBuiltIn = bool("isBuiltIn") ?: false
    )

    private fun JsonObject.toTrack(): MediaTrack {
        val title = str("title") ?: "Unknown"
        return MediaTrack(
            id = str("id") ?: java.util.UUID.randomUUID().toString(),
            title = title,
            artist = str("artist") ?: "Unknown Artist",
            duration = num("duration") ?: 0.0,
            sourceType = if (str("sourceType") == "local") TrackSourceType.LOCAL else TrackSourceType.YOUTUBE,
            mediaType = if (str("mediaType") == "audio") MediaType.AUDIO else MediaType.VIDEO,
            originalURL = str("originalURL") ?: title,
            thumbnailURL = str("thumbnailURL"),
            isFavorite = bool("isFavorite") ?: false,
            dateAdded = date("dateAdded") ?: System.currentTimeMillis(),
            youtubeId = str("youtubeId")?.takeIf { it.isNotEmpty() },
            playCount = int("playCount") ?: 0,
            lastPlayedDate = date("lastPlayedDate"),
            album = str("album"),
            composer = str("composer"),
            year = int("year"),
            genre = str("genre"),
            applePlayCount = int("applePlayCount"),
            startTime = num("startTime"),
            endTime = num("endTime"),
            rejectedVideoIds = (this["rejectedVideoIds"] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.content }
        )
    }

    private fun JsonObject.prim(key: String): JsonPrimitive? =
        (this[key] as? JsonElement)?.takeIf { it !is JsonNull } as? JsonPrimitive

    private fun JsonObject.str(key: String) = prim(key)?.takeIf { it.isString }?.content
    private fun JsonObject.num(key: String) = prim(key)?.doubleOrNull
    private fun JsonObject.int(key: String) = prim(key)?.intOrNull ?: prim(key)?.doubleOrNull?.toInt()
    private fun JsonObject.bool(key: String) = prim(key)?.booleanOrNull
    private fun JsonObject.date(key: String) =
        num(key)?.let { ((it + APPLE_EPOCH_OFFSET_SEC) * 1000).toLong() }
}
