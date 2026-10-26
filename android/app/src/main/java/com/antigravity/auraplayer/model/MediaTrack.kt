package com.antigravity.auraplayer.model

import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
enum class TrackSourceType {
    LOCAL,
    YOUTUBE
}

@Serializable
enum class MediaType {
    AUDIO,
    VIDEO
}

@Serializable
data class MediaTrack(
    val id: String = UUID.randomUUID().toString(),
    var title: String,
    var artist: String = "Unknown Artist",
    var duration: Double = 0.0,
    var sourceType: TrackSourceType = TrackSourceType.YOUTUBE,
    var mediaType: MediaType = MediaType.AUDIO,
    var originalURL: String = "",
    var streamURL: String? = null,
    var thumbnailURL: String? = null,
    var isFavorite: Boolean = false,
    var dateAdded: Long = System.currentTimeMillis(),
    var youtubeId: String? = null,
    var playCount: Int = 0,
    var lastPlayedDate: Long? = null,
    /** Album as named in Apple Music, e.g. "Gabbar Singh (Original Motion Picture Soundtrack) - EP" */
    var album: String? = null,
    var composer: String? = null,
    var year: Int? = null,
    /** Apple Music genre, e.g. "Telugu", "Bollywood", "Regional Indian" */
    var genre: String? = null,
    /** Plays counted by Apple Music (from the Mac library) */
    var applePlayCount: Int? = null,
    /** Optional trim: playback starts at `startTime` and moves on at `endTime` (seconds) */
    var startTime: Double? = null,
    var endTime: Double? = null,
    /** Videos the user marked as wrong (👎) for this song; never picked again */
    var rejectedVideoIds: List<String>? = null
) {
    /** Plays in Apple Music plus plays in AuraPlayer */
    val totalPlays: Int get() = (applePlayCount ?: 0) + playCount

    /** "0:15 – 3:40" when the song is trimmed, otherwise null */
    val trimLabel: String?
        get() {
            if ((startTime ?: 0.0) <= 0 && endTime == null) return null
            fun fmt(s: Double) = "%d:%02d".format(s.toInt() / 60, s.toInt() % 60)
            return "${fmt(startTime ?: 0.0)} – ${endTime?.let(::fmt) ?: "end"}"
        }

    /** Song name without "(From "Movie")" style suffixes. */
    val coreTitle: String
        get() = title.replace(Regex("\\s*[(\\[].*$"), "").trim()

    /**
     * Movie / album name cleaned for searching: "Gabbar Singh (Original Motion Picture Soundtrack) - EP"
     * becomes "Gabbar Singh"; `Song (From "Movie")` in the title wins.
     */
    val movieName: String?
        get() {
            Regex("From \"([^\"]+)\"").find(title)?.let { return removingBrackets(it.groupValues[1]) }
            val a0 = album
            if (!a0.isNullOrEmpty()) {
                var a = removingBrackets(a0)
                for (suffix in listOf(" - EP", " - Single", " - Original Soundtrack")) {
                    if (a.endsWith(suffix)) a = a.dropLast(suffix.length)
                }
                a = a.trim()
                // Single releases are named after the song itself, which says nothing about the movie
                if (a.isNotEmpty() && !a.equals(coreTitle, ignoreCase = true)) return a
            }
            return null
        }

    /** Language this release is in, from "(Kannada)" / "Telugu Version" markers or the genre. */
    val releaseLanguage: String?
        get() {
            val text = "$title ${album ?: ""}".lowercase()
            INDIAN_LANGUAGES.firstOrNull { text.contains(it) }?.let { return it }
            val g = genre?.lowercase()
            return if (g != null && g in INDIAN_LANGUAGES) g else null
        }

    /** An Indian film/regional song, where dubbed versions in other languages exist. */
    val isIndianRelease: Boolean
        get() = releaseLanguage != null || genre?.lowercase() in INDIAN_GENRES

    /** What to type into YouTube to find this song's video: "Pillaa Gabbar Singh". */
    val videoSearchQuery: String
        get() {
            if (originalURL.lowercase().startsWith("http") || sourceType == TrackSourceType.LOCAL) {
                return "$coreTitle $artist"
            }
            // Film songs: the movie identifies the song best. Everything else: the artist.
            val movie = movieName
            if (isIndianRelease && movie != null) return "$coreTitle $movie"
            val cleanArtist = artist.replace(Regex("\\s*\\(.*?\\)"), "")
            return "$coreTitle $cleanArtist".trim()
        }

    val effectiveThumbnailURL: String?
        get() = thumbnailURL?.takeIf { it.isNotEmpty() }
            ?: youtubeId?.takeIf { it.isNotEmpty() }?.let { "https://i.ytimg.com/vi/$it/hqdefault.jpg" }

    val formattedDuration: String
        get() {
            if (duration <= 0) return "--:--"
            val t = duration.toInt()
            return if (t >= 3600) "%d:%02d:%02d".format(t / 3600, t / 60 % 60, t % 60) else "%d:%02d".format(t / 60, t % 60)
        }

    companion object {
        val INDIAN_LANGUAGES = listOf("telugu", "tamil", "hindi", "kannada", "malayalam", "bengali", "marathi", "punjabi")
        private val INDIAN_GENRES = setOf("telugu", "tamil", "hindi", "kannada", "malayalam", "bollywood", "tollywood",
            "regional indian", "indian", "indian pop", "indian classical", "punjabi")

        fun removingBrackets(s: String): String =
            s.replace(Regex("\\s*[(\\[][^)\\]]*[)\\]]"), "").trim()
    }
}
