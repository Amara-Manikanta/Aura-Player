package com.antigravity.auraplayer.service

import android.util.Log
import com.antigravity.auraplayer.model.MediaTrack
import com.antigravity.auraplayer.model.MediaType
import com.antigravity.auraplayer.model.TrackSourceType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.search.SearchInfo
import org.schabi.newpipe.extractor.services.youtube.linkHandler.YoutubeSearchQueryHandlerFactory
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.DeliveryMethod
import org.schabi.newpipe.extractor.stream.StreamInfo
import org.schabi.newpipe.extractor.stream.StreamInfoItem
import org.schabi.newpipe.extractor.stream.StreamType
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.min

data class YouTubeSearchResult(
    val id: String,
    val title: String,
    val channel: String,
    val durationSec: Double,
    val thumbnailUrl: String,
    val url: String
) {
    val formattedDuration: String
        get() {
            if (durationSec <= 0) return "--:--"
            val total = durationSec.toInt()
            val h = total / 3600
            val m = (total % 3600) / 60
            val s = total % 60
            return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
        }

    /** As a song for the library: cleaned title and singer */
    fun toTrack(): MediaTrack {
        val clean = com.antigravity.auraplayer.utils.MetadataCleaner.clean(title, channel)
        return MediaTrack(
            title = clean.toDisplayTitle(),
            artist = clean.cleanArtist,
            duration = durationSec,
            sourceType = TrackSourceType.YOUTUBE,
            mediaType = MediaType.VIDEO,
            originalURL = "https://www.youtube.com/watch?v=$id",
            thumbnailURL = thumbnailUrl,
            youtubeId = id
        )
    }

    /** As a song with its full video title and channel (Discover lists, like the Mac app) */
    fun toRawTrack() = MediaTrack(
        title = title, artist = channel, duration = durationSec,
        sourceType = TrackSourceType.YOUTUBE, mediaType = MediaType.VIDEO,
        originalURL = url, thumbnailURL = thumbnailUrl, youtubeId = id
    )
}

/** A song uploaded recently: with its views and "3 days ago" as YouTube shows it */
data class NewRelease(val video: YouTubeSearchResult, val views: Long, val uploadedAgo: String) {
    val id: String get() = video.id
}

enum class ReleasePeriod(val label: String, val filter: String) {
    WEEK("This Week", "EgQIAxAB"),   // YouTube search filter: uploaded this week, videos only
    MONTH("This Month", "EgQIBBAB")
}

/** One song of a YouTube "Mix" */
data class MixEntry(val id: String, val title: String, val channel: String, val duration: Double)

/**
 * YouTube search, video details and audio streams via NewPipeExtractor, with the same
 * "official video song first" ranking as the Mac and iPhone apps.
 */
object YouTubeService {
    private const val TAG = "AuraPlayer/YouTube"
    private val youtube = ServiceList.YouTube
    private val videoIdCache = mutableMapOf<String, String>()
    private const val BROWSER_UA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    fun extractVideoId(urlOrId: String): String? {
        val trimmed = urlOrId.trim()
        if (trimmed.length == 11 && trimmed.matches(Regex("^[a-zA-Z0-9_-]{11}$"))) return trimmed
        val patterns = listOf(
            "[?&]v=([a-zA-Z0-9_-]{11})",
            "youtu\\.be/([a-zA-Z0-9_-]{11})",
            "embed/([a-zA-Z0-9_-]{11})",
            "shorts/([a-zA-Z0-9_-]{11})",
            "live/([a-zA-Z0-9_-]{11})"
        )
        for (p in patterns) {
            Regex(p).find(trimmed)?.let { return it.groupValues[1] }
        }
        return null
    }

    fun isYouTubeLink(text: String): Boolean =
        text.contains("youtube.com", ignoreCase = true) || text.contains("youtu.be", ignoreCase = true)

    // region Search

    private suspend fun rawSearch(query: String): List<YouTubeSearchResult> = withContext(Dispatchers.IO) {
        val handler = youtube.searchQHFactory.fromQuery(query, listOf(YoutubeSearchQueryHandlerFactory.VIDEOS), "")
        val info = SearchInfo.getInfo(youtube, handler)
        info.relatedItems
            .filterIsInstance<StreamInfoItem>()
            .filter { it.streamType == StreamType.VIDEO_STREAM && !it.isShortFormContent }
            .mapNotNull { item ->
                val id = extractVideoId(item.url) ?: return@mapNotNull null
                YouTubeSearchResult(
                    id = id,
                    title = item.name,
                    channel = item.uploaderName ?: "YouTube",
                    durationSec = item.duration.toDouble(),
                    thumbnailUrl = "https://i.ytimg.com/vi/$id/hqdefault.jpg",
                    url = "https://www.youtube.com/watch?v=$id"
                )
            }
    }

    /**
     * Official videos for a typed song / a known track, best first.
     * @param songTitle when resolving a known track, its song name; results without it are dropped.
     * @param movie movie / album name; results that mention it rank higher.
     * @param expectedDuration known song length in seconds; videos close to it rank higher.
     * @param language preferred language ("telugu"): that version ranks first.
     */
    suspend fun search(
        query: String,
        limit: Int = 8,
        songTitle: String? = null,
        movie: String? = null,
        expectedDuration: Double? = null,
        artist: String? = null,
        language: String? = null
    ): List<YouTubeSearchResult> {
        extractVideoId(query)?.let { id -> return rawSearch(id) }
        val raw = rawSearch(officialSearchQuery(query))
        return rankOfficialVideos(raw, query, songTitle, artist, movie, expectedDuration, language).take(limit)
    }

    /**
     * Finds the song in `language`: the normal search first (official originals rank best that way);
     * only if its top result is in another language, searches again with the language name added.
     */
    suspend fun languageAwareSearch(
        query: String, limit: Int, songTitle: String?, artist: String?, movie: String?,
        expectedDuration: Double?, language: String?
    ): List<YouTubeSearchResult> {
        val plain = search(query, limit, songTitle, movie, expectedDuration, artist, language)
        if (language == null || query.lowercase().contains(language)) return plain
        plain.firstOrNull()?.let { if (videoLanguage(it.title, it.channel) == language) return plain }
        val dubbed = search("$query $language", limit, songTitle, movie, expectedDuration, artist, language)
        dubbed.firstOrNull()?.let {
            if (videoLanguage(it.title, it.channel) == language) {
                Log.i(TAG, "using $language version for \"$query\": ${it.title}")
                return dubbed
            }
        }
        return plain
    }

    /** The single most likely official video song for a song name. */
    suspend fun bestOfficialVideo(query: String, language: String? = null): YouTubeSearchResult? = try {
        languageAwareSearch(query, 1, null, null, null, null, language).firstOrNull()?.also {
            Log.i(TAG, "picked ${it.id} for \"$query\": ${it.title}")
        }
    } catch (e: Exception) {
        Log.w(TAG, "search failed for \"$query\"", e)
        null
    }

    /** Best official video for a saved song (uses its title, artist, movie, length and language). */
    suspend fun resolveVideo(track: MediaTrack, language: String?, excluding: Set<String> = emptySet()): String? {
        val addedByLink = track.originalURL.lowercase().startsWith("http")
        if (addedByLink && excluding.isEmpty()) extractVideoId(track.originalURL)?.let { return it }
        val query = track.videoSearchQuery
        val cacheKey = "${query.lowercase()}|${language ?: ""}"
        if (excluding.isEmpty()) videoIdCache[cacheKey]?.let { return it }

        // After a 👎 / blocked video, try a few phrasings of the same song before giving up
        val core = coreSongTitle(track.title)
        val mainArtist = track.artist.split('&', ',', '(').first().trim()
        val variants = mutableListOf(query)
        if (excluding.isNotEmpty()) {
            track.movieName?.let { variants.add("$core $it full video song") }
            if (mainArtist.isNotEmpty()) variants.add("$core $mainArtist official video")
        }
        for (variant in variants) {
            val ranked = try {
                languageAwareSearch(
                    variant, 12, if (addedByLink) null else track.title, track.artist,
                    track.movieName, track.duration.takeIf { it > 0 }, language
                )
            } catch (e: Exception) {
                Log.w(TAG, "search failed for \"$variant\"", e)
                emptyList()
            }
            ranked.firstOrNull { it.id !in excluding }?.let { best ->
                Log.i(TAG, "picked ${best.id} for \"$variant\" language=${language ?: "-"}: ${best.title}")
                videoIdCache[cacheKey] = best.id
                return best.id
            }
        }
        Log.i(TAG, "nothing for \"$query\" (excluded ${excluding.size})")
        return null
    }

    /** Kept for existing callers */
    suspend fun resolveVideoId(track: MediaTrack, excluding: Set<String> = emptySet()): String? =
        resolveVideo(track, null, excluding)

    // endregion

    // region Video details & streams

    /** Title, channel, real duration and thumbnail for a pasted link. */
    suspend fun fetchTrack(urlOrId: String): MediaTrack? = withContext(Dispatchers.IO) {
        val id = extractVideoId(urlOrId) ?: return@withContext null
        try {
            val info = StreamInfo.getInfo(youtube, "https://www.youtube.com/watch?v=$id")
            val clean = com.antigravity.auraplayer.utils.MetadataCleaner.clean(info.name, info.uploaderName ?: "YouTube")
            MediaTrack(
                title = clean.toDisplayTitle(),
                artist = clean.cleanArtist,
                duration = info.duration.toDouble(),
                sourceType = TrackSourceType.YOUTUBE,
                mediaType = MediaType.VIDEO,
                originalURL = "https://www.youtube.com/watch?v=$id",
                thumbnailURL = "https://i.ytimg.com/vi/$id/hqdefault.jpg",
                youtubeId = id
            )
        } catch (e: Exception) {
            Log.w(TAG, "fetchTrack failed for $id", e)
            null
        }
    }

    /**
     * Direct audio URL ExoPlayer can play (and keep playing in the background).
     * URLs expire after a few hours, so resolve on every play instead of storing them.
     */
    suspend fun audioStreamUrl(videoId: String): String? = withContext(Dispatchers.IO) {
        try {
            val info = StreamInfo.getInfo(youtube, "https://www.youtube.com/watch?v=$videoId")
            val playable = info.audioStreams.filter {
                it.isUrl && it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP
            }
            // Prefer M4A/AAC (widest device support), then the highest bitrate
            val best = playable.maxWithOrNull(
                compareBy<AudioStream>({ it.format?.suffix == "m4a" }, { it.averageBitrate })
            )
            Log.i(TAG, "audio for $videoId: ${playable.size} streams, picked ${best?.format?.suffix} ${best?.averageBitrate}kbps")
            best?.content
        } catch (e: Exception) {
            Log.w(TAG, "audio stream failed for $videoId", e)
            null
        }
    }

    // endregion

    // region New Releases (same search and filters as the Mac app)

    private val releaseCache = mutableMapOf<String, Pair<Long, List<NewRelease>>>()

    suspend fun newReleases(language: String, period: ReleasePeriod, forceRefresh: Boolean = false): List<NewRelease> =
        withContext(Dispatchers.IO) {
            val cacheKey = "$language|${period.name}"
            if (!forceRefresh) releaseCache[cacheKey]?.let { (at, items) ->
                if (System.currentTimeMillis() - at < 30 * 60_000) return@withContext items
            }
            val lang = language.lowercase()
            val queries = when (lang) {
                "english" -> listOf("new official music video", "official music video new song")
                "hindi" -> listOf("hindi new song official video", "bollywood new video song")
                else -> listOf("$lang new video song", "$lang latest song official video")
            }
            val seen = mutableSetOf<String>()
            val items = mutableListOf<NewRelease>()
            for (q in queries) {
                // English: ask YouTube for US results, otherwise it serves Indian songs to an Indian location
                val region = if (lang == "english") "&gl=US&hl=en" else ""
                val html = Http.get(
                    "https://www.youtube.com/results?search_query=${Http.enc(q)}&sp=${period.filter}$region",
                    mapOf("User-Agent" to BROWSER_UA, "Accept-Language" to "en-US,en;q=0.9")
                ) ?: continue
                for (item in parseSearchPage(html, 40)) {
                    if (!seen.add(item.video.id) || !looksLikeNewSong(item.video, lang)) continue
                    items.add(item)
                }
            }
            val ranked = items.sortedByDescending { releaseScore(it) }
            if (ranked.isNotEmpty()) releaseCache[cacheKey] = System.currentTimeMillis() to ranked
            Log.i(TAG, "releases $language ${period.label}: ${ranked.size} songs")
            ranked
        }

    /** Videos (with views and upload age) from a YouTube search results page */
    private fun parseSearchPage(html: String, limit: Int): List<NewRelease> {
        val marker = "var ytInitialData = "
        val start = html.indexOf(marker).takeIf { it >= 0 }?.plus(marker.length) ?: return emptyList()
        val end = html.indexOf(";</script>", start).takeIf { it > 0 } ?: return emptyList()
        val sections = try {
            JSONObject(html.substring(start, end))
                .getJSONObject("contents").getJSONObject("twoColumnSearchResultsRenderer")
                .getJSONObject("primaryContents").getJSONObject("sectionListRenderer").getJSONArray("contents")
        } catch (e: Exception) { return emptyList() }
        val out = mutableListOf<NewRelease>()
        for (i in 0 until sections.length()) {
            val items = sections.optJSONObject(i)?.optJSONObject("itemSectionRenderer")?.optJSONArray("contents") ?: continue
            for (j in 0 until items.length()) {
                val v = items.optJSONObject(j)?.optJSONObject("videoRenderer") ?: continue
                val id = v.optString("videoId")
                val title = text(v.opt("title"))
                if (id.isEmpty() || title == null) continue
                val video = YouTubeSearchResult(
                    id = id,
                    title = title,
                    channel = text(v.opt("ownerText")) ?: "YouTube",
                    durationSec = parseDuration(text(v.opt("lengthText")) ?: ""),
                    thumbnailUrl = "https://i.ytimg.com/vi/$id/hqdefault.jpg",
                    url = "https://www.youtube.com/watch?v=$id"
                )
                val views = (text(v.opt("viewCountText")) ?: "").filter { it.isDigit() }.toLongOrNull() ?: 0L
                out.add(NewRelease(video, views, text(v.opt("publishedTimeText")) ?: ""))
                if (out.size >= limit) return out
            }
        }
        return out
    }

    /** Text from YouTube's {simpleText} or {runs:[{text}]} objects */
    private fun text(any: Any?): String? {
        val o = any as? JSONObject ?: return null
        o.optString("simpleText").takeIf { it.isNotEmpty() }?.let { return it }
        val runs = o.optJSONArray("runs") ?: return null
        return (0 until runs.length()).joinToString("") { runs.optJSONObject(it)?.optString("text") ?: "" }.ifEmpty { null }
    }

    private fun parseDuration(s: String): Double =
        s.split(":").mapNotNull { it.trim().toIntOrNull() }.fold(0.0) { acc, part -> acc * 60 + part }

    /** Keeps real songs; drops trailers, teasers, jukeboxes, covers, reels, events and other languages. */
    fun looksLikeNewSong(v: YouTubeSearchResult, language: String): Boolean {
        val t = v.title.lowercase()
        if (v.url.contains("/shorts/") || v.durationSec < 90 || v.durationSec > 480) return false
        val junk = listOf("trailer", "teaser", "promo", "glimpse", "jukebox", "reaction", "cover", "status", "#shorts", "reel",
            "making", "interview", "speech", "launch", "event", "karaoke", "slowed", "reverb", "8d", "bgm",
            "scene", "full movie", "episode", "news", "review", "remix", "mashup", "dance video", "tutorial",
            "behind the scenes", "bts", "podcast", "live stream", "nonstop", "back to back", "audio jukebox",
            "performance", "pooja", "puja ceremony", "press meet", "ai song", "ai generated", "fan made")
        if (junk.any { t.contains(it) }) return false
        // Old hits re-uploaded as "8K Video Song" / remasters / classics aren't new releases
        val reissue = listOf("8k", "4k", "remaster", "classic", "classics", "evergreen", "superhit", "super hit", " hits", "old song",
            "retro", "90s", "80s", "70s", "all time", "best of", "top 10", "top 20")
        if (reissue.any { t.contains(it) }) return false
        if (listOf("song", "video", "lyric", "music", "audio", "single", "official").none { t.contains(it) }) return false
        val videoLang = videoLanguage(v.title, v.channel)
        if (language == "english") {
            if (videoLang != null) return false
            val c = v.channel.lowercase()
            val regional = listOf("bhojpuri", "santali", "bengali", "bangla", "odia", "assamese", "nepali", "kokborok",
                "garo", "haryanvi", "rajasthani", "gujarati", "marathi", "bollywood", "desi", "sambalpuri",
                "khasi", "mizo", "manipuri", "bodo", "pahadi", "garhwali", "kumaoni", "chhattisgarhi")
            if (regional.any { t.contains(it) || c.contains(it) }) return false
            if (c.contains("india") || c.contains("saregama")) return false
        } else if (videoLang != null && videoLang != language) {
            return false
        }
        return true
    }

    fun releaseScore(r: NewRelease): Double {
        val t = r.video.title.lowercase()
        val c = r.video.channel.lowercase()
        var score = log10(maxOf(r.views, 1L).toDouble())
        val labels = listOf("vevo", "t-series", "sony music", "zee music", "tips", "saregama", "aditya music", "lahari",
            "mango music", "think music", "yrf", "speed records", "times music", "anand audio", "muzik247",
            "mythri", "geetha arts", "sun tv", "divo", "junglee", "eros now",
            "atlantic", "republic records", "interscope", "columbia", "rca records", "capitol",
            "warner", "island records", "def jam", "universal music group")
        if (labels.any { c.contains(it) }) score += 3
        val channelName = c.replace(" official", "").replace("vevo", "").trim()
        if (channelName.length >= 3 && t.startsWith(channelName)) score += 3
        if (c.contains("classics")) score -= 3
        if (listOf("video song", "official video", "music video", "full video").any { t.contains(it) }) score += 2
        if (t.contains("lyric")) score -= 1.5
        if (t.contains("audio")) score -= 1
        return score
    }

    // endregion

    // region YouTube Mix (For You)

    /**
     * YouTube's "Mix" for a song (list=RD<id>): what millions of listeners play together with it.
     * Uses YouTube's own web API, the same request the website makes (no sign-in needed).
     */
    suspend fun fetchMix(videoId: String): List<MixEntry> = withContext(Dispatchers.IO) {
        val body = JSONObject()
            .put("context", JSONObject().put("client", JSONObject()
                .put("clientName", "WEB").put("clientVersion", "2.20241010.00.00").put("hl", "en").put("gl", "IN")))
            .put("videoId", videoId)
            .put("playlistId", "RD$videoId")
        val req = Request.Builder()
            .url("https://www.youtube.com/youtubei/v1/next?prettyPrint=false")
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .build()
        val text = try {
            Http.client.newCall(req).execute().use { if (it.isSuccessful) it.body?.string() else null }
        } catch (e: Exception) { null } ?: return@withContext emptyList()
        val items: JSONArray = try {
            JSONObject(text).getJSONObject("contents").getJSONObject("twoColumnWatchNextResults")
                .getJSONObject("playlist").getJSONObject("playlist").getJSONArray("contents")
        } catch (e: Exception) { return@withContext emptyList() }
        (0 until items.length()).mapNotNull { i ->
            val r = items.optJSONObject(i)?.optJSONObject("playlistPanelVideoRenderer") ?: return@mapNotNull null
            val id = r.optString("videoId").ifEmpty { return@mapNotNull null }
            val title = text(r.opt("title")) ?: return@mapNotNull null
            MixEntry(id, title, text(r.opt("shortBylineText")) ?: "YouTube", parseDuration(text(r.opt("lengthText")) ?: ""))
        }
    }

    // endregion

    // region Official video ranking (port of the Mac / iPhone ranking)

    /** Biases the search toward video songs unless the user already said what they want. */
    fun officialSearchQuery(query: String): String {
        val lower = query.lowercase()
        val intentWords = listOf("video", "audio", "lyric", "official", "live", "cover", "karaoke", "remix", "jukebox")
        return if (intentWords.any { lower.contains(it) }) query else "$query video song"
    }

    /**
     * Normalizes romanized Indian-language spellings so variants compare equal
     * ("valukanuladana" ~ "Vaalu Kanuladaanaa").
     */
    fun translit(s: String): String {
        var x = s.lowercase().filter { it.isLetterOrDigit() }
        val folds = listOf(
            "aa" to "a", "ee" to "i", "ii" to "i", "oo" to "u", "uu" to "u", "ou" to "u",
            "th" to "t", "dh" to "d", "bh" to "b", "kh" to "k", "gh" to "g",
            "sh" to "s", "ph" to "f", "w" to "v", "z" to "j"
        )
        for ((from, to) in folds) x = x.replace(from, to)
        val out = StringBuilder()
        for (c in x) if (out.isEmpty() || out.last() != c) out.append(c)
        return out.toString()
    }

    /** Song name without "(From "Movie")", "[Remastered]" or " - Live" style suffixes. */
    fun coreSongTitle(title: String): String {
        var t = title.replace(Regex("\\s*[(\\[].*$"), "")
        val dash = t.lastIndexOf(" - ")
        if (dash >= 0) {
            val suffix = t.substring(dash + 3).lowercase()
            val versionWords = listOf("remaster", "live", "version", "mix", "edit", "from", "single", "remix",
                "acoustic", "reprise", "unplugged", "radio", "mono", "stereo", "bonus")
            if (versionWords.any { suffix.contains(it) }) t = t.substring(0, dash)
        }
        return t.trim()
    }

    /**
     * Language of a video, from its title ("Srivalli (Hindi)") or, since official dubbed uploads
     * often don't say, from the label that uploaded it (T-Series → Hindi, Aditya Music → Telugu).
     */
    fun videoLanguage(title: String, channel: String): String? {
        val t = title.lowercase()
        val c = channel.lowercase()
        MediaTrack.INDIAN_LANGUAGES.firstOrNull { t.contains(it) }?.let { return it }
        MediaTrack.INDIAN_LANGUAGES.firstOrNull { c.contains(it) }?.let { return it }
        val labels = listOf(
            "telugu" to listOf("aditya music", "mango music", "shalimar", "sri balaji", "telugu filmnagar", "geetha arts", "mythri", "suresh productions"),
            "tamil" to listOf("think music", "sun tv", "divo"),
            "kannada" to listOf("anand audio", "pmusic", "d beats"),
            "malayalam" to listOf("muzik247", "manorama music", "east coast", "wayfarer"),
            "punjabi" to listOf("apna punjab", "speed records", "white hill", "geet mp3", "jass records"),
            "hindi" to listOf("saregama music", "t-series", "zee music", "tips", "yrf", "yash raj", "sony music india", "goldmines", "eros now", "venus", "shemaroo", "dharma", "red chillies")
        )
        for ((lang, names) in labels) if (names.any { c.contains(it) }) return lang
        return null
    }

    private fun wordsOf(s: String): List<String> = s.lowercase().split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }

    /**
     * Drops Shorts/reels, lyric videos, audio uploads, loops etc., then orders the rest so the
     * original video song from the label or artist comes first.
     */
    fun rankOfficialVideos(
        results: List<YouTubeSearchResult>,
        query: String,
        songTitle: String? = null,
        artist: String? = null,
        movie: String? = null,
        expectedDuration: Double? = null,
        language: String? = null
    ): List<YouTubeSearchResult> {
        val q = query.lowercase()
        val fillerWords = setOf("video", "song", "songs", "official", "full", "music", "the", "a", "-", "|")
        val queryWords = wordsOf(q).filter { it !in fillerWords }

        // Rejected outright unless the user typed that word themselves
        val rejected = listOf(
            "lyric", "lyrics", "lyrical", "letra", "karaoke", "slowed", "reverb", "8d", "bass boosted",
            "cover", "status", "reaction", "#shorts", "shorts", "#short", "reel", "reels", "tiktok",
            "mashup", "loop", "minutes version", "hour", "extended", "ringtone", "bgm", "instrumental",
            "whatsapp", "kidz bop", "mmv", "amv", "nightcore", "choreography", "dance cover", "indian idol",
            "traducida", "traducción", "traduccion", "translated", "sub español", "subtitulado", "legendado",
            "freestyle", "reversed", "just dance", "behind the scenes", "bts", "pre wedding", "wedding video", "launch event",
            "song launch", "audio launch", "speech", "interview", "press meet", "pre release",
            "pre-release", "full movie", "interval bgm", "movie scene", "scenes", "making video", "fan made"
        )
        // Allowed but pushed down
        val penalized = listOf(
            "retrowave", "lofi", "lo-fi", " mix", "audio", "jukebox", "live", "performs", "performance", "teaser", "trailer", "promo",
            "promotional", "making", "behind the scenes", "remix", "fan made"
        )
        val officialTitle = listOf(
            "official video", "official music video", "(official)", "[official]", "official visualizer", "video song", "full video", "music video",
            "official 4k", "8k video", "4k video", "video telugu", "video tamil", "video hindi", "video |", "(video)"
        )
        val officialChannels = listOf(
            "vevo", "volume", "aditya music", "sony music", "t-series", "lahari", "saregama", "mango music",
            "think music", "zee music", "tips", "sun tv", "divo", "junglee", "speed records",
            "eros now", "yrf", "times music", "muzik247", "goldmines", "venus", "shemaroo",
            "madhura audio", "anand audio", "sri balaji", "geetha arts", "mythri", "shalimar",
            "suresh productions", "volga", "rajshri", "ultra", "telugu filmnagar", "yash raj",
            "dharma", "red chillies", "excel", "official"
        )
        // Fan re-uploads (upscales, 60fps edits) rank below the original label upload
        val reuploadMarkers = listOf("upscale", "60fps", "8k songs", "remastered", "hdr edit", "audiophile", "high quality")

        val queryKey = translit(queryWords.joinToString(""))
        val songWords = songTitle?.let { wordsOf(coreSongTitle(it)) } ?: emptyList()
        val songKey = translit(songWords.joinToString(""))
        // Ignore 1-2 letter words and generic words when matching
        val genericSongWords = setOf("theme", "title", "song", "songs", "track", "version", "the", "and")
        val realSongWords = songWords.filter { it.length >= 3 && it !in genericSongWords }
        val significantSongWords = realSongWords.ifEmpty { songWords }
        val movieWords = wordsOf(movie ?: "")
        // Every credited artist ("Zedd & Katy Perry" → [zedd], [katy, perry]); the channel may be either one
        val artistNames: List<List<String>> = (artist ?: "").lowercase()
            .replace(Regex("\\(.*?\\)"), "")
            .split('&', ',')
            .map { wordsOf(it).filter { w -> w.length >= 3 } }
            .filter { it.isNotEmpty() }

        val scored = mutableListOf<Pair<YouTubeSearchResult, Double>>()
        results.forEachIndexed { index, r ->
            val title = r.title.lowercase()
            val channel = r.channel.lowercase()

            if (r.url.contains("/shorts/")) return@forEachIndexed
            if (r.durationSec > 0 && (r.durationSec < 60 || r.durationSec > 900)) return@forEachIndexed
            // The artist's own channel (not a "- Topic" art-track channel)
            val isArtistChannel = !channel.contains("topic") &&
                artistNames.any { name -> name.all { translit(channel).contains(translit(it)) } }
            // Songs with no music video often have an "Official Lyric Video" on the artist's channel
            val officialLyricByArtist = isArtistChannel && title.contains("official lyric")
            if (rejected.any { title.contains(it) && !q.contains(it) } && !officialLyricByArtist) return@forEachIndexed

            var score = 0.0
            val titleKey = translit(title)
            val matched = queryWords.count { titleKey.contains(translit(it)) }
            if (songWords.isNotEmpty()) {
                // Known track: the song name carries the relevance; other words (movie, singers) add a little
                val songMatched = significantSongWords.count { titleKey.contains(translit(it)) }
                val extraMatched = queryWords.count { w -> w !in songWords && titleKey.contains(translit(w)) }
                score += 6.0 * songMatched / significantSongWords.size + min(1.5, 0.5 * extraMatched)
            } else if (queryWords.isNotEmpty()) {
                score += 6.0 * matched / queryWords.size
            }
            if (queryWords.isNotEmpty()) {
                if (matched == 0) score -= 10 // unrelated song that only matched on "video song"
                if (titleKey.contains(queryKey)) score += 2
                // Song name in the first part of the title, not just as the movie/album name later on
                val lead = title.split('|', '(').first()
                val leadKey = translit(lead)
                if (queryWords.any { leadKey.contains(translit(it)) }) score += 3
                if (leadKey.startsWith(queryKey)) score += 1
            }
            if (reuploadMarkers.any { title.contains(it) || channel.contains(it) }) score -= 3
            // Auto-generated uploads have the bare song name as the whole title and a still image
            if (songKey.isNotEmpty() && titleKey == songKey && !isArtistChannel && officialTitle.none { title.contains(it) }) score -= 5
            if (listOf("re edited", "re-edited", "reedited", "re edit", "re-edit", "reedit").any { title.contains(it) }) score -= 5
            // "feat. Someone" is another singer's version of the song, unless the track itself says feat.
            Regex("\\b(feat\\.?|ft\\.?|featuring)\\s+([^|()\\[\\]\\-]+)").find(title)?.let { feat ->
                if (!(songTitle ?: "").lowercase().contains("feat") && !q.contains("feat")) {
                    val featured = feat.value.split(Regex("[^\\p{L}]+")).filter { it.length >= 4 && it !in setOf("feat", "featuring") }
                    val known = ((artist ?: "") + " " + (songTitle ?: "")).lowercase()
                    if (featured.isNotEmpty() && featured.none { known.contains(it) }) score -= 4
                }
            }
            if (listOf("new version", "female version", "male version", "unplugged").any { title.contains(it) && !q.contains(it) }) score -= 3
            if (officialLyricByArtist) score -= 1 // a real music video, if there is one, still wins
            if (isArtistChannel) score += 3
            // Titles that never say "video" (or official / music) are usually audio over a still image
            val sayVideo = listOf("video", "official", "music", " mv").any { title.contains(it) }
            if (!sayVideo && !isArtistChannel && !q.contains("audio")) score -= 3
            if (title.contains("video song") || title.contains("full video")) score += 2
            if (title.contains("audio song") && !title.contains("video") && !q.contains("audio")) score -= 3
            if (officialTitle.any { title.contains(it) } && officialChannels.any { channel.contains(it) }) score += 2
            // Sequels / variants ("Darmiyan 2", "Part 3") are different songs unless the user asked for them
            if (Regex("(?<![\\d.])\\b[2-9]\\b(?![\\d.])").containsMatchIn(title) && !Regex("\\b[2-9]\\b").containsMatchIn(q)) score -= 5
            if (listOf("female version", "reprise", "unplugged", "mashup", "flute", "piano").any { title.contains(it) && !q.contains(it) }) score -= 4
            // "Pilla Full Song" (no "video") is usually the audio over a still poster
            val fullSongVideoLabels = listOf("yrf", "yash raj", "t-series", "zee music", "tips", "vevo", "sony music india")
            if (title.contains("full song") && !title.contains("video") && !q.contains("audio") &&
                fullSongVideoLabels.none { channel.contains(it) }) score -= 2
            if (movie != null && movieWords.isNotEmpty()) {
                val movieMatched = movieWords.count { titleKey.contains(translit(it)) }
                if (movieMatched == movieWords.size) score += 3 else if (movieMatched > 0) score += 1
            }

            // Known track: its song name must be in the video title
            if (songWords.isNotEmpty()) {
                val songMatched = significantSongWords.count { titleKey.contains(translit(it)) }
                val fullNameMatch = titleKey.contains(songKey)
                if (!fullNameMatch && songMatched.toDouble() / significantSongWords.size < 0.75) return@forEachIndexed
                // A title segment that starts with the song name
                val segments = title.split('|', '(', '-', ':')
                if (segments.any { translit(it).startsWith(songKey) }) score += 2
            }
            if (expectedDuration != null && expectedDuration > 0 && r.durationSec > 0) {
                val diff = abs(r.durationSec - expectedDuration)
                if (diff <= 15) score += 3 else if (diff <= 40) score += 1 else if (diff > 90) score -= 2
            }

            if (officialTitle.any { title.contains(it) }) score += 3
            if (officialChannels.any { channel.contains(it) }) score += 4
            // Artist's own channel, e.g. "The Weeknd" uploading "The Weeknd - Blinding Lights"
            if (channel.length > 2 && title.startsWith(channel)) score += 2
            if (penalized.any { title.contains(it) && !q.contains(it) }) score -= 3

            if (artistNames.isNotEmpty()) {
                val channelKey = translit(channel)
                // Only the first credited artist counts in the title: later names are often the film's actor
                val artistMatched = artistNames.first().all { titleKey.contains(translit(it)) || channelKey.contains(translit(it)) }
                if (artistMatched) {
                    score += 3
                } else {
                    val dash = title.indexOf(" - ")
                    // "Beth - Don't You Worry Child": credited to someone else, usually a cover
                    if (dash >= 0 && translit(title.substring(0, dash)).length >= 3) score -= 3
                }
            }
            if (language != null) {
                videoLanguage(r.title, r.channel)?.let { videoLang ->
                    // Prefer the version in the wanted language; push other languages down
                    if (videoLang == language) score += 4 else if (!q.contains(videoLang)) score -= 4
                }
            }

            score -= index * 0.15 // keep YouTube's own order as a tiebreaker
            scored.add(r to score)
        }

        // Anything scoring this low is a loose match (talks, events, other songs): better to find nothing
        val ranked = scored.sortedByDescending { it.second }.filter { it.second >= 6 }
        Log.i(TAG, "ranked \"$query\" song=${songTitle ?: "-"} movie=${movie ?: "-"}: ${results.size} results, ${ranked.size} kept")
        ranked.take(3).forEachIndexed { i, (r, s) -> Log.i(TAG, "  #${i + 1} score=${"%.1f".format(s)} ${r.id} [${r.channel}] ${r.title}") }
        return ranked.map { it.first }
    }

    // endregion
}
