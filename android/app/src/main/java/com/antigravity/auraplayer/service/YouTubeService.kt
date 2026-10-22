package com.antigravity.auraplayer.service

import android.util.Log
import com.antigravity.auraplayer.model.MediaTrack
import com.antigravity.auraplayer.model.MediaType
import com.antigravity.auraplayer.model.TrackSourceType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.search.SearchInfo
import org.schabi.newpipe.extractor.services.youtube.linkHandler.YoutubeSearchQueryHandlerFactory
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.DeliveryMethod
import org.schabi.newpipe.extractor.stream.StreamInfo
import org.schabi.newpipe.extractor.stream.StreamInfoItem
import org.schabi.newpipe.extractor.stream.StreamType
import kotlin.math.abs
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
}

/**
 * YouTube search, video details and audio streams via NewPipeExtractor, with the same
 * "official video song first" ranking as the Mac app.
 */
object YouTubeService {
    private const val TAG = "AuraPlayer/YouTube"
    private val youtube = ServiceList.YouTube
    private val videoIdCache = mutableMapOf<String, String>()

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

    /**
     * @param songTitle when resolving a known track, its song name; results without it are dropped.
     * @param movie movie / album name; results that mention it rank higher.
     * @param expectedDuration known song length in seconds; videos close to it rank higher.
     */
    suspend fun search(
        query: String,
        limit: Int = 8,
        songTitle: String? = null,
        movie: String? = null,
        expectedDuration: Double? = null
    ): List<YouTubeSearchResult> = withContext(Dispatchers.IO) {
        val handler = youtube.searchQHFactory.fromQuery(
            officialSearchQuery(query),
            listOf(YoutubeSearchQueryHandlerFactory.VIDEOS),
            ""
        )
        val info = SearchInfo.getInfo(youtube, handler)
        val candidates = info.relatedItems
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
        rankOfficialVideos(candidates, query, songTitle, movie, expectedDuration).take(limit)
    }

    /** The single most likely official video song for a song name. */
    suspend fun bestOfficialVideo(
        query: String,
        songTitle: String? = null,
        movie: String? = null,
        expectedDuration: Double? = null
    ): YouTubeSearchResult? {
        val key = query.trim().lowercase()
        return try {
            search(query, 1, songTitle, movie, expectedDuration).firstOrNull()?.also {
                videoIdCache[key] = it.id
                Log.i(TAG, "picked ${it.id} for \"$query\": ${it.title}")
            }
        } catch (e: Exception) {
            Log.w(TAG, "search failed for \"$query\"", e)
            null
        }
    }

    /** Video id for a track that was saved without one, using its title/duration as hints. */
    suspend fun resolveVideoId(track: MediaTrack, excluding: Set<String> = emptySet()): String? {
        val query = "${track.title} ${track.artist}".trim()
        if (excluding.isEmpty()) videoIdCache[query.lowercase()]?.let { return it }
        return try {
            search(query, 10, songTitle = track.title, expectedDuration = track.duration.takeIf { it > 0 })
                .firstOrNull { it.id !in excluding }?.id
                ?.also { videoIdCache[query.lowercase()] = it }
        } catch (e: Exception) {
            Log.w(TAG, "resolve failed for \"$query\"", e)
            null
        }
    }

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

    // region Official video ranking (port of the Mac app's ranking)

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
        return com.antigravity.auraplayer.utils.MetadataCleaner.clean(title).cleanTitle
    }

    private fun words(s: String): List<String> =
        s.lowercase().split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }

    private val fillerWords = setOf("video", "song", "songs", "official", "full", "music", "the", "a")

    // Rejected outright unless the user typed that word themselves
    private val rejected = listOf(
        "lyric", "lyrics", "lyrical", "letra", "karaoke", "slowed", "reverb", "8d", "bass boosted",
        "cover", "status", "reaction", "#shorts", "shorts", "#short", "reel", "reels", "tiktok",
        "mashup", "loop", "minutes version", "hour", "extended", "ringtone", "bgm", "instrumental",
        "whatsapp", "kidz bop", "mmv", "amv", "nightcore", "choreography", "dance cover", "indian idol"
    )
    // Allowed but pushed down
    private val penalized = listOf(
        "audio", "jukebox", "live", "performs", "performance", "teaser", "trailer", "promo",
        "promotional", "making", "behind the scenes", "remix", "fan made"
    )
    private val officialTitle = listOf(
        "official video", "official music video", "video song", "full video", "music video",
        "official 4k", "video telugu", "video tamil", "video hindi", "video |", "(video)"
    )
    private val officialChannels = listOf(
        "vevo", "volume", "aditya music", "sony music", "t-series", "lahari", "saregama", "mango music",
        "think music", "zee music", "tips", "sun tv", "divo", "junglee", "speed records",
        "eros now", "yrf", "yash raj", "times music", "muzik247", "goldmines", "venus", "shemaroo",
        "madhura audio", "anand audio", "sri balaji", "geetha arts", "mythri", "shalimar",
        "suresh productions", "volga", "rajshri", "ultra", "telugu filmnagar", "dharma",
        "red chillies", "excel", "official"
    )
    // Fan re-uploads (upscales, 60fps edits) rank below the original label upload
    private val reuploadMarkers = listOf("upscale", "60fps", "8k songs", "remastered", "hdr edit", "audiophile", "high quality")

    /**
     * Drops Shorts/reels, lyric videos, audio uploads, loops etc., then orders the rest so the
     * original video song from the label or artist comes first.
     */
    fun rankOfficialVideos(
        results: List<YouTubeSearchResult>,
        query: String,
        songTitle: String? = null,
        movie: String? = null,
        expectedDuration: Double? = null
    ): List<YouTubeSearchResult> {
        val q = query.lowercase()
        val queryWords = words(q).filter { it !in fillerWords }
        val queryKey = translit(queryWords.joinToString(""))
        val songWords = songTitle?.let { words(coreSongTitle(it)) } ?: emptyList()
        val songKey = translit(songWords.joinToString(""))
        // Ignore 1-2 letter words ("o", "re") when matching: they occur inside almost any title
        val significantSongWords = songWords.filter { it.length >= 3 }.ifEmpty { songWords }
        val movieWords = words(movie ?: "")

        val scored = mutableListOf<Pair<YouTubeSearchResult, Double>>()
        for ((index, r) in results.withIndex()) {
            val title = r.title.lowercase()
            val channel = r.channel.lowercase()

            if (r.url.contains("/shorts/")) continue
            if (r.durationSec > 0 && (r.durationSec < 60 || r.durationSec > 900)) continue
            if (rejected.any { title.contains(it) && !q.contains(it) }) continue

            var score = 0.0
            val titleKey = translit(title)
            val matched = queryWords.count { titleKey.contains(translit(it)) }

            // Relevance: the typed words should appear in the title, ignoring spacing and spelling variants
            if (songWords.isNotEmpty()) {
                // Known track: the song name carries the relevance; other words add a little.
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
                val lead = title.split('|', '(').firstOrNull() ?: title
                val leadKey = translit(lead)
                if (queryWords.any { leadKey.contains(translit(it)) }) score += 3
                if (leadKey.startsWith(queryKey)) score += 1
            }
            if (reuploadMarkers.any { title.contains(it) || channel.contains(it) }) score -= 3

            // Known track: its song name must be in the video title
            if (songWords.isNotEmpty()) {
                val songMatched = significantSongWords.count { titleKey.contains(translit(it)) }
                val fullNameMatch = titleKey.contains(songKey)
                if (!fullNameMatch && songMatched.toDouble() / significantSongWords.size < 0.75) continue
                // A title segment that starts with the song name beats a passing mention
                val segments = title.split('|', '(', '-', ':')
                if (segments.any { translit(it).startsWith(songKey) }) score += 2
            }
            if (expectedDuration != null && expectedDuration > 0 && r.durationSec > 0) {
                val diff = abs(r.durationSec - expectedDuration)
                score += when {
                    diff <= 15 -> 3.0
                    diff <= 40 -> 1.0
                    diff > 90 -> -2.0
                    else -> 0.0
                }
            }

            if (officialTitle.any { title.contains(it) }) score += 3
            if (officialChannels.any { channel.contains(it) }) score += 2
            // Artist's own channel, e.g. "The Weeknd" uploading "The Weeknd - Blinding Lights"
            if (channel.length > 2 && title.startsWith(channel)) score += 2
            if (penalized.any { title.contains(it) && !q.contains(it) }) score -= 3
            // Auto-generated "Provided to YouTube" uploads have just the song name as title
            if (songKey.isNotEmpty() && titleKey == songKey && officialTitle.none { title.contains(it) }) score -= 5
            // Sequels / variants ("Darmiyan 2") are different songs unless asked for
            if (Regex("(?<![\\d.])\\b[2-9]\\b(?![\\d.])").containsMatchIn(title) &&
                !Regex("\\b[2-9]\\b").containsMatchIn(q)) score -= 5
            if (listOf("female version", "reprise", "unplugged", "flute", "piano").any { title.contains(it) && !q.contains(it) }) score -= 4
            // "Pilla Full Song" (no "video") is usually the audio over a still poster
            if (title.contains("full song") && !title.contains("video") && !q.contains("audio")) score -= 2
            if (movieWords.isNotEmpty()) {
                val movieMatched = movieWords.count { titleKey.contains(translit(it)) }
                if (movieMatched == movieWords.size) score += 3 else if (movieMatched > 0) score += 1
            }

            score -= index * 0.15 // keep YouTube's own order as a tiebreaker
            scored.add(r to score)
        }

        val ranked = scored.sortedByDescending { it.second }
        Log.i(TAG, "ranked \"$query\": ${results.size} results, ${ranked.size} kept")
        ranked.take(5).forEachIndexed { i, (r, s) ->
            Log.i(TAG, "  #${i + 1} score=${"%.1f".format(s)} ${r.id} ${r.durationSec.toInt()}s [${r.channel}] ${r.title}")
        }
        return ranked.map { it.first }
    }

    // endregion
}
