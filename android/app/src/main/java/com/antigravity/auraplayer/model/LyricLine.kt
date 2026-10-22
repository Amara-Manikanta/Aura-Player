package com.antigravity.auraplayer.model

import kotlinx.serialization.Serializable

@Serializable
data class LyricLine(
    val timeMs: Long,
    val text: String
)
