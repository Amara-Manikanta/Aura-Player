package com.antigravity.auraplayer.ui.components

import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.antigravity.auraplayer.model.LyricLine
import com.antigravity.auraplayer.model.MediaTrack
import com.antigravity.auraplayer.service.PlaybackManager
import com.antigravity.auraplayer.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FullPlayerSheet(
    playbackManager: PlaybackManager,
    track: MediaTrack?,
    isPlaying: Boolean,
    positionMs: Long,
    durationMs: Long,
    isAudioOnly: Boolean,
    isShuffled: Boolean,
    syncedLyrics: List<LyricLine>?,
    plainLyrics: String?,
    currentLyricIndex: Int,
    onDismiss: () -> Unit,
    onPlayPause: () -> Unit,
    onSeek: (Long) -> Unit,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    onToggleAudioOnly: () -> Unit,
    onToggleShuffle: () -> Unit,
    onToggleFavorite: () -> Unit,
    onChangeVideo: () -> Unit,
    onEnterPiP: () -> Unit
) {
    if (track == null) return

    var showLyricsTab by remember { mutableStateOf(false) }

    // Modern artwork scaling animation
    val artworkScale by animateFloatAsState(
        targetValue = if (isPlaying) 1f else 0.85f,
        animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessLow),
        label = "artworkScale"
    )

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        NeonPurple.copy(alpha = 0.25f),
                        BackgroundDark,
                        BackgroundDark
                    )
                )
            )
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = 24.dp, vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Top Bar
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Default.KeyboardArrowDown, contentDescription = "Collapse", tint = TextPrimary, modifier = Modifier.size(32.dp))
                }

                // Audio / Video Toggle Pill
                Row(
                    modifier = Modifier
                        .clip(RoundedCornerShape(20.dp))
                        .background(SurfaceCard)
                        .padding(4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(16.dp))
                            .background(if (isAudioOnly) NeonPurple else SurfaceCard)
                            .clickable { if (!isAudioOnly) onToggleAudioOnly() }
                            .padding(horizontal = 14.dp, vertical = 6.dp)
                    ) {
                        Text("Audio", style = MaterialTheme.typography.labelSmall, color = TextPrimary, fontWeight = FontWeight.Bold)
                    }

                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(16.dp))
                            .background(if (!isAudioOnly) NeonPink else SurfaceCard)
                            .clickable { if (isAudioOnly) onToggleAudioOnly() }
                            .padding(horizontal = 14.dp, vertical = 6.dp)
                    ) {
                        Text("Video", style = MaterialTheme.typography.labelSmall, color = TextPrimary, fontWeight = FontWeight.Bold)
                    }
                }

                Row {
                    if (!isAudioOnly && track.youtubeId != null) {
                        IconButton(onClick = onEnterPiP) {
                            Icon(Icons.Default.PictureInPictureAlt, contentDescription = "PiP", tint = TextSecondary)
                        }
                    }
                    IconButton(onClick = onChangeVideo) {
                        Icon(Icons.Default.Link, contentDescription = "Change Video", tint = TextSecondary)
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Center Content: Vinyl/Artwork vs Video vs Lyrics
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                contentAlignment = Alignment.Center
            ) {
                if (showLyricsTab) {
                    LyricsView(
                        syncedLyrics = syncedLyrics,
                        plainLyrics = plainLyrics,
                        currentLyricIndex = currentLyricIndex,
                        onSeekToTime = onSeek
                    )
                } else if (!isAudioOnly && track.youtubeId != null) {
                    // Video View
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .aspectRatio(16f / 9f)
                            .clip(RoundedCornerShape(16.dp))
                            .shadow(16.dp)
                    ) {
                        VideoPlayerView(playbackManager = playbackManager)
                    }
                } else {
                    // Audio Mode: Modern Scalable Artwork
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .aspectRatio(1f)
                            .padding(24.dp)
                            .graphicsLayer {
                                scaleX = artworkScale
                                scaleY = artworkScale
                            }
                            .shadow(24.dp, shape = RoundedCornerShape(24.dp))
                            .clip(RoundedCornerShape(24.dp))
                            .background(SurfaceDark),
                        contentAlignment = Alignment.Center
                    ) {
                        if (track.thumbnailURL != null) {
                            AsyncImage(
                                model = track.thumbnailURL,
                                contentDescription = null,
                                modifier = Modifier.fillMaxSize(),
                                contentScale = ContentScale.Crop
                            )
                        } else {
                            Icon(Icons.Default.MusicNote, contentDescription = null, tint = TextTertiary, modifier = Modifier.size(64.dp))
                        }
                    }
                }
            } 

            Spacer(modifier = Modifier.height(32.dp))

            // Track Info
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = track.title,
                    style = MaterialTheme.typography.headlineSmall,
                    color = TextPrimary,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = track.artist,
                    style = MaterialTheme.typography.titleMedium,
                    color = TextSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Progress Bar
            val progress = if (durationMs > 0) (positionMs.toFloat() / durationMs.toFloat()).coerceIn(0f, 1f) else 0f
            Slider(
                value = progress,
                onValueChange = { onSeek((it * durationMs).toLong()) },
                modifier = Modifier.fillMaxWidth(),
                colors = SliderDefaults.colors(
                    thumbColor = NeonPink,
                    activeTrackColor = NeonPink,
                    inactiveTrackColor = SurfaceCard
                )
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(formatDuration(positionMs / 1000.0), style = MaterialTheme.typography.labelSmall, color = TextTertiary)
                Text(formatDuration(durationMs / 1000.0), style = MaterialTheme.typography.labelSmall, color = TextTertiary)
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Controls
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = onToggleShuffle) {
                    Icon(Icons.Default.Shuffle, contentDescription = "Shuffle", tint = if (isShuffled) NeonPink else TextTertiary)
                }
                IconButton(onClick = onPrevious) {
                    Icon(Icons.Default.SkipPrevious, contentDescription = "Previous", tint = TextPrimary, modifier = Modifier.size(48.dp))
                }
                Box(
                    modifier = Modifier
                        .size(72.dp)
                        .clip(CircleShape)
                        .background(NeonPink)
                        .clickable { onPlayPause() },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                        contentDescription = "Play/Pause",
                        tint = BackgroundDark,
                        modifier = Modifier.size(40.dp)
                    )
                }
                IconButton(onClick = onNext) {
                    Icon(Icons.Default.SkipNext, contentDescription = "Next", tint = TextPrimary, modifier = Modifier.size(48.dp))
                }
                IconButton(onClick = onToggleFavorite) {
                    Icon(if (track.isFavorite) Icons.Default.Favorite else Icons.Default.FavoriteBorder, contentDescription = "Favorite", tint = if (track.isFavorite) NeonPink else TextTertiary)
                }
            }
        }
    }
}

private fun formatDuration(seconds: Double): String {
    if (seconds <= 0) return "--:--"
    val total = seconds.toInt()
    return "%d:%02d".format(total / 60, total % 60)
}
