package com.antigravity.auraplayer.data

import android.content.Context
import com.antigravity.auraplayer.model.ArtistGroup
import com.antigravity.auraplayer.model.MediaTrack
import com.antigravity.auraplayer.model.Playlist
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.util.UUID

class PlaylistRepository(private val context: Context) {
    private val json = Json {
        ignoreUnknownKeys = true
        prettyPrint = true
    }

    private val playlistsFile = File(context.filesDir, "playlists.json")

    private val _playlists = MutableStateFlow<List<Playlist>>(emptyList())
    val playlists: StateFlow<List<Playlist>> = _playlists.asStateFlow()

    var favoritesPlaylistId: String = ""
        private set

    init {
        loadPlaylists()
    }

    private fun loadPlaylists() {
        if (!playlistsFile.exists()) {
            setupDefaults()
            return
        }

        try {
            val content = playlistsFile.readText()
            val list = json.decodeFromString<List<Playlist>>(content)
            if (list.isEmpty()) {
                setupDefaults()
            } else {
                _playlists.value = list
                favoritesPlaylistId = list.firstOrNull { it.name == "Favorites" }?.id ?: list.first().id
            }
        } catch (e: Exception) {
            setupDefaults()
        }
    }

    private fun setupDefaults() {
        val favId = UUID.randomUUID().toString()
        val favorites = Playlist(
            id = favId,
            name = "Favorites",
            iconName = "favorite",
            tracks = emptyList(),
            isBuiltIn = true
        )

        val sampleTracks = listOf(
            MediaTrack(
                title = "Powerhouse",
                artist = "Anirudh Ravichander & Arivu",
                duration = 206.0,
                originalURL = "https://www.youtube.com/watch?v=kY3bu_pA93k",
                youtubeId = "kY3bu_pA93k",
                thumbnailURL = "https://img.youtube.com/vi/kY3bu_pA93k/hqdefault.jpg"
            ),
            MediaTrack(
                title = "Hukum - Thalaivar Alappara",
                artist = "Anirudh Ravichander",
                duration = 207.0,
                originalURL = "https://www.youtube.com/watch?v=1F3hm6MfR1k",
                youtubeId = "1F3hm6MfR1k",
                thumbnailURL = "https://img.youtube.com/vi/1F3hm6MfR1k/hqdefault.jpg"
            ),
            MediaTrack(
                title = "Bilionera",
                artist = "Otilia",
                duration = 185.0,
                originalURL = "https://www.youtube.com/watch?v=j5-yKhDd64s",
                youtubeId = "j5-yKhDd64s",
                thumbnailURL = "https://img.youtube.com/vi/j5-yKhDd64s/hqdefault.jpg"
            )
        )

        val music = Playlist(
            name = "Vibes & Favorites",
            iconName = "music_note",
            tracks = sampleTracks,
            isBuiltIn = false
        )

        val initial = listOf(favorites, music)
        _playlists.value = initial
        favoritesPlaylistId = favId
        savePlaylists()
    }

    private fun savePlaylists() {
        try {
            val content = json.encodeToString(_playlists.value)
            playlistsFile.writeText(content)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun addPlaylist(name: String, iconName: String = "playlist_play"): Playlist {
        val trimmed = name.trim()
        val newPlaylist = Playlist(
            name = trimmed.ifEmpty { "New Playlist" },
            iconName = iconName,
            tracks = emptyList(),
            isBuiltIn = false
        )
        _playlists.value = _playlists.value + newPlaylist
        savePlaylists()
        return newPlaylist
    }

    fun renamePlaylist(id: String, newName: String) {
        val trimmed = newName.trim()
        if (trimmed.isEmpty()) return
        _playlists.value = _playlists.value.map {
            if (it.id == id && !it.isBuiltIn) it.copy(name = trimmed) else it
        }
        savePlaylists()
    }

    fun deletePlaylist(id: String) {
        _playlists.value = _playlists.value.filterNot { it.id == id && !it.isBuiltIn }
        savePlaylists()
    }

    fun addTrackToPlaylist(playlistId: String, track: MediaTrack, allowDuplicate: Boolean = false) {
        _playlists.value = _playlists.value.map { pl ->
            if (pl.id == playlistId) {
                val exists = pl.tracks.any { it.originalURL == track.originalURL || (it.youtubeId != null && it.youtubeId == track.youtubeId) }
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

    // MARK: - Duplicate Detection

    /** Same song: same YouTube video, same link, or same title and artist. */
    fun isSameSong(a: MediaTrack, b: MediaTrack): Boolean {
        if (!a.youtubeId.isNullOrEmpty() && a.youtubeId == b.youtubeId) return true
        if (a.originalURL.isNotEmpty() && a.originalURL.equals(b.originalURL, ignoreCase = true)) return true
        fun key(t: MediaTrack) = "${t.title.trim().lowercase()}|${t.artist.trim().lowercase()}"
        return a.title.isNotEmpty() && key(a) == key(b)
    }

    /** Playlists that already contain the given song. */
    fun playlistsContaining(track: MediaTrack): List<Playlist> =
        _playlists.value.filter { pl -> pl.tracks.any { isSameSong(it, track) } }

    fun removeTrackFromPlaylist(playlistId: String, trackId: String) {
        _playlists.value = _playlists.value.map { pl ->
            if (pl.id == playlistId) {
                pl.copy(tracks = pl.tracks.filterNot { it.id == trackId })
            } else pl
        }
        savePlaylists()
    }

    fun toggleFavorite(track: MediaTrack) {
        val fav = _playlists.value.firstOrNull { it.id == favoritesPlaylistId } ?: return
        val isFav = fav.tracks.any { it.originalURL == track.originalURL }

        if (isFav) {
            removeTrackFromPlaylist(favoritesPlaylistId, track.id)
        } else {
            addTrackToPlaylist(favoritesPlaylistId, track.copy(isFavorite = true))
        }

        // update isFavorite flag across other tracks
        _playlists.value = _playlists.value.map { pl ->
            pl.copy(tracks = pl.tracks.map {
                if (it.originalURL == track.originalURL) it.copy(isFavorite = !isFav) else it
            })
        }
        savePlaylists()
    }

    fun updateTrackVideo(trackId: String, newVideoId: String) {
        val newThumb = "https://img.youtube.com/vi/$newVideoId/hqdefault.jpg"
        _playlists.value = _playlists.value.map { pl ->
            pl.copy(tracks = pl.tracks.map { tr ->
                if (tr.id == trackId) {
                    tr.copy(
                        youtubeId = newVideoId,
                        thumbnailURL = newThumb,
                        originalURL = "https://www.youtube.com/watch?v=$newVideoId"
                    )
                } else tr
            })
        }
        savePlaylists()
    }

    fun recordPlay(track: MediaTrack) {
        val now = System.currentTimeMillis()
        _playlists.value = _playlists.value.map { pl ->
            pl.copy(tracks = pl.tracks.map { tr ->
                if (tr.originalURL == track.originalURL || tr.id == track.id) {
                    tr.copy(playCount = tr.playCount + 1, lastPlayedDate = now)
                } else tr
            })
        }
        savePlaylists()
    }

    // MARK: - Merging Playlists
    fun mergePlaylists(
        sourceId: String,
        targetId: String,
        skipDuplicates: Boolean = true,
        deleteSource: Boolean = false
    ): Int {
        val source = _playlists.value.firstOrNull { it.id == sourceId } ?: return 0
        val target = _playlists.value.firstOrNull { it.id == targetId } ?: return 0

        fun normalizedKey(t: MediaTrack): String =
            "${t.title.trim().lowercase()}|${t.artist.trim().lowercase()}"

        val existingKeys = target.tracks.map { normalizedKey(it) }.toMutableSet()
        val existingUrls = target.tracks.map { it.originalURL.lowercase() }.toMutableSet()

        val toAdd = mutableListOf<MediaTrack>()
        for (track in source.tracks) {
            val key = normalizedKey(track)
            val url = track.originalURL.lowercase()
            if (skipDuplicates) {
                if (!existingKeys.contains(key) && !existingUrls.contains(url)) {
                    toAdd.add(track)
                    existingKeys.add(key)
                    existingUrls.add(url)
                }
            } else {
                toAdd.add(track)
            }
        }

        _playlists.value = _playlists.value.map { pl ->
            if (pl.id == targetId) pl.copy(tracks = pl.tracks + toAdd) else pl
        }

        if (deleteSource && !source.isBuiltIn) {
            _playlists.value = _playlists.value.filterNot { it.id == sourceId }
        }

        savePlaylists()
        return toAdd.size
    }

    fun createMergedPlaylist(
        name: String,
        sourceIds: List<String>,
        skipDuplicates: Boolean = true,
        deleteSources: Boolean = false
    ): String? {
        val trimmed = name.trim()
        if (trimmed.isEmpty() || sourceIds.isEmpty()) return null

        fun normalizedKey(t: MediaTrack): String =
            "${t.title.trim().lowercase()}|${t.artist.trim().lowercase()}"

        val existingKeys = mutableSetOf<String>()
        val existingUrls = mutableSetOf<String>()
        val combined = mutableListOf<MediaTrack>()

        for (id in sourceIds) {
            val pl = _playlists.value.firstOrNull { it.id == id } ?: continue
            for (track in pl.tracks) {
                val key = normalizedKey(track)
                val url = track.originalURL.lowercase()
                if (skipDuplicates) {
                    if (!existingKeys.contains(key) && !existingUrls.contains(url)) {
                        combined.add(track)
                        existingKeys.add(key)
                        existingUrls.add(url)
                    }
                } else {
                    combined.add(track)
                }
            }
        }

        val newPlaylist = Playlist(
            name = trimmed,
            iconName = "playlist_play",
            tracks = combined,
            isBuiltIn = false
        )

        val updated = _playlists.value.toMutableList()
        updated.add(newPlaylist)

        if (deleteSources) {
            val deleteSet = sourceIds.toSet()
            updated.removeAll { deleteSet.contains(it.id) && !it.isBuiltIn }
        }

        _playlists.value = updated
        savePlaylists()
        return newPlaylist.id
    }

    // MARK: - Queries
    val mostPlayedTracks: List<MediaTrack>
        get() {
            val all = _playlists.value.flatMap { it.tracks }
            return all.distinctBy { "${it.title.lowercase()}-${it.artist.lowercase()}" }
                .filter { it.playCount > 0 }
                .sortedByDescending { it.playCount }
        }

    val allArtists: List<ArtistGroup>
        get() {
            val all = _playlists.value.flatMap { it.tracks }
                .distinctBy { "${it.title.lowercase()}-${it.artist.lowercase()}" }

            val grouped = all.groupBy { it.artist.trim() }
            return grouped.map { (artist, tracks) ->
                ArtistGroup(
                    name = artist,
                    trackCount = tracks.size,
                    totalPlayCount = tracks.sumOf { it.playCount },
                    tracks = tracks,
                    sampleArtworkURL = tracks.firstOrNull { it.thumbnailURL != null }?.thumbnailURL
                )
            }.sortedByDescending { it.totalPlayCount }
        }
}
