package com.antigravity.auraplayer.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.antigravity.auraplayer.model.MediaTrack
import com.antigravity.auraplayer.ui.theme.*

import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.launch
import com.antigravity.auraplayer.utils.DownloadHelper

@Composable
fun TrackRow(
    track: MediaTrack,
    isCurrent: Boolean,
    isPlaying: Boolean,
    onPlay: () -> Unit,
    onPlayVideo: () -> Unit = {},
    onToggleFavorite: () -> Unit,
    onChangeVideo: () -> Unit,
    onRemove: (() -> Unit)? = null,
    onAddToPlaylist: (() -> Unit)? = null
) {
    var showMenu by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(if (isCurrent) NeonPurple.copy(alpha = 0.10f) else androidx.compose.ui.graphics.Color.Transparent)
            .clickable { onPlay() }
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Thumbnail
        Box(
            modifier = Modifier
                .size(48.dp)
                .clip(RoundedCornerShape(12.dp))
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

            if (isCurrent && isPlaying) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(BackgroundDark.copy(alpha = 0.5f)),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.Default.PlayArrow,
                        contentDescription = null,
                        tint = NeonPurple,
                        modifier = Modifier.size(24.dp)
                    )
                }
            }
        }

        Spacer(modifier = Modifier.width(12.dp))

        // Title and Artist
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = track.title,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = if (isCurrent) FontWeight.Bold else FontWeight.Medium,
                color = if (isCurrent) NeonPurple else TextPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(modifier = Modifier.height(2.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (track.youtubeId != null) {
                    Icon(
                        imageVector = Icons.Default.PlayCircle,
                        contentDescription = "Video available",
                        tint = NeonPink,
                        modifier = Modifier.size(12.dp)
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                }
                Text(
                    text = track.artist,
                    style = MaterialTheme.typography.bodyMedium,
                    color = TextSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }

        // Duration or Play Count
        if (track.duration > 0) {
            val mins = (track.duration / 60).toInt()
            val secs = (track.duration % 60).toInt()
            Text(
                text = "%d:%02d".format(mins, secs),
                style = MaterialTheme.typography.labelSmall,
                color = TextTertiary,
                modifier = Modifier.padding(horizontal = 8.dp)
            )
        }

        // Favorite Button
        IconButton(onClick = onToggleFavorite, modifier = Modifier.size(36.dp)) {
            Icon(
                imageVector = if (track.isFavorite) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                contentDescription = "Favorite",
                tint = if (track.isFavorite) NeonPink else TextTertiary,
                modifier = Modifier.size(18.dp)
            )
        }

        // More Menu
        Box {
            IconButton(onClick = { showMenu = true }, modifier = Modifier.size(36.dp)) {
                Icon(
                    imageVector = Icons.Default.MoreVert,
                    contentDescription = "More",
                    tint = TextSecondary,
                    modifier = Modifier.size(18.dp)
                )
            }
            DropdownMenu(
                expanded = showMenu,
                onDismissRequest = { showMenu = false }
            ) {
                DropdownMenuItem(
                    text = { Text("Play Video") },
                    onClick = {
                        showMenu = false
                        onPlayVideo()
                    },
                    leadingIcon = {
                        Icon(Icons.Default.OndemandVideo, contentDescription = null)
                    }
                )
                DropdownMenuItem(
                    text = { Text("Download") },
                    onClick = {
                        showMenu = false
                        DownloadHelper.downloadTrack(context, track, scope)
                    },
                    leadingIcon = {
                        Icon(Icons.Default.Download, contentDescription = null)
                    }
                )
                DropdownMenuItem(
                    text = { Text("Change Video Link") },
                    onClick = {
                        showMenu = false
                        onChangeVideo()
                    },
                    leadingIcon = {
                        Icon(Icons.Default.Link, contentDescription = null)
                    }
                )
                if (onAddToPlaylist != null) {
                    DropdownMenuItem(
                        text = { Text("Add to Playlist") },
                        onClick = {
                            showMenu = false
                            onAddToPlaylist()
                        },
                        leadingIcon = {
                            Icon(Icons.Default.PlaylistAdd, contentDescription = null)
                        }
                    )
                }
                if (onRemove != null) {
                    DropdownMenuItem(
                        text = { Text("Remove from Playlist", color = DangerRed) },
                        onClick = {
                            showMenu = false
                            onRemove()
                        },
                        leadingIcon = {
                            Icon(Icons.Default.Delete, contentDescription = null, tint = DangerRed)
                        }
                    )
                }
            }
        }
    }
}
