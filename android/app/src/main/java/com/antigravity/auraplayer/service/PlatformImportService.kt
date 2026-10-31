package com.antigravity.auraplayer.service

import android.util.Log
import com.antigravity.auraplayer.model.MediaTrack
import com.antigravity.auraplayer.model.MediaType
import com.antigravity.auraplayer.model.TrackSourceType
import com.antigravity.auraplayer.utils.MetadataCleaner
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import okhttp3.OkHttpClient
import okhttp3.Request
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.playlist.PlaylistInfo
import org.schabi.newpipe.extractor.stream.StreamInfoItem
import java.util.concurrent.TimeUnit

enum class PlatformType(val displayName: String, val badgeColor: Long) {
    YOUTUBE("YouTube", 0xFFFF0000),
    SPOTIFY("Spotify", 0xFF1DB954),
    JIOSAAVN("JioSaavn", 0xFF2BC5B4),
    GAANA("Gaana", 0xFFE72C30),
    AMAZON_MUSIC("Amazon Music", 0xFF00A8E1),
    APPLE_MUSIC("Apple Music", 0xFFFC3C44),
    TEXT("Track List", 0xFF8A2BE2)
}

data class ImportedPlaylist(
    val name: String,
    val platform: PlatformType,
    val tracks: List<MediaTrack>,
    val sourceUrl: String? = null
)

/**
 * Universal importer for music playlists and tracks from YouTube, Spotify, JioSaavn,
 * Gaana, Amazon Music, Apple Music, and plain text song lists.
 */
object PlatformImportService {
    private const val TAG = "AuraPlayer/Import"

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .followRedirects(true)
        .build()

    private val jsonParser = Json {
        ignoreUnknownKeys = true
        isLenient = true
        coerceInputValues = true
    }

    private const val DESKTOP_UA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    /**
     * Real-time platform detector for live badges in the UI.
     */
    fun detectPlatform(input: String): PlatformType? {
        val lower = input.trim().lowercase()
        if (lower.isEmpty()) return null

        return when {
            lower.contains("youtube.com") || lower.contains("youtu.be") -> PlatformType.YOUTUBE
            lower.contains("spotify.com") || lower.startsWith("spotify:") -> PlatformType.SPOTIFY
            lower.contains("jiosaavn.com") -> PlatformType.JIOSAAVN
            lower.contains("gaana.com") -> PlatformType.GAANA
            lower.contains("music.amazon") || lower.contains("amazon.com/music") || lower.contains("amazon.in/music") -> PlatformType.AMAZON_MUSIC
            lower.contains("music.apple.com") -> PlatformType.APPLE_MUSIC
            lower.lines().size > 1 || lower.contains(" - ") || lower.contains(" – ") || lower.contains(" — ") -> PlatformType.TEXT
            lower.startsWith("http://") || lower.startsWith("https://") -> PlatformType.TEXT
            else -> PlatformType.TEXT
        }
    }

    /**
     * Parses the link or multi-line text and extracts playlist metadata and track list.
     */
    suspend fun parseLinkOrText(input: String): Result<ImportedPlaylist> = withContext(Dispatchers.IO) {
        try {
            val trimmed = input.trim()
            if (trimmed.isEmpty()) {
                return@withContext Result.failure(IllegalArgumentException("Please paste a link or song list"))
            }

            val platform = detectPlatform(trimmed)
            val result = when (platform) {
                PlatformType.YOUTUBE -> importYouTube(trimmed)
                PlatformType.SPOTIFY -> importSpotify(trimmed)
                PlatformType.JIOSAAVN -> importJioSaavn(trimmed)
                PlatformType.GAANA -> importGenericWeb(trimmed, PlatformType.GAANA)
                PlatformType.AMAZON_MUSIC -> importGenericWeb(trimmed, PlatformType.AMAZON_MUSIC)
                PlatformType.APPLE_MUSIC -> importGenericWeb(trimmed, PlatformType.APPLE_MUSIC)
                PlatformType.TEXT, null -> {
                    if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
                        try {
                            importGenericWeb(trimmed, PlatformType.TEXT)
                        } catch (e: Exception) {
                            importTextList(trimmed)
                        }
                    } else {
                        importTextList(trimmed)
                    }
                }
            }
            Result.success(result)
        } catch (e: Exception) {
            Log.e(TAG, "Import error", e)
            Result.failure(e)
        }
    }

    // region YouTube & YouTube Music

    private suspend fun importYouTube(input: String): ImportedPlaylist = withContext(Dispatchers.IO) {
        val cleanUrl = Regex("https?://[^\\s]+").find(input)?.value ?: input.trim()

        if (cleanUrl.contains("list=")) {
            // YouTube Playlist
            val info = PlaylistInfo.getInfo(ServiceList.YouTube, cleanUrl)
            val playlistTitle = info.name.ifBlank { "YouTube Playlist" }

            val allItems = mutableListOf<StreamInfoItem>()
            allItems.addAll(info.relatedItems.filterIsInstance<StreamInfoItem>())

            var currentPage = if (info.hasNextPage()) info.nextPage else null
            var pagesFetched = 0
            while (currentPage != null && pagesFetched < 4 && allItems.size < 200) {
                try {
                    val more = PlaylistInfo.getMoreItems(ServiceList.YouTube, cleanUrl, currentPage)
                    allItems.addAll(more.items.filterIsInstance<StreamInfoItem>())
                    currentPage = if (more.hasNextPage()) more.nextPage else null
                    pagesFetched++
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to load more YouTube playlist items", e)
                    break
                }
            }

            val tracks = allItems.mapNotNull { item ->
                val id = YouTubeService.extractVideoId(item.url)
                val clean = MetadataCleaner.clean(item.name, item.uploaderName ?: "")
                MediaTrack(
                    title = clean.toDisplayTitle(),
                    artist = clean.cleanArtist.ifBlank { item.uploaderName ?: "YouTube" },
                    duration = item.duration.toDouble().coerceAtLeast(0.0),
                    sourceType = TrackSourceType.YOUTUBE,
                    mediaType = MediaType.VIDEO,
                    originalURL = item.url,
                    thumbnailURL = id?.let { "https://i.ytimg.com/vi/$it/hqdefault.jpg" },
                    youtubeId = id
                )
            }

            if (tracks.isEmpty()) {
                throw IllegalStateException("No playable songs found in YouTube playlist")
            }

            ImportedPlaylist(
                name = playlistTitle,
                platform = PlatformType.YOUTUBE,
                tracks = tracks,
                sourceUrl = cleanUrl
            )
        } else {
            // Single YouTube Video
            val track = YouTubeService.fetchTrack(cleanUrl)
                ?: throw IllegalArgumentException("Could not extract YouTube video from link")
            ImportedPlaylist(
                name = track.title,
                platform = PlatformType.YOUTUBE,
                tracks = listOf(track),
                sourceUrl = cleanUrl
            )
        }
    }

    // endregion

    // region Spotify

    private suspend fun importSpotify(input: String): ImportedPlaylist = withContext(Dispatchers.IO) {
        val typeAndId = Regex("(playlist|album|track)[/:]([a-zA-Z0-9]+)").find(input)
            ?: throw IllegalArgumentException("Invalid Spotify link. Expected playlist, album, or track URL.")
        val type = typeAndId.groupValues[1]
        val id = typeAndId.groupValues[2]

        val embedUrl = "https://open.spotify.com/embed/$type/$id"
        val req = Request.Builder()
            .url(embedUrl)
            .header("User-Agent", DESKTOP_UA)
            .build()

        val response = httpClient.newCall(req).execute()
        if (!response.isSuccessful) {
            throw IllegalStateException("Spotify returned error code ${response.code}")
        }
        val html = response.body?.string() ?: throw IllegalStateException("Empty response from Spotify")

        val jsonMatch = Regex("<script id=\"__NEXT_DATA__\"[^>]*>(.*?)</script>").find(html)
            ?: throw IllegalStateException("Could not parse Spotify data")

        val root = jsonParser.parseToJsonElement(jsonMatch.groupValues[1]).jsonObject
        val entity = root["props"]
            ?.jsonObject?.get("pageProps")
            ?.jsonObject?.get("state")
            ?.jsonObject?.get("data")
            ?.jsonObject?.get("entity")
            ?.jsonObject
            ?: throw IllegalStateException("Spotify metadata entity not found")

        val entityName = entity["name"]?.jsonPrimitive?.contentOrNull?.ifBlank { null }
            ?: entity["title"]?.jsonPrimitive?.contentOrNull?.ifBlank { null }
            ?: "Spotify Import"

        val tracks = mutableListOf<MediaTrack>()
        val trackList = entity["trackList"]?.jsonArray

        if (trackList != null && trackList.isNotEmpty()) {
            for (trackElement in trackList) {
                val item = trackElement.jsonObject
                val rawTitle = item["title"]?.jsonPrimitive?.contentOrNull?.ifBlank { null }
                    ?: item["name"]?.jsonPrimitive?.contentOrNull ?: ""
                var rawArtist = item["subtitle"]?.jsonPrimitive?.contentOrNull ?: ""
                if (rawArtist.isBlank()) {
                    val artistsArr = item["artists"]?.jsonArray
                    if (!artistsArr.isNullOrEmpty()) {
                        val names = artistsArr.mapNotNull { it.jsonObject["name"]?.jsonPrimitive?.contentOrNull }
                        rawArtist = names.joinToString(", ")
                    }
                }
                val durationMs = item["duration"]?.jsonPrimitive?.longOrNull ?: 0L
                val clean = MetadataCleaner.clean(rawTitle, rawArtist)
                tracks.add(
                    MediaTrack(
                        title = clean.toDisplayTitle(),
                        artist = clean.cleanArtist.ifBlank { "Unknown Artist" },
                        duration = (durationMs / 1000.0).coerceAtLeast(0.0),
                        sourceType = TrackSourceType.YOUTUBE,
                        mediaType = MediaType.VIDEO
                    )
                )
            }
        } else {
            // Single track
            val rawTitle = entity["name"]?.jsonPrimitive?.contentOrNull?.ifBlank { null }
                ?: entity["title"]?.jsonPrimitive?.contentOrNull ?: ""
            var rawArtist = ""
            val artistsArr = entity["artists"]?.jsonArray
            if (!artistsArr.isNullOrEmpty()) {
                val names = artistsArr.mapNotNull { it.jsonObject["name"]?.jsonPrimitive?.contentOrNull }
                rawArtist = names.joinToString(", ")
            }
            val durationMs = entity["duration"]?.jsonPrimitive?.longOrNull ?: 0L
            val clean = MetadataCleaner.clean(rawTitle, rawArtist)
            tracks.add(
                MediaTrack(
                    title = clean.toDisplayTitle(),
                    artist = clean.cleanArtist.ifBlank { "Unknown Artist" },
                    duration = (durationMs / 1000.0).coerceAtLeast(0.0),
                    sourceType = TrackSourceType.YOUTUBE,
                    mediaType = MediaType.VIDEO
                )
            )
        }

        if (tracks.isEmpty()) {
            throw IllegalStateException("No tracks found in Spotify link")
        }

        ImportedPlaylist(
            name = entityName,
            platform = PlatformType.SPOTIFY,
            tracks = tracks,
            sourceUrl = embedUrl
        )
    }

    // endregion

    // region JioSaavn

    private suspend fun importJioSaavn(input: String): ImportedPlaylist = withContext(Dispatchers.IO) {
        val cleanUrl = Regex("https?://[^\\s]+").find(input)?.value ?: input.trim()
        val type = when {
            cleanUrl.contains("/album/") -> "album"
            cleanUrl.contains("/song/") -> "song"
            else -> "playlist"
        }

        val token = cleanUrl.trimEnd('/').substringAfterLast('/')
        if (token.isBlank()) throw IllegalArgumentException("Could not extract JioSaavn ID from link")

        val apiUrl = "https://www.jiosaavn.com/api.php?__call=webapi.get&token=$token&type=$type&_format=json&_marker=0&ctx=web6dot0"
        val req = Request.Builder()
            .url(apiUrl)
            .header("User-Agent", DESKTOP_UA)
            .header("Cookie", "L=english")
            .build()

        val response = httpClient.newCall(req).execute()
        if (!response.isSuccessful) {
            throw IllegalStateException("JioSaavn returned error code ${response.code}")
        }
        val jsonStr = response.body?.string() ?: throw IllegalStateException("Empty JioSaavn response")
        val data = jsonParser.parseToJsonElement(jsonStr).jsonObject

        val playlistName = data["listname"]?.jsonPrimitive?.contentOrNull?.ifBlank { null }
            ?: data["title"]?.jsonPrimitive?.contentOrNull?.ifBlank { null }
            ?: data["name"]?.jsonPrimitive?.contentOrNull?.ifBlank { null }
            ?: "JioSaavn Import"

        val songsArray = data["songs"]?.jsonArray ?: data["list"]?.jsonArray
        val tracks = mutableListOf<MediaTrack>()

        if (songsArray != null && songsArray.isNotEmpty()) {
            for (songElement in songsArray) {
                val song = songElement.jsonObject
                val rawTitle = song["song"]?.jsonPrimitive?.contentOrNull?.ifBlank { null }
                    ?: song["title"]?.jsonPrimitive?.contentOrNull ?: ""
                val rawArtist = song["singers"]?.jsonPrimitive?.contentOrNull?.ifBlank { null }
                    ?: song["primary_artists"]?.jsonPrimitive?.contentOrNull ?: ""
                val dur = song["duration"]?.jsonPrimitive?.doubleOrNull
                    ?: (song["duration"]?.jsonPrimitive?.longOrNull?.toDouble() ?: 0.0)
                val album = song["album"]?.jsonPrimitive?.contentOrNull
                val image = song["image"]?.jsonPrimitive?.contentOrNull?.replace("150x150", "500x500")

                val clean = MetadataCleaner.clean(rawTitle, rawArtist)
                tracks.add(
                    MediaTrack(
                        title = clean.toDisplayTitle(),
                        artist = clean.cleanArtist.ifBlank { "Unknown Artist" },
                        album = album?.ifBlank { null },
                        duration = dur,
                        thumbnailURL = image?.ifBlank { null },
                        sourceType = TrackSourceType.YOUTUBE,
                        mediaType = MediaType.VIDEO
                    )
                )
            }
        }

        if (tracks.isEmpty()) {
            throw IllegalStateException("No songs found in JioSaavn link")
        }

        ImportedPlaylist(
            name = playlistName,
            platform = PlatformType.JIOSAAVN,
            tracks = tracks,
            sourceUrl = cleanUrl
        )
    }

    // endregion

    // region Gaana, Amazon Music, Apple Music, Generic Web

    private suspend fun importGenericWeb(input: String, platform: PlatformType): ImportedPlaylist = withContext(Dispatchers.IO) {
        // 1. Check share message text first
        parseShareText(input)?.let { (title, artist) ->
            val clean = MetadataCleaner.clean(title, artist)
            val track = MediaTrack(
                title = clean.toDisplayTitle(),
                artist = clean.cleanArtist.ifBlank { "Unknown Artist" },
                sourceType = TrackSourceType.YOUTUBE,
                mediaType = MediaType.VIDEO
            )
            return@withContext ImportedPlaylist(
                name = track.title,
                platform = platform,
                tracks = listOf(track),
                sourceUrl = Regex("https?://[^\\s]+").find(input)?.value
            )
        }

        // 2. Fetch page HTML and inspect OpenGraph / title
        val url = Regex("https?://[^\\s]+").find(input)?.value
            ?: throw IllegalArgumentException("No URL found in input")

        val req = Request.Builder()
            .url(url)
            .header("User-Agent", DESKTOP_UA)
            .build()

        val response = httpClient.newCall(req).execute()
        val html = response.body?.string() ?: ""

        var title = Regex("<meta property=\"og:title\" content=\"([^\"]+)\"").find(html)?.groupValues?.get(1)
            ?: Regex("<title>([^<]+)</title>", RegexOption.IGNORE_CASE).find(html)?.groupValues?.get(1)
            ?: ""

        var desc = Regex("<meta property=\"og:description\" content=\"([^\"]+)\"").find(html)?.groupValues?.get(1)
            ?: Regex("<meta name=\"description\" content=\"([^\"]+)\"").find(html)?.groupValues?.get(1)
            ?: ""

        title = sanitizeHtmlEntities(title)
        desc = sanitizeHtmlEntities(desc)

        // Strip brand suffixes e.g. " - Song by X | Gaana", " on Apple Music"
        title = title
            .replace(Regex("(?i)\\s*[-|–—]\\s*(Gaana|Amazon Music|Apple Music|Spotify).*$"), "")
            .replace(Regex("(?i)\\s+(on\\s+Apple\\s+Music|on\\s+Amazon\\s+Music|on\\s+Gaana).*$"), "")
            .trim()

        var artist = ""
        if (title.contains(" by ", ignoreCase = true)) {
            val parts = title.split(Regex("(?i)\\s+by\\s+"))
            title = parts[0].trim()
            artist = parts.getOrNull(1)?.trim() ?: ""
        } else if (desc.contains(" by ", ignoreCase = true)) {
            val parts = desc.split(Regex("(?i)\\s+by\\s+"))
            artist = parts.getOrNull(1)?.split(Regex("[,.]"))?.getOrNull(0)?.trim() ?: ""
        }

        if (title.isBlank()) {
            throw IllegalStateException("Could not extract song info from link")
        }

        val clean = MetadataCleaner.clean(title, artist)
        val track = MediaTrack(
            title = clean.toDisplayTitle(),
            artist = clean.cleanArtist.ifBlank { "Unknown Artist" },
            sourceType = TrackSourceType.YOUTUBE,
            mediaType = MediaType.VIDEO
        )

        ImportedPlaylist(
            name = track.title,
            platform = platform,
            tracks = listOf(track),
            sourceUrl = url
        )
    }

    // endregion

    // region Plain Text / Track List

    private fun importTextList(text: String): ImportedPlaylist {
        val lines = text.lines()
        val tracks = mutableListOf<MediaTrack>()

        for (rawLine in lines) {
            val trimmed = rawLine.trim()
            if (trimmed.isBlank() || trimmed.startsWith("#") || trimmed.startsWith("//")) continue

            val share = parseShareText(trimmed)
            if (share != null) {
                val clean = MetadataCleaner.clean(share.first, share.second)
                tracks.add(
                    MediaTrack(
                        title = clean.toDisplayTitle(),
                        artist = clean.cleanArtist.ifBlank { "Unknown Artist" },
                        sourceType = TrackSourceType.YOUTUBE,
                        mediaType = MediaType.VIDEO
                    )
                )
                continue
            }

            // Strip track numbers e.g. "1. ", "01) ", "2 - "
            val noNumber = trimmed.replace(Regex("^\\s*\\d+[.)\\-:\\s]+\\s*"), "").trim()
            if (noNumber.isBlank()) continue

            // Split "Title - Artist" or "Artist - Title"
            val parts = noNumber.split(Regex("\\s+[-–—]\\s+"), limit = 2)
            val (title, artist) = if (parts.size >= 2) {
                Pair(parts[0].trim(), parts[1].trim())
            } else {
                Pair(noNumber, "Unknown Artist")
            }

            val clean = MetadataCleaner.clean(title, artist)
            tracks.add(
                MediaTrack(
                    title = clean.toDisplayTitle(),
                    artist = clean.cleanArtist.ifBlank { "Unknown Artist" },
                    sourceType = TrackSourceType.YOUTUBE,
                    mediaType = MediaType.VIDEO
                )
            )
        }

        if (tracks.isEmpty()) {
            throw IllegalArgumentException("No song titles could be recognized from the text")
        }

        val defaultName = if (tracks.size == 1) tracks.first().title else "Imported Playlist"
        return ImportedPlaylist(
            name = defaultName,
            platform = PlatformType.TEXT,
            tracks = tracks
        )
    }

    // endregion

    // region Helpers

    private fun parseShareText(input: String): Pair<String, String>? {
        val m1 = Regex("(?i)(?:check out|listen to)\\s+[\"“']?(.+?)[\"”']?\\s+by\\s+[\"“']?(.+?)[\"”']?\\s+on\\s+").find(input)
        if (m1 != null) {
            return Pair(m1.groupValues[1].trim(), m1.groupValues[2].trim())
        }
        val m2 = Regex("(?i)listen to\\s+[\"“']?(.+?)[\"”']?\\s+on\\s+([a-zA-Z]+)").find(input)
        if (m2 != null) {
            return Pair(m2.groupValues[1].trim(), "")
        }
        return null
    }

    private fun sanitizeHtmlEntities(input: String): String = input
        .replace("&amp;", "&")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
        .replace("&#39;", "'")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&#x27;", "'")
        .replace("&nbsp;", " ")

    // endregion
}
