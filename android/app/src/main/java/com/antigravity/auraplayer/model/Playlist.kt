package com.antigravity.auraplayer.model

import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
data class Playlist(
    val id: String = UUID.randomUUID().toString(),
    var name: String,
    var iconName: String = "playlist_play",
    var tracks: List<MediaTrack> = emptyList(),
    val isBuiltIn: Boolean = false
)

data class ArtistGroup(
    val name: String,
    val trackCount: Int,
    val totalPlayCount: Int,
    val tracks: List<MediaTrack>,
    val sampleArtworkURL: String?
)
