package com.antigravity.auraplayer.data

import android.content.Context
import android.util.Log
import com.antigravity.auraplayer.model.ArtistGroup
import com.antigravity.auraplayer.model.MediaTrack
import com.antigravity.auraplayer.model.Playlist
import com.antigravity.auraplayer.service.ArtistPhotoService
import com.antigravity.auraplayer.service.YouTubeService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.util.UUID

class PlaylistRepository private constructor(private val context: Context) {
    companion object {
        private const val TAG = "AuraPlayer/Library"

        @Volatile
        private var instance: PlaylistRepository? = null

        fun getInstance(context: Context): PlaylistRepository =
            instance ?: synchronized(this) {
                instance ?: PlaylistRepository(context.applicationContext).also { instance = it }
            }

        /** Acts whose names contain a separator but are one act */
        private val WHOLE_NAMES = listOf(
            "Simon & Garfunkel", "Earth, Wind & Fire", "Hall & Oates", "Florence + The Machine",
            "Mumford & Sons", "Years & Years", "Of Monsters and Men", "Tom & Jerry",
            "Shankar-Ehsaan-Loy", "Vishal-Shekhar", "Vishal & Shekhar", "Salim-Sulaiman", "Salim–Sulaiman",
            "Sachin-Jigar", "Jatin-Lalit", "Laxmikant-Pyarelal", "Nadeem-Shravan"
        )

        /** "Zedd & Katy Perry" → ["Zedd", "Katy Perry"]; "Hari (Live), Chitra feat. X" → ["Hari", "Chitra", "X"] */
        fun splitArtists(raw: String): List<String> {
            var text = raw.replace(Regex("\\s*[(\\[][^)\\]]*[)\\]]"), "")
            val shielded = mutableMapOf<String, String>()
            WHOLE_NAMES.forEachIndexed { i, whole ->
                if (text.contains(whole, ignoreCase = true)) {
                    val token = "§$i§"
                    shielded[token] = whole
                    text = text.replace(whole, token, ignoreCase = true)
                }
            }
            val parts = text.replace(Regex("(?i)\\s+(feat\\.?|ft\\.?|featuring|with|vs\\.?|x)\\s+"), ",")
                .split('&', ',', ';', '/', '+')
            val seen = mutableSetOf<String>()
            val result = mutableListOf<String>()
            for (part in parts) {
                var name = part.trim()
                for ((token, whole) in shielded) name = name.replace(token, whole)
                val key = ArtistPhotoService.normalize(name)
                if (key.isEmpty() || name.equals("various artists", true) || name == "Unknown Artist" || !seen.add(key)) continue
                result.add(name)
            }
            return result
        }

        /** Same song: same YouTube video, same link, or same title and artist. */
        fun isSameSong(a: MediaTrack, b: MediaTrack): Boolean {
            if (!a.youtubeId.isNullOrEmpty() && a.youtubeId == b.youtubeId) return true
            if (a.originalURL.isNotEmpty() && a.originalURL.equals(b.originalURL, ignoreCase = true)) return true
            fun key(t: MediaTrack) = "${t.title.trim().lowercase()}|${t.artist.trim().lowercase()}"
            return a.title.isNotEmpty() && key(a) == key(b)
        }
    }

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    private val playlistsFile = File(context.filesDir, "playlists.json")

    private val _playlists = MutableStateFlow<List<Playlist>>(emptyList())
    val playlists: StateFlow<List<Playlist>> = _playlists.asStateFlow()

    val favoritesPlaylistId: String
        get() = _playlists.value.firstOrNull { it.isBuiltIn && it.name.equals("Favorites", true) }?.id
            ?: _playlists.value.firstOrNull { it.name.equals("Favorites", true) }?.id
            ?: ""

    init {
        loadPlaylists()
    }

    // region Storage

    /** Saved library if it's real; otherwise the Mac library bundled with the app. */
    private fun loadPlaylists() {
        val saved = try {
            if (playlistsFile.exists()) json.decodeFromString<List<Playlist>>(playlistsFile.readText()) else emptyList()
        } catch (e: Exception) {
            Log.w(TAG, "saved library unreadable", e)
            emptyList()
        }
        // The old sample library had 3 songs: anything that small gets the real library instead
        if (saved.sumOf { it.tracks.size } > 10) {
            _playlists.value = saved
            return
        }
        val mac = MacLibraryImporter.load(context)
        _playlists.value = mac.ifEmpty { listOf(Playlist(name = "Favorites", iconName = "heart.fill", isBuiltIn = true)) }
        savePlaylists()
    }

    /** Throws away changes made on the phone and starts again from the Mac library. */
    fun resetToMacLibrary() {
        val mac = MacLibraryImporter.load(context)
        if (mac.isNotEmpty()) {
            _playlists.value = mac
            savePlaylists()
        }
    }

    private fun savePlaylists() {
        try {
            playlistsFile.writeText(json.encodeToString(_playlists.value))
        } catch (e: Exception) {
            Log.w(TAG, "save failed", e)
        }
    }

    /** Applies a change to every saved copy of the songs matching `match`, then saves. */
    private fun updateTracks(match: (MediaTrack) -> Boolean, change: (MediaTrack) -> MediaTrack) {
        _playlists.value = _playlists.value.map { pl ->
            pl.copy(tracks = pl.tracks.map { if (match(it)) change(it) else it })
        }
        savePlaylists()
    }

    fun savedTrack(id: String): MediaTrack? =
        _playlists.value.asSequence().flatMap { it.tracks }.firstOrNull { it.id == id }

    // endregion

    // region Playlists

    fun addPlaylist(name: String, iconName: String = "playlist_play"): Playlist {
        val newPlaylist = Playlist(name = name.trim().ifEmpty { "New Playlist" }, iconName = iconName)
        _playlists.value = _playlists.value + newPlaylist
        savePlaylists()
        return newPlaylist
    }

    fun renamePlaylist(id: String, newName: String) {
        val trimmed = newName.trim()
        if (trimmed.isEmpty()) return
        _playlists.value = _playlists.value.map { if (it.id == id && !it.isBuiltIn) it.copy(name = trimmed) else it }
        savePlaylists()
    }

    fun deletePlaylist(id: String) {
        _playlists.value = _playlists.value.filterNot { it.id == id && !it.isBuiltIn }
        savePlaylists()
    }

    fun addTrackToPlaylist(playlistId: String, track: MediaTrack, allowDuplicate: Boolean = false) {
        _playlists.value = _playlists.value.map { pl ->
            if (pl.id == playlistId) {
                val exists = pl.tracks.any { isSameSong(it, track) }
                when {
                    !exists -> pl.copy(tracks = pl.tracks + track)
                    // A second copy needs its own id so list keys stay unique
                    allowDuplicate -> pl.copy(tracks = pl.tracks + track.copy(id = UUID.randomUUID().toString()))
                    else -> pl
                }
            } else pl
        }
        savePlaylists()
    }

    /** Playlists that already contain the given song. */
    fun playlistsContaining(track: MediaTrack): List<Playlist> =
        _playlists.value.filter { pl -> pl.tracks.any { isSameSong(it, track) } }

    fun removeTrackFromPlaylist(playlistId: String, trackId: String) {
        _playlists.value = _playlists.value.map { pl ->
            if (pl.id == playlistId) pl.copy(tracks = pl.tracks.filterNot { it.id == trackId }) else pl
        }
        savePlaylists()
    }

    enum class TransferResult { MOVED, COPIED, ALREADY_THERE, NOT_FOUND }

    fun moveTrack(trackId: String, fromId: String, toId: String): TransferResult {
        if (fromId == toId) return TransferResult.NOT_FOUND
        val track = _playlists.value.firstOrNull { it.id == fromId }?.tracks?.firstOrNull { it.id == trackId }
            ?: return TransferResult.NOT_FOUND
        val dest = _playlists.value.firstOrNull { it.id == toId } ?: return TransferResult.NOT_FOUND
        val exists = dest.tracks.any { isSameSong(it, track) }
        _playlists.value = _playlists.value.map { pl ->
            when (pl.id) {
                fromId -> pl.copy(tracks = pl.tracks.filterNot { it.id == trackId })
                toId -> if (exists) pl else pl.copy(tracks = pl.tracks + track)
                else -> pl
            }
        }
        savePlaylists()
        return if (exists) TransferResult.ALREADY_THERE else TransferResult.MOVED
    }

    fun copyTrack(track: MediaTrack, toId: String): TransferResult {
        val dest = _playlists.value.firstOrNull { it.id == toId } ?: return TransferResult.NOT_FOUND
        if (dest.tracks.any { isSameSong(it, track) }) return TransferResult.ALREADY_THERE
        val copy = if (dest.tracks.any { it.id == track.id }) track.copy(id = UUID.randomUUID().toString()) else track
        _playlists.value = _playlists.value.map { if (it.id == toId) it.copy(tracks = it.tracks + copy) else it }
        savePlaylists()
        return TransferResult.COPIED
    }

    // endregion

    // region Favorites, video, trims, plays

    fun isFavorite(track: MediaTrack): Boolean =
        _playlists.value.firstOrNull { it.id == favoritesPlaylistId }?.tracks?.any { isSameSong(it, track) } == true

    fun toggleFavorite(track: MediaTrack) {
        val favId = favoritesPlaylistId.ifEmpty { return }
        val fav = _playlists.value.first { it.id == favId }
        val existing = fav.tracks.firstOrNull { isSameSong(it, track) }
        _playlists.value = _playlists.value.map { pl ->
            if (pl.id == favId) {
                if (existing != null) pl.copy(tracks = pl.tracks.filterNot { it.id == existing.id })
                else pl.copy(tracks = pl.tracks + track.copy(isFavorite = true))
            } else pl
        }
        savePlaylists()
    }

    /** Updates the title and artist for all copies of the song in all playlists. */
    fun renameTrack(trackId: String, newTitle: String, newArtist: String) {
        val track = savedTrack(trackId)
        val cleanTitle = newTitle.trim()
        val cleanArtist = newArtist.trim().ifEmpty { "Unknown Artist" }
        updateTracks({ it.id == trackId || (track != null && isSameSong(it, track)) }) {
            it.copy(title = cleanTitle, artist = cleanArtist)
        }
    }

    /** Points a song (every copy of it) at a YouTube video: Change Video Link, or 👍 on the playing video. */
    fun setVideo(trackId: String, videoId: String) {
        val track = savedTrack(trackId)
        updateTracks({ it.id == trackId || (track != null && isSameSong(it, track)) }) {
            it.copy(youtubeId = videoId, thumbnailURL = "https://i.ytimg.com/vi/$videoId/hqdefault.jpg")
        }
    }

    /** Kept for existing callers */
    fun updateTrackVideo(trackId: String, newVideoId: String) = setVideo(trackId, newVideoId)

    /** 👎: never pick this video for the song again (and forget it if it was saved) */
    fun rejectVideo(trackId: String, videoId: String) {
        val track = savedTrack(trackId)
        updateTracks({ it.id == trackId || (track != null && isSameSong(it, track)) }) {
            it.copy(
                rejectedVideoIds = ((it.rejectedVideoIds ?: emptyList()) + videoId).distinct(),
                youtubeId = if (it.youtubeId == videoId) null else it.youtubeId
            )
        }
    }

    /** Where a song starts and stops, on every copy of it. */
    fun setTrimTimes(track: MediaTrack, start: Double?, end: Double?) {
        val s = start?.takeIf { it > 0 }
        updateTracks({ it.id == track.id || isSameSong(it, track) }) { it.copy(startTime = s, endTime = end) }
    }

    fun recordPlay(track: MediaTrack) {
        val now = System.currentTimeMillis()
        updateTracks({ it.id == track.id || isSameSong(it, track) }) {
            it.copy(playCount = it.playCount + 1, lastPlayedDate = now)
        }
    }

    // endregion

    // region Merging Playlists

    private fun normalizedKey(t: MediaTrack) = "${t.title.trim().lowercase()}|${t.artist.trim().lowercase()}"

    fun mergePlaylists(sourceId: String, targetId: String, skipDuplicates: Boolean = true, deleteSource: Boolean = false): Int {
        val source = _playlists.value.firstOrNull { it.id == sourceId } ?: return 0
        val target = _playlists.value.firstOrNull { it.id == targetId } ?: return 0
        val existingKeys = target.tracks.map { normalizedKey(it) }.toMutableSet()
        val existingUrls = target.tracks.map { it.originalURL.lowercase() }.toMutableSet()
        val toAdd = source.tracks.filter { track ->
            !skipDuplicates || (existingKeys.add(normalizedKey(track)) && existingUrls.add(track.originalURL.lowercase()))
        }
        _playlists.value = _playlists.value.map { if (it.id == targetId) it.copy(tracks = it.tracks + toAdd) else it }
        if (deleteSource && !source.isBuiltIn) _playlists.value = _playlists.value.filterNot { it.id == sourceId }
        savePlaylists()
        return toAdd.size
    }

    fun createMergedPlaylist(name: String, sourceIds: List<String>, skipDuplicates: Boolean = true, deleteSources: Boolean = false): String? {
        val trimmed = name.trim()
        if (trimmed.isEmpty() || sourceIds.isEmpty()) return null
        val keys = mutableSetOf<String>()
        val urls = mutableSetOf<String>()
        val combined = sourceIds.flatMap { id -> _playlists.value.firstOrNull { it.id == id }?.tracks ?: emptyList() }
            .filter { !skipDuplicates || (keys.add(normalizedKey(it)) && urls.add(it.originalURL.lowercase())) }
        val newPlaylist = Playlist(name = trimmed, tracks = combined)
        val deleteSet = if (deleteSources) sourceIds.toSet() else emptySet()
        _playlists.value = _playlists.value.filterNot { it.id in deleteSet && !it.isBuiltIn } + newPlaylist
        savePlaylists()
        return newPlaylist.id
    }

    // endregion

    // region Queries

    /** Every song once */
    val allUniqueTracks: List<MediaTrack>
        get() = _playlists.value.flatMap { it.tracks }.distinctBy { "${it.title.lowercase()}-${it.artist.lowercase()}" }

    /** Apple Music plays + plays in this app, most first (same as the Mac app) */
    val mostPlayedTracks: List<MediaTrack>
        get() = allUniqueTracks.filter { it.totalPlays > 0 }.sortedByDescending { it.totalPlays }

    /** Newest additions first (Apple Music's real "added" dates from the Mac) */
    val recentlyAddedTracks: List<MediaTrack>
        get() = allUniqueTracks.sortedByDescending { it.dateAdded }

    /** Every singer separately (a duet is listed under both), most songs first, like the Mac app */
    val allArtists: List<ArtistGroup>
        get() {
            val byArtist = mutableMapOf<String, MutableList<MediaTrack>>()
            val spellings = mutableMapOf<String, MutableMap<String, Int>>()
            for (t in allUniqueTracks) {
                for (name in splitArtists(t.artist)) {
                    val key = ArtistPhotoService.normalize(name)
                    if (key.isEmpty()) continue
                    byArtist.getOrPut(key) { mutableListOf() }.add(t)
                    val s = spellings.getOrPut(key) { mutableMapOf() }
                    s[name] = (s[name] ?: 0) + 1
                }
            }
            return byArtist.map { (key, tracks) ->
                ArtistGroup(
                    name = spellings[key]?.maxByOrNull { it.value }?.key ?: key,
                    trackCount = tracks.size,
                    totalPlayCount = tracks.sumOf { it.totalPlays },
                    tracks = tracks,
                    sampleArtworkURL = tracks.firstNotNullOfOrNull { it.thumbnailURL }
                )
            }.sortedWith(compareByDescending<ArtistGroup> { it.trackCount }.thenBy { it.name })
        }

    /** Songs matching a search: every word must match title, singer, album or movie (spelling-tolerant) */
    fun filter(tracks: List<MediaTrack>, query: String): List<MediaTrack> {
        val words = query.lowercase().split(" ").filter { it.isNotBlank() }
        if (words.isEmpty()) return tracks
        return tracks.filter { t ->
            val text = listOf(t.title, t.artist, t.album ?: "", t.movieName ?: "").joinToString(" ")
            val plain = text.lowercase()
            val loose = YouTubeService.translit(text)
            words.all { w -> plain.contains(w) || loose.contains(YouTubeService.translit(w)) }
        }
    }

    // endregion
}
