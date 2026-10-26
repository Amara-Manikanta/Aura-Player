package com.antigravity.auraplayer.ui.components

import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.antigravity.auraplayer.data.PlaylistRepository
import com.antigravity.auraplayer.service.PlaybackManager
import com.antigravity.auraplayer.ui.theme.*

/**
 * "•••" options for the song that's playing now, like the Mac and iPhone apps:
 * start/end time, right/wrong video, change/copy/open video link, favourites and playlists.
 */
@Composable
fun CurrentSongMenu(
    playbackManager: PlaybackManager,
    onChangeVideo: () -> Unit,
    onAddToPlaylist: () -> Unit,
    tint: Color = TextSecondary
) {
    val context = LocalContext.current
    val repository = remember { PlaylistRepository.getInstance(context) }
    val track by playbackManager.currentTrack.collectAsState()
    val position by playbackManager.currentPosition.collectAsState()
    var open by remember { mutableStateOf(false) }
    var showTrim by remember { mutableStateOf(false) }
    val t = track ?: return

    IconButton(onClick = { open = true }) {
        Icon(Icons.Default.MoreHoriz, contentDescription = "Song options", tint = tint, modifier = Modifier.size(24.dp))
    }
    DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
        Text(t.trimLabel?.let { "  Plays $it" } ?: "  Start & End Time", color = TextTertiary,
            style = MaterialTheme.typography.labelSmall)
        DropdownMenuItem(text = { Text("Start From Current Position") }, leadingIcon = { Icon(Icons.Default.FirstPage, null) },
            onClick = {
                open = false
                val now = position / 1000.0
                // keep the end only if it's still after the new start
                playbackManager.setTrim(now, t.endTime?.takeIf { it > now + 1 })
            })
        DropdownMenuItem(text = { Text("End at Current Position") }, leadingIcon = { Icon(Icons.Default.LastPage, null) },
            onClick = {
                open = false
                val now = position / 1000.0
                playbackManager.setTrim(t.startTime?.takeIf { it < now - 1 }, now)
            })
        DropdownMenuItem(text = { Text("Set Start & End Time…") }, leadingIcon = { Icon(Icons.Default.ContentCut, null) },
            onClick = { open = false; showTrim = true })
        if (t.trimLabel != null) DropdownMenuItem(text = { Text("Clear Start & End Time") },
            leadingIcon = { Icon(Icons.Default.Cancel, null) }, onClick = { open = false; playbackManager.setTrim(null, null) })
        HorizontalDivider()
        DropdownMenuItem(text = { Text("Right Video (always play it)") }, leadingIcon = { Icon(Icons.Default.ThumbUp, null) },
            onClick = { open = false; playbackManager.confirmCurrentVideo(); Toast.makeText(context, "This video will always play for this song", Toast.LENGTH_SHORT).show() })
        DropdownMenuItem(text = { Text("Wrong Video (try the next best)") }, leadingIcon = { Icon(Icons.Default.ThumbDown, null) },
            onClick = { open = false; playbackManager.rejectCurrentVideo() })
        DropdownMenuItem(text = { Text("Change Video Link…") }, leadingIcon = { Icon(Icons.Default.Link, null) },
            onClick = { open = false; onChangeVideo() })
        t.youtubeId?.let { id ->
            val url = "https://www.youtube.com/watch?v=$id"
            DropdownMenuItem(text = { Text("Open in YouTube") }, leadingIcon = { Icon(Icons.Default.OpenInNew, null) },
                onClick = { open = false; context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) })
            DropdownMenuItem(text = { Text("Copy YouTube Link") }, leadingIcon = { Icon(Icons.Default.ContentCopy, null) },
                onClick = { open = false; copyToClipboard(context, url) })
        }
        HorizontalDivider()
        val fav = repository.isFavorite(t)
        DropdownMenuItem(text = { Text(if (fav) "Remove from Favorites" else "Add to Favorites") },
            leadingIcon = { Icon(if (fav) Icons.Default.HeartBroken else Icons.Default.FavoriteBorder, null) },
            onClick = { open = false; repository.toggleFavorite(t) })
        DropdownMenuItem(text = { Text("Add to Playlist…") }, leadingIcon = { Icon(Icons.Default.PlaylistAdd, null) },
            onClick = { open = false; onAddToPlaylist() })
    }
    if (showTrim) {
        TrimDialog(t, onSave = { s, e -> playbackManager.setTrim(s, e); showTrim = false }, onDismiss = { showTrim = false })
    }
}
