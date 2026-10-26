package com.antigravity.auraplayer.service

import android.content.Context
import android.util.Log
import com.antigravity.auraplayer.model.MediaTrack
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.URLEncoder
import java.text.Normalizer
import java.util.concurrent.TimeUnit

internal object Http {
    val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

    /** Body of a successful GET, or null on any network trouble */
    fun get(url: String, headers: Map<String, String> = emptyMap()): String? = try {
        val req = Request.Builder().url(url).apply { headers.forEach { (k, v) -> header(k, v) } }.build()
        client.newCall(req).execute().use { r -> if (r.isSuccessful) r.body?.string() else null }
    } catch (e: Exception) {
        null
    }

    fun enc(s: String): String = URLEncoder.encode(s, "UTF-8")
}

/** A name → URL map saved as JSON in the app's files, seeded from the Mac's copy in assets. */
internal class DiskCache(private val fileName: String) {
    private val map = mutableMapOf<String, String>()
    private var file: File? = null
    private var unsaved = 0

    @Synchronized
    fun init(context: Context) {
        if (file != null) return
        val f = File(context.filesDir, fileName)
        file = f
        val text = if (f.exists()) f.readText() else try {
            context.assets.open(fileName).bufferedReader().use { it.readText() }   // first launch: the Mac's lookups
        } catch (e: Exception) { null }
        if (text != null) try {
            val o = JSONObject(text)
            o.keys().forEach { k -> map[k] = o.getString(k) }
        } catch (e: Exception) { }
    }

    @Synchronized
    operator fun get(key: String): String? = map[key]

    @Synchronized
    fun put(key: String, value: String) {
        map[key] = value
        if (++unsaved >= 5) save()
    }

    @Synchronized
    fun save() {
        unsaved = 0
        val f = file ?: return
        try { f.writeText(JSONObject(map as Map<*, *>).toString()) } catch (e: Exception) { }
    }
}

/** Singer / artist photos from Deezer's free artist search, remembered on disk (same as the Mac app). */
object ArtistPhotoService {
    private val cache = DiskCache("artist_photos.json")
    private val mutex = Mutex()
    private var nextSlot = 0L

    fun init(context: Context) = cache.init(context)

    /** Lowercase letters and digits only, so "A.R. Rahman" == "A. R. Rahman". */
    fun normalize(name: String): String =
        Normalizer.normalize(name, Normalizer.Form.NFD).lowercase().filter { it.isLetterOrDigit() }

    /** Same artist: equal, or one is the other plus a short extra ("Sid Sriram" vs "Sid Sriram Official"). */
    fun namesMatch(wanted: String, found: String): Boolean {
        if (wanted.isEmpty() || found.isEmpty()) return false
        if (wanted == found) return true
        val (short, long) = if (wanted.length <= found.length) wanted to found else found to wanted
        return short.length >= 5 && long.contains(short) && short.length.toDouble() / long.length >= 0.75
    }

    /** "Zedd & Katy Perry" → "Zedd" */
    fun firstArtist(name: String): String {
        var n = name.replace(Regex("\\s*[(\\[].*$"), "")
        for (sep in listOf(" & ", ",", " feat.", " feat ", " ft.", " ft ", " featuring ", " x ", " and ", ";")) {
            val i = n.indexOf(sep, ignoreCase = true)
            if (i >= 0) n = n.substring(0, i)
        }
        return n.trim()
    }

    suspend fun photoUrl(artistName: String): String? = withContext(Dispatchers.IO) {
        val name = artistName.trim()
        val key = normalize(name)
        if (key.length < 2) return@withContext null
        cache[key]?.let { return@withContext it.ifEmpty { null } }
        // Deezer allows ~50 requests per 5 seconds: space requests out
        mutex.withLock {
            val wait = nextSlot - System.currentTimeMillis()
            if (wait > 0) delay(wait)
            nextSlot = System.currentTimeMillis() + 150
        }
        val body = Http.get("https://api.deezer.com/search/artist?q=${Http.enc(name)}&limit=8") ?: return@withContext null
        val found = try {
            val data = JSONObject(body).optJSONArray("data") ?: JSONArray()
            var best: JSONObject? = null
            for (i in 0 until data.length()) {
                val a = data.getJSONObject(i)
                if (!namesMatch(key, normalize(a.optString("name")))) continue
                if (best == null || a.optInt("nb_fan") > best.optInt("nb_fan")) best = a
            }
            val pic = best?.optString("picture_xl")?.ifEmpty { best.optString("picture_big") } ?: ""
            if (pic.contains("/images/artist//")) "" else pic
        } catch (e: Exception) { return@withContext null }
        cache.put(key, found)
        found.ifEmpty { null }
    }
}

/** Album covers from Apple's free iTunes search, matched carefully so a song never gets a wrong cover. */
object TrackArtworkService {
    private val cache = DiskCache("track_artwork.json")
    private val mutex = Mutex()
    private var nextSlot = 0L

    fun init(context: Context) = cache.init(context)

    private fun key(t: MediaTrack) =
        "${ArtistPhotoService.normalize(t.coreTitle)}|${ArtistPhotoService.normalize(ArtistPhotoService.firstArtist(t.artist))}"

    private fun isMiss(v: String) = v.isEmpty() || v.startsWith("miss:")

    /** Cover already known for this song, without any network call */
    fun cachedCover(t: MediaTrack): String? = cache[key(t)]?.takeIf { !isMiss(it) }

    suspend fun cover(t: MediaTrack): String? = withContext(Dispatchers.IO) {
        val k = key(t)
        cache[k]?.let { v ->
            if (!isMiss(v)) return@withContext v
            // Misses are retried after a day
            val at = v.removePrefix("miss:").toLongOrNull() ?: 0L
            if (System.currentTimeMillis() / 1000 - at < 86_400) return@withContext null
        }
        val title = t.coreTitle
        val artist = ArtistPhotoService.firstArtist(t.artist)
        if (title.isEmpty()) return@withContext null
        val queries = listOfNotNull("$title $artist", t.movieName?.let { "$title $it" }, title)
        for (q in queries) {
            mutex.withLock {
                val wait = nextSlot - System.currentTimeMillis()
                if (wait > 0) delay(wait)
                nextSlot = System.currentTimeMillis() + 350
            }
            val body = Http.get("https://itunes.apple.com/search?term=${Http.enc(q)}&entity=song&limit=12")
                ?: return@withContext null   // network trouble: don't remember a miss
            val results = try { JSONObject(body).optJSONArray("results") ?: JSONArray() } catch (e: Exception) { JSONArray() }
            bestCover(results, t, title, artist)?.let { cache.put(k, it); return@withContext it }
        }
        cache.put(k, "miss:${System.currentTimeMillis() / 1000}")
        null
    }

    /** Title must match and the artist (or album) must fit */
    private fun bestCover(results: JSONArray, t: MediaTrack, title: String, artist: String): String? {
        val n = ArtistPhotoService::normalize
        val wantedTitle = n(title)
        val artistWords = artist.lowercase().split(Regex("[^\\p{L}\\p{N}]+")).filter { it.length >= 3 }
        val wantedAlbum = n(MediaTrack.removingBrackets(t.album ?: ""))
        for (i in 0 until results.length()) {
            val item = results.getJSONObject(i)
            val foundTitle = n(MediaTrack.removingBrackets(item.optString("trackName")))
            if (foundTitle.isEmpty()) continue
            val titleOk = foundTitle == wantedTitle || (minOf(foundTitle.length, wantedTitle.length) >= 6 &&
                (foundTitle.contains(wantedTitle) || wantedTitle.contains(foundTitle)))
            if (!titleOk) continue
            val foundArtist = n(item.optString("artistName"))
            val foundAlbum = n(MediaTrack.removingBrackets(item.optString("collectionName")))
            val artistFits = artistWords.any { foundArtist.contains(n(it)) }
            val albumFits = wantedAlbum.isNotEmpty() && foundAlbum.length >= 3 &&
                (foundAlbum == wantedAlbum || foundAlbum.contains(wantedAlbum) || wantedAlbum.contains(foundAlbum))
            if (!artistFits && !albumFits) continue
            val small = item.optString("artworkUrl100")
            if (small.isNotEmpty()) return small.replace("100x100bb", "600x600bb")
        }
        return null
    }

    fun flush() = cache.save()
}

