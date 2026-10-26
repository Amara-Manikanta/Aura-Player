package com.antigravity.auraplayer.service

import android.content.Context
import android.util.Log
import com.antigravity.auraplayer.data.PlaylistRepository
import com.antigravity.auraplayer.model.MediaTrack
import com.antigravity.auraplayer.model.TrackSourceType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.max
import kotlin.random.Random

/**
 * "For You", same as the Mac and iPhone apps:
 * 1. Seeds: your most-played / favourite / 👍 / recently played songs (varied across artists & movies).
 * 2. For each seed, YouTube's own "Mix" (what millions of listeners play together with it).
 * 3. Songs that show up in several of your seeds' mixes, near the top, score highest.
 * 4. Anything already in your library, marked "Not interested", or junk is removed.
 */
object RecommendationService {
    private const val TAG = "AuraPlayer/ForYou"
    private const val APPLE_EPOCH_OFFSET_SEC = 978_307_200L

    data class Suggestion(
        val videoId: String, val title: String, val channel: String, val duration: Double,
        val score: Double, val becauseOf: String, val seedCount: Int
    ) {
        val video get() = YouTubeSearchResult(videoId, title, channel, duration,
            "https://i.ytimg.com/vi/$videoId/hqdefault.jpg", "https://www.youtube.com/watch?v=$videoId")
        val reason get() = if (seedCount > 1) "Like $becauseOf + ${seedCount - 1} more" else "Because you like $becauseOf"
    }

    data class Seed(val track: MediaTrack, val weight: Double)
    data class KnownSong(val key: String, val context: List<String>)
    data class NewForYou(val release: NewRelease, val score: Double, val reason: String)

    data class TasteProfile(
        val artistWeights: Map<String, Double>,
        val artistDisplay: Map<String, String>,
        val artistWords: Map<String, List<String>>,
        val languages: List<Pair<String, Double>>
    )

    private var suggestions = listOf<Suggestion>()
    var generatedAt = 0L
        private set
    private val notInterested = mutableSetOf<String>()
    private val seedVideoIds = mutableMapOf<String, String>()
    private var file: File? = null

    @Synchronized
    fun init(context: Context) {
        if (file != null) return
        val f = File(context.filesDir, "for_you.json")
        file = f
        try {
            if (f.exists()) {
                val o = JSONObject(f.readText())
                generatedAt = o.optLong("generatedAt")
                suggestions = o.optJSONArray("suggestions").toSuggestions()
                o.optJSONArray("notInterested")?.let { a -> for (i in 0 until a.length()) notInterested.add(a.getString(i)) }
                o.optJSONObject("seedVideoIds")?.let { m -> m.keys().forEach { seedVideoIds[it] = m.getString(it) } }
            } else {
                // First launch: the Mac's last picks (refreshed here after a day like any other)
                val o = JSONObject(context.assets.open("for_you.json").bufferedReader().use { it.readText() })
                suggestions = o.optJSONArray("suggestions").toSuggestions()
                val macAt = ((o.optDouble("generatedAt", 0.0) + APPLE_EPOCH_OFFSET_SEC) * 1000).toLong()
                generatedAt = minOf(macAt, System.currentTimeMillis() - 86_400_000)
                o.optJSONArray("notInterested")?.let { a -> for (i in 0 until a.length()) notInterested.add(a.getString(i)) }
                o.optJSONObject("seedVideoIds")?.let { m -> m.keys().forEach { seedVideoIds[it] = m.getString(it) } }
            }
        } catch (e: Exception) {
            Log.w(TAG, "couldn't read saved picks", e)
        }
    }

    private fun JSONArray?.toSuggestions(): List<Suggestion> {
        if (this == null) return emptyList()
        return (0 until length()).mapNotNull { i ->
            val s = optJSONObject(i) ?: return@mapNotNull null
            Suggestion(s.optString("videoId"), s.optString("title"), s.optString("channel"), s.optDouble("duration", 0.0),
                s.optDouble("score", 0.0), s.optString("becauseOf"), s.optInt("seedCount", 1))
        }
    }

    @Synchronized
    private fun persist() {
        val f = file ?: return
        val o = JSONObject()
            .put("generatedAt", generatedAt)
            .put("suggestions", JSONArray(suggestions.map {
                JSONObject().put("videoId", it.videoId).put("title", it.title).put("channel", it.channel)
                    .put("duration", it.duration).put("score", it.score).put("becauseOf", it.becauseOf).put("seedCount", it.seedCount)
            }))
            .put("notInterested", JSONArray(notInterested.toList()))
            .put("seedVideoIds", JSONObject(seedVideoIds as Map<*, *>))
        try { f.writeText(o.toString()) } catch (e: Exception) { }
    }

    fun cached(): List<Suggestion> = suggestions.filter { it.videoId !in notInterested }

    fun markNotInterested(videoId: String) {
        notInterested.add(videoId)
        suggestions = suggestions.filter { it.videoId != videoId }
        persist()
    }

    /** Builds fresh suggestions. `progress(done, total)` reports seed songs processed. */
    suspend fun generate(
        seeds: List<Seed>, known: List<KnownSong>, knownVideoIds: Set<String>,
        progress: (Int, Int) -> Unit
    ): List<Suggestion> = withContext(Dispatchers.IO) {
        val total = seeds.size
        // 1. A YouTube video for every seed (remembered between runs: lookups are the slow part)
        val seedIds = mutableListOf<Pair<Seed, String>>()
        seeds.forEachIndexed { i, seed ->
            val key = trackKey(seed.track)
            val vid = seed.track.youtubeId ?: seedVideoIds[key]
                ?: YouTubeService.resolveVideo(seed.track, null)?.also { seedVideoIds[key] = it }
            if (vid != null) seedIds.add(seed to vid)
            progress((i + 1) / 2, total)
        }
        persist()

        // 2. Their mixes, four at a time
        var finished = 0
        val gate = Semaphore(4)
        val mixes = coroutineScope {
            seedIds.map { (seed, vid) ->
                async {
                    gate.withPermit {
                        val entries = YouTubeService.fetchMix(vid)
                        synchronized(this@RecommendationService) { finished++ }
                        progress(total / 2 + finished * (total - total / 2) / max(seedIds.size, 1), total)
                        seed to entries
                    }
                }
            }.awaitAll()
        }

        // 3. Score: weight of the seed × how near the top of its mix; summed across seeds
        class Candidate(var entry: MixEntry, var score: Double, var bestSeed: String, var bestContribution: Double, val seeds: MutableSet<String>)
        val candidates = mutableMapOf<String, Candidate>()   // keyed by song identity, not video, to merge re-uploads
        for ((seed, entries) in mixes) {
            entries.forEachIndexed { position, entry ->
                if (position == 0) return@forEachIndexed   // the seed itself
                if (entry.id in knownVideoIds || entry.id in notInterested || !isGoodSong(entry) || isKnown(entry.title, known)) return@forEachIndexed
                val contribution = seed.weight * max(0.15, 1.0 - position / 30.0)
                val songKey = songIdentity(entry.title)
                val seedName = seed.track.coreTitle
                val c = candidates[songKey]
                if (c != null) {
                    c.score += contribution
                    c.seeds.add(seedName)
                    if (contribution > c.bestContribution) { c.bestContribution = contribution; c.bestSeed = seedName }
                    if (uploadQuality(entry) > uploadQuality(c.entry)) c.entry = entry
                } else {
                    candidates[songKey] = Candidate(entry, contribution, seedName, contribution, mutableSetOf(seedName))
                }
            }
        }

        // Songs recommended by several of your favourites count extra
        val ranked = candidates.values
            .map { it to it.score * (1 + 0.35 * (it.seeds.size - 1)) + uploadQuality(it.entry) * 0.3 }
            .sortedByDescending { it.second }

        // 4. Variety: at most 4 songs per channel and per seed
        val perChannel = mutableMapOf<String, Int>()
        val perSeed = mutableMapOf<String, Int>()
        val chosen = mutableListOf<String>()
        val result = mutableListOf<Suggestion>()
        for ((c, score) in ranked) {
            val channel = c.entry.channel.lowercase()
            val identity = songIdentity(c.entry.title)
            if ((perChannel[channel] ?: 0) >= 4 || (perSeed[c.bestSeed] ?: 0) >= 4 || isDuplicate(identity, chosen)) continue
            perChannel[channel] = (perChannel[channel] ?: 0) + 1
            perSeed[c.bestSeed] = (perSeed[c.bestSeed] ?: 0) + 1
            chosen.add(identity)
            result.add(Suggestion(c.entry.id, c.entry.title, c.entry.channel, c.entry.duration, score, c.bestSeed, c.seeds.size))
            if (result.size >= 60) break
        }
        if (result.isNotEmpty()) {
            suggestions = result
            generatedAt = System.currentTimeMillis()
            persist()
        }
        Log.i(TAG, "${seeds.size} seeds, ${mixes.size} mixes, ${candidates.size} candidates → ${result.size} suggestions")
        result
    }

    /** This month's new songs in your languages, best taste match first. */
    suspend fun newForYou(profile: TasteProfile): List<NewForYou> {
        val results = mutableListOf<NewForYou>()
        val seen = mutableSetOf<String>()
        val languages = profile.languages.filter { it.second >= 0.05 }.take(4)
        for ((language, share) in languages) {
            val releases = YouTubeService.newReleases(language.replaceFirstChar { it.uppercase() }, ReleasePeriod.MONTH)
            for (r in releases) {
                if (r.id in notInterested || !seen.add(r.id)) continue
                // Whole words only: "Karthik" must not match "Karthika", nor "Priya" match "Priyanka"
                val words = (r.video.title + " " + r.video.channel).lowercase().split(Regex("[^\\p{L}\\p{N}]+")).toSet()
                val matched = profile.artistWeights.mapNotNull { (name, weight) ->
                    val parts = profile.artistWords[name] ?: return@mapNotNull null
                    if (parts.isEmpty() || name.length < 5) return@mapNotNull null
                    // one-word names like "Priya" or "Rahul" are part of many other people's names
                    if (parts.size == 1 && name.length < 7) return@mapNotNull null
                    if (parts.all { it in words }) name to weight else null
                }.sortedByDescending { it.second }
                val artistScore = matched.take(3).sumOf { it.second }
                val popularity = log10(max(r.views, 1L).toDouble())
                val t = r.video.title.lowercase()
                var quality = 0.0
                if (listOf("video song", "full video", "official video", "music video", "- video", "(video)").any { t.contains(it) }) quality += 1
                if (t.contains("lyric")) quality -= 1.5
                if (t.contains("audio")) quality -= 1
                val score = artistScore * 2 + share * 6 + popularity * 0.6 + quality
                val reason = matched.firstOrNull()?.let { "You listen to ${profile.artistDisplay[it.first] ?: it.first}" }
                    ?: "New in ${language.replaceFirstChar { it.uppercase() }}"
                results.add(NewForYou(r, score, reason))
            }
        }
        results.sortByDescending { it.score }
        // one upload per song (the best-scored: usually the real video)
        val identities = mutableListOf<String>()
        return results.filter { item ->
            val id = songIdentity(item.release.video.title)
            if (isDuplicate(id, identities)) false else { identities.add(id); true }
        }.also { Log.i(TAG, "new for you: ${it.size} releases in ${languages.map { l -> l.first }}") }
    }

    // region Filters

    /** Real songs only: no jukeboxes, lyric/remix/cover versions, live shows, Shorts, long compilations. */
    private fun isGoodSong(e: MixEntry): Boolean {
        val t = e.title.lowercase()
        if (e.duration > 0 && (e.duration < 90 || e.duration > 600)) return false
        val junk = listOf("jukebox", "lyric", "lyrical", "karaoke", "cover", "remix", "mashup", "slowed", "reverb", "8d",
            "lofi", "lo-fi", "bgm", "instrumental", "reaction", "live", "performance", "trailer", "teaser",
            "promo", "status", "#shorts", "nonstop", "back to back", "audio songs", "full album", "hour",
            "extended", "amv", "edit", "version", "versión", "sped up", "nightcore", "tiktok", "ringtone")
        return junk.none { t.contains(it) }
    }

    /** Already in your library? (same song name, plus its movie or a singer in the video title) */
    private fun isKnown(title: String, known: List<KnownSong>): Boolean {
        val t = YouTubeService.translit(title)
        return known.any { song -> t.contains(song.key) && (song.context.isEmpty() || song.context.any { t.contains(it) }) }
    }

    /** Same song across different uploads: the first part of the title ("Hoyna Hoyna" from "Hoyna Hoyna | Gang Leader") */
    fun songIdentity(title: String): String {
        var t = title.lowercase()
        for (sep in listOf("|", "(", "[", " - video", " - full", " - lyric", " - audio")) {
            val i = t.indexOf(sep)
            if (i > 0) t = t.substring(0, i)
        }
        val colon = t.indexOf(":")
        if (colon >= 0 && colon + 1 < t.length) t = t.substring(colon + 1)
        val generic = listOf("full video song", "video song", "full video", "full song", "lyrical song", "lyrical video", "lyric video",
            "lyrical", "lyric", "audio song", "audio", "official video", "music video", "video", "song", "full", "4k", "8k", "hd")
        for (g in generic) t = t.replace(g, " ")
        return YouTubeService.translit(t)
    }

    private fun isDuplicate(identity: String, chosen: List<String>): Boolean {
        if (identity.length < 4) return identity in chosen
        return chosen.any { it == identity || (it.length >= 4 && (it.contains(identity) || identity.contains(it))) }
    }

    private fun uploadQuality(e: MixEntry): Double {
        val t = e.title.lowercase()
        val c = e.channel.lowercase()
        var q = 0.0
        if (listOf("vevo", "t-series", "sony music", "zee music", "saregama", "aditya music", "lahari", "mango music",
                "think music", "tips", "yrf", "speed records", "sun tv").any { c.contains(it) }) q += 2
        if (listOf("video song", "official video", "music video", "full video").any { t.contains(it) }) q += 1
        return q
    }

    private fun trackKey(t: MediaTrack) =
        "${ArtistPhotoService.normalize(t.coreTitle)}|${ArtistPhotoService.normalize(t.artist)}"

    // endregion
}

/** Turns the library into what the recommender needs (same as the Mac app). */
object TasteBuilder {
    /** How much a song tells us about your taste: plays (log scale), favourite, 👍, played recently. */
    private fun weight(t: MediaTrack, favorite: Boolean): Double {
        var w = ln(1.0 + t.totalPlays) / ln(2.0)
        if (favorite) w += 1.5
        if (!t.youtubeId.isNullOrEmpty() && !t.originalURL.lowercase().startsWith("http")) w += 0.5   // 👍 / chosen video
        t.lastPlayedDate?.let { if (System.currentTimeMillis() - it < 30L * 86_400_000) w += 1 }
        return w
    }

    /**
     * About `count` seed songs: strongest first, but sampled from the top 60 so each refresh differs,
     * and at most 2 per artist and per movie so one favourite doesn't take over.
     */
    fun seeds(repo: PlaylistRepository, count: Int): List<RecommendationService.Seed> {
        val ranked = repo.allUniqueTracks
            .filter { it.sourceType == TrackSourceType.YOUTUBE }
            .map { it to weight(it, repo.isFavorite(it)) }
            .filter { it.second > 1 }
            .sortedByDescending { it.second }
        val perArtist = mutableMapOf<String, Int>()
        val perMovie = mutableMapOf<String, Int>()
        val pool = mutableListOf<Pair<MediaTrack, Double>>()
        for ((t, w) in ranked) {
            val artist = ArtistPhotoService.normalize(PlaylistRepository.splitArtists(t.artist).firstOrNull() ?: t.artist)
            val movie = ArtistPhotoService.normalize(t.movieName ?: "")
            if ((perArtist[artist] ?: 0) >= 2) continue
            if (movie.isNotEmpty() && (perMovie[movie] ?: 0) >= 2) continue
            perArtist[artist] = (perArtist[artist] ?: 0) + 1
            if (movie.isNotEmpty()) perMovie[movie] = (perMovie[movie] ?: 0) + 1
            pool.add(t to w)
            if (pool.size >= 60) break
        }
        // weighted random pick without replacement
        val chosen = mutableListOf<RecommendationService.Seed>()
        val remaining = pool.toMutableList()
        while (chosen.size < count && remaining.isNotEmpty()) {
            var r = Random.nextDouble() * max(remaining.sumOf { it.second }, 0.001)
            var index = 0
            for ((i, item) in remaining.withIndex()) {
                r -= item.second
                if (r <= 0) { index = i; break }
            }
            val item = remaining.removeAt(index)
            chosen.add(RecommendationService.Seed(item.first, item.second))
        }
        return chosen
    }

    fun knownSongs(repo: PlaylistRepository): List<RecommendationService.KnownSong> =
        repo.allUniqueTracks.mapNotNull { t ->
            val key = YouTubeService.translit(t.coreTitle)
            if (key.length < 5) return@mapNotNull null
            val context = PlaylistRepository.splitArtists(t.artist).map { YouTubeService.translit(it) }.filter { it.length >= 4 }.toMutableList()
            t.movieName?.let { YouTubeService.translit(it) }?.takeIf { it.length >= 3 }?.let { context.add(it) }
            RecommendationService.KnownSong(key, context)
        }

    fun profile(repo: PlaylistRepository): RecommendationService.TasteProfile {
        val artists = repo.allArtists.filter { it.totalPlayCount > 0 }
        val maxPlays = (artists.maxOfOrNull { it.totalPlayCount } ?: 1).toDouble()
        val weights = mutableMapOf<String, Double>()
        val display = mutableMapOf<String, String>()
        val words = mutableMapOf<String, List<String>>()
        for (a in artists) {
            val key = ArtistPhotoService.normalize(a.name)
            weights[key] = ln(1.0 + a.totalPlayCount) / ln(1.0 + maxPlays)
            display[key] = a.name
            words[key] = a.name.lowercase().split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }
        }
        val langPlays = mutableMapOf<String, Double>()
        for (t in repo.allUniqueTracks) {
            if (t.totalPlays <= 0) continue
            val lang = t.releaseLanguage ?: if (t.genre?.lowercase() == "bollywood") "hindi" else if (t.isIndianRelease) null else "english"
            if (lang != null) langPlays[lang] = (langPlays[lang] ?: 0.0) + t.totalPlays
        }
        val total = max(langPlays.values.sum(), 1.0)
        val languages = langPlays.map { it.key to it.value / total }.sortedByDescending { it.second }
        return RecommendationService.TasteProfile(weights, display, words, languages)
    }
}
