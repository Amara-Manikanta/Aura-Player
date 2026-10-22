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
    var lastPlayedDate: Long? = null
)
