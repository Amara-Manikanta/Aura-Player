package com.antigravity.auraplayer.ui.components

import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.ThumbDown
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.antigravity.auraplayer.data.PlaylistRepository
import com.antigravity.auraplayer.service.DisplayMode
import com.antigravity.auraplayer.service.PlaybackManager
import com.antigravity.auraplayer.ui.theme.*

/** Now Playing, like the iPhone app: Audio / Video / Lyrics, 👍 👎 ♥, repeat, song options. */
@Composable
fun FullPlayerSheet(
    playbackManager: PlaybackManager,
    onDismiss: () -> Unit,
    onChangeVideo: () -> Unit,
    onAddToPlaylist: () -> Unit,
    onEnterPiP: () -> Unit
) {
    val context = LocalContext.current
    val repository = remember { PlaylistRepository.getInstance(context) }
    val track by playbackManager.currentTrack.collectAsState()
    val isPlaying by playbackManager.isPlaying.collectAsState()
    val positionMs by playbackManager.currentPosition.collectAsState()
    val durationMs by playbackManager.duration.collectAsState()
    val displayMode by playbackManager.displayMode.collectAsState()
    val isShuffled by playbackManager.isShuffled.collectAsState()
    val repeatMode by playbackManager.repeatMode.collectAsState()
    val syncedLyrics by playbackManager.syncedLyrics.collectAsState()
    val plainLyrics by playbackManager.plainLyrics.collectAsState()
    val currentLyricIndex by playbackManager.currentLyricIndex.collectAsState()
    val artworkUrl by playbackManager.artworkUrl.collectAsState()
    repository.playlists.collectAsState().value   // redraw when favourites / saved video change
    val t = track ?: return

    val artworkScale by animateFloatAsState(
        targetValue = if (isPlaying) 1f else 0.88f,
        animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessLow),
        label = "artworkScale"
    )

    Box(Modifier.fillMaxSize()) {
        AuraBackground()
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = 20.dp, vertical = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Top bar: collapse, Audio / Video / Lyrics, options
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Default.KeyboardArrowDown, contentDescription = "Collapse", tint = TextPrimary, modifier = Modifier.size(32.dp))
                }
                SegmentedTabs(
                    options = listOf("Audio", "Video", "Lyrics"),
                    selected = displayMode.ordinal,
                    onSelect = { playbackManager.setDisplayMode(DisplayMode.entries[it]) },
                    modifier = Modifier.weight(1f).padding(horizontal = 6.dp)
                )
                CurrentSongMenu(playbackManager, onChangeVideo, onAddToPlaylist, tint = TextPrimary)
            }

            Spacer(Modifier.height(16.dp))

            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                if (displayMode == DisplayMode.LYRICS) {
                    LyricsView(
                        syncedLyrics = syncedLyrics,
                        plainLyrics = plainLyrics,
                        currentLyricIndex = currentLyricIndex,
                        onSeekToTime = { playbackManager.seekTo(it) }
                    )
                } else if (displayMode == DisplayMode.VIDEO && t.youtubeId != null) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(14.dp))) {
                            VideoPlayerView(playbackManager = playbackManager)
                        }
                        TextButton(onClick = onEnterPiP) {
                            Icon(Icons.Default.PictureInPictureAlt, null, tint = TextSecondary)
                            Spacer(Modifier.width(6.dp))
                            Text("Picture in Picture", color = TextSecondary)
                        }
                    }
                } else {
                    // Album cover, breathing with play / pause
                    BoxWithConstraints(
                        Modifier
                            .fillMaxWidth(0.85f)
                            .aspectRatio(1f)
                            .graphicsLayer { scaleX = artworkScale; scaleY = artworkScale }
                            .shadow(28.dp, RoundedCornerShape(26.dp))
                    ) {
                        TrackArtwork(t, maxWidth, 26.dp, overrideUrl = artworkUrl)
                    }
                }
            }

            Spacer(Modifier.height(20.dp))

            // Title, singer, 👍 👎 ♥
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(t.title, color = TextPrimary, fontSize = 22.sp, fontWeight = FontWeight.Bold,
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(t.artist, color = TextSecondary, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    t.trimLabel?.let { Text("✂ Plays $it", color = NeonPurple, fontSize = 12.sp) }
                }
                if (t.youtubeId != null) {
                    val confirmed = playbackManager.isCurrentVideoConfirmed()
                    IconButton(onClick = { playbackManager.confirmCurrentVideo() }) {
                        Icon(if (confirmed) Icons.Default.ThumbUp else Icons.Outlined.ThumbUp, contentDescription = "Right video",
                            tint = if (confirmed) SuccessGreen else TextSecondary)
                    }
                    IconButton(onClick = { playbackManager.rejectCurrentVideo() }) {
                        Icon(Icons.Outlined.ThumbDown, contentDescription = "Wrong video", tint = TextSecondary)
                    }
                }
                val fav = repository.isFavorite(t)
                IconButton(onClick = { repository.toggleFavorite(t) }) {
                    Icon(if (fav) Icons.Default.Favorite else Icons.Default.FavoriteBorder, contentDescription = "Favorite",
                        tint = if (fav) NeonPurple else TextSecondary)
                }
            }

            Spacer(Modifier.height(12.dp))

            val progress = if (durationMs > 0) (positionMs.toFloat() / durationMs.toFloat()).coerceIn(0f, 1f) else 0f
            Slider(
                value = progress,
                onValueChange = { playbackManager.seekTo((it * durationMs).toLong()) },
                modifier = Modifier.fillMaxWidth(),
                colors = SliderDefaults.colors(
                    thumbColor = Color.White,
                    activeTrackColor = NeonPurple,
                    inactiveTrackColor = Color.White.copy(alpha = 0.22f)
                )
            )
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(formatDuration(positionMs / 1000.0), style = MaterialTheme.typography.labelSmall, color = TextTertiary)
                Text(formatDuration(durationMs / 1000.0), style = MaterialTheme.typography.labelSmall, color = TextTertiary)
            }

            Spacer(Modifier.height(16.dp))

            Row(
                Modifier.fillMaxWidth().padding(bottom = 12.dp),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = { playbackManager.toggleShuffle() }) {
                    Icon(Icons.Default.Shuffle, contentDescription = "Shuffle", tint = if (isShuffled) NeonPurple else TextTertiary)
                }
                IconButton(onClick = { playbackManager.playPrevious() }, modifier = Modifier.size(56.dp)) {
                    Icon(Icons.Default.SkipPrevious, contentDescription = "Previous", tint = TextPrimary, modifier = Modifier.size(42.dp))
                }
                // Frosted white glass button
                Box(
                    modifier = Modifier
                        .size(74.dp)
                        .shadow(16.dp, CircleShape, ambientColor = Color(0xFF3A2E9A), spotColor = Color(0xFF3A2E9A))
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.88f))
                        .border(1.5.dp, Color.White, CircleShape)
                        .clickable { playbackManager.togglePlayPause() },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                        contentDescription = "Play/Pause",
                        tint = BackdropTop,
                        modifier = Modifier.size(38.dp)
                    )
                }
                IconButton(onClick = { playbackManager.playNext() }, modifier = Modifier.size(56.dp)) {
                    Icon(Icons.Default.SkipNext, contentDescription = "Next", tint = TextPrimary, modifier = Modifier.size(42.dp))
                }
                IconButton(onClick = { playbackManager.toggleRepeat() }) {
                    Icon(
                        if (repeatMode == 2) Icons.Default.RepeatOne else Icons.Default.Repeat,
                        contentDescription = "Repeat",
                        tint = if (repeatMode > 0) NeonPurple else TextTertiary
                    )
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
