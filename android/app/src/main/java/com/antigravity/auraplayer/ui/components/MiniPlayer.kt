package com.antigravity.auraplayer.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.antigravity.auraplayer.service.PlaybackManager
import com.antigravity.auraplayer.ui.theme.*

/** Floating glass bar with the playing song: tap to open the player; play, next and song options */
@Composable
fun MiniPlayer(
    playbackManager: PlaybackManager,
    onClick: () -> Unit,
    onChangeVideo: () -> Unit,
    onAddToPlaylist: () -> Unit,
    modifier: Modifier = Modifier
) {
    val track by playbackManager.currentTrack.collectAsState()
    val isPlaying by playbackManager.isPlaying.collectAsState()
    val position by playbackManager.currentPosition.collectAsState()
    val duration by playbackManager.duration.collectAsState()
    val artworkUrl by playbackManager.artworkUrl.collectAsState()
    val t = track ?: return
    val progress = if (duration > 0) position.toFloat() / duration else 0f
    val shape = RoundedCornerShape(22.dp)

    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .shadow(14.dp, shape, ambientColor = Color(0x66000000), spotColor = Color(0x66000000))
            .background(BackdropBottom.copy(alpha = 0.93f), shape)
            .glass(shape, alpha = 0.14f)
            .clickable { onClick() }
    ) {
        // Progress along the top edge
        Box(Modifier.fillMaxWidth().height(2.5.dp).background(Color.White.copy(alpha = 0.18f))) {
            Box(Modifier.fillMaxWidth(progress.coerceIn(0f, 1f)).fillMaxHeight().background(NeonPurple))
        }

        Row(
            modifier = Modifier.fillMaxWidth().padding(start = 12.dp, end = 4.dp, top = 9.dp, bottom = 9.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            TrackArtwork(t, 46.dp, 10.dp, overrideUrl = artworkUrl)
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(t.title, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(t.artist, fontSize = 12.sp, color = TextSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            IconButton(onClick = { playbackManager.togglePlayPause() }) {
                Icon(if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                    contentDescription = if (isPlaying) "Pause" else "Play", tint = TextPrimary, modifier = Modifier.size(28.dp))
            }
            IconButton(onClick = { playbackManager.playNext() }) {
                Icon(Icons.Default.SkipNext, contentDescription = "Next", tint = TextSecondary, modifier = Modifier.size(26.dp))
            }
            CurrentSongMenu(playbackManager, onChangeVideo, onAddToPlaylist)
        }
    }
}
