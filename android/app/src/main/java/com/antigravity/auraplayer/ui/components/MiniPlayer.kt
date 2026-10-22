package com.antigravity.auraplayer.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.antigravity.auraplayer.model.MediaTrack
import com.antigravity.auraplayer.ui.theme.*

@Composable
fun MiniPlayer(
    track: MediaTrack?,
    isPlaying: Boolean,
    progress: Float,
    isAudioOnly: Boolean,
    onPlayPause: () -> Unit,
    onNext: () -> Unit,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    if (track == null) return

    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 12.dp)
            .clip(RoundedCornerShape(32.dp))
            .background(SurfaceCard.copy(alpha = 0.90f))
            .clickable { onClick() }
    ) {
        // Progress Bar on top edge
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(2.5.dp)
                .background(GlassBorder)
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth(progress.coerceIn(0f, 1f))
                    .fillMaxHeight()
                    .background(NeonPurple)
            )
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Thumbnail
            Box(
                modifier = Modifier
                    .size(46.dp)
                    .clip(androidx.compose.foundation.shape.CircleShape)
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
                    Icon(
                        imageVector = Icons.Default.MusicNote,
                        contentDescription = null,
                        tint = NeonPurple
                    )
                }
            }

            Spacer(modifier = Modifier.width(12.dp))

            // Details
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = track.title,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Bold,
                    color = TextPrimary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = track.artist,
                        style = MaterialTheme.typography.bodyMedium,
                        color = TextSecondary,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("•", color = TextTertiary, style = MaterialTheme.typography.labelSmall)
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = if (isAudioOnly) "Audio" else "Video",
                        style = MaterialTheme.typography.labelSmall,
                        color = if (isAudioOnly) AccentCyan else NeonPink,
                        fontWeight = FontWeight.Bold
                    )
                }
            }

            // Play / Pause
            IconButton(onClick = onPlayPause) {
                Icon(
                    imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                    contentDescription = if (isPlaying) "Pause" else "Play",
                    tint = TextPrimary,
                    modifier = Modifier.size(28.dp)
                )
            }

            // Next
            IconButton(onClick = onNext) {
                Icon(
                    imageVector = Icons.Default.SkipNext,
                    contentDescription = "Next",
                    tint = TextSecondary,
                    modifier = Modifier.size(26.dp)
                )
            }
        }
    }
}
