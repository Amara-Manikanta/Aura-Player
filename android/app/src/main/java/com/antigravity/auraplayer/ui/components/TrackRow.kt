package com.antigravity.auraplayer.ui.components

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DriveFileMove
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.antigravity.auraplayer.data.PlaylistRepository
import com.antigravity.auraplayer.model.MediaTrack
import com.antigravity.auraplayer.ui.theme.*
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
    onAddToPlaylist: (() -> Unit)? = null,
    /** The playlist this row is shown in: enables Move to / Copy to another playlist */
    playlistId: String? = null,
    subtitle: String? = null
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val repository = remember { PlaylistRepository.getInstance(context) }
    var showMenu by remember { mutableStateOf(false) }
    var showTrim by remember { mutableStateOf(false) }
    var transferMove by remember { mutableStateOf<Boolean?>(null) }   // true = move, false = copy
    val isFavorite = repository.isFavorite(track)

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(if (isCurrent) Color.White.copy(alpha = 0.12f) else Color.Transparent)
            .clickable { onPlay() }
            .padding(horizontal = 12.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(contentAlignment = Alignment.Center) {
            TrackArtwork(track, 50.dp, 10.dp)
            if (isCurrent && isPlaying) {
                Box(Modifier.size(50.dp).clip(RoundedCornerShape(10.dp)).background(Color.Black.copy(alpha = 0.45f)),
                    contentAlignment = Alignment.Center) {
                    Icon(Icons.Default.GraphicEq, contentDescription = null, tint = NeonPurple, modifier = Modifier.size(22.dp))
                }
            }
        }

        Spacer(modifier = Modifier.width(12.dp))

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = track.title,
                fontSize = 15.sp,
                fontWeight = if (isCurrent) FontWeight.Bold else FontWeight.SemiBold,
                color = if (isCurrent) NeonPurple else TextPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Spacer(modifier = Modifier.height(2.dp))
            val movie = track.movieName
            Text(
                text = subtitle ?: listOfNotNull(track.artist, movie?.takeIf { track.isIndianRelease }).joinToString(" • "),
                fontSize = 13.sp,
                color = TextSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            track.trimLabel?.let {
                Text("✂ $it", fontSize = 11.sp, color = NeonPurple)
            }
        }

        if (track.duration > 0) {
            Text(
                text = track.formattedDuration,
                style = MaterialTheme.typography.labelSmall,
                color = TextTertiary,
                modifier = Modifier.padding(horizontal = 6.dp)
            )
        }

        Box {
            IconButton(onClick = { showMenu = true }, modifier = Modifier.size(36.dp)) {
                Icon(Icons.Default.MoreHoriz, contentDescription = "More", tint = TextSecondary, modifier = Modifier.size(20.dp))
            }
            DropdownMenu(expanded = showMenu, onDismissRequest = { showMenu = false }) {
                DropdownMenuItem(
                    text = { Text("Play Video") },
                    onClick = { showMenu = false; onPlayVideo() },
                    leadingIcon = { Icon(Icons.Default.OndemandVideo, contentDescription = null) }
                )
                if (onAddToPlaylist != null) DropdownMenuItem(
                    text = { Text("Add to Playlist") },
                    onClick = { showMenu = false; onAddToPlaylist() },
                    leadingIcon = { Icon(Icons.Default.PlaylistAdd, contentDescription = null) }
                )
                DropdownMenuItem(
                    text = { Text(if (isFavorite) "Remove from Favorites" else "Add to Favorites") },
                    onClick = { showMenu = false; onToggleFavorite() },
                    leadingIcon = { Icon(if (isFavorite) Icons.Default.HeartBroken else Icons.Default.FavoriteBorder, contentDescription = null) }
                )
                HorizontalDivider()
                DropdownMenuItem(
                    text = { Text("Change Video Link") },
                    onClick = { showMenu = false; onChangeVideo() },
                    leadingIcon = { Icon(Icons.Default.Link, contentDescription = null) }
                )
                track.youtubeId?.let { id ->
                    DropdownMenuItem(
                        text = { Text("Copy YouTube Link") },
                        onClick = { showMenu = false; copyToClipboard(context, "https://www.youtube.com/watch?v=$id") },
                        leadingIcon = { Icon(Icons.Default.ContentCopy, contentDescription = null) }
                    )
                }
                DropdownMenuItem(
                    text = { Text("Start & End Time…") },
                    onClick = { showMenu = false; showTrim = true },
                    leadingIcon = { Icon(Icons.Default.ContentCut, contentDescription = null) }
                )
                DropdownMenuItem(
                    text = { Text("Download") },
                    onClick = { showMenu = false; DownloadHelper.downloadTrack(context, track, scope) },
                    leadingIcon = { Icon(Icons.Default.Download, contentDescription = null) }
                )
                if (playlistId != null) {
                    HorizontalDivider()
                    DropdownMenuItem(
                        text = { Text("Move to Playlist…") },
                        onClick = { showMenu = false; transferMove = true },
                        leadingIcon = { Icon(Icons.AutoMirrored.Filled.DriveFileMove, contentDescription = null) }
                    )
                    DropdownMenuItem(
                        text = { Text("Copy to Playlist…") },
                        onClick = { showMenu = false; transferMove = false },
                        leadingIcon = { Icon(Icons.Default.LibraryAdd, contentDescription = null) }
                    )
                }
                if (onRemove != null) {
                    HorizontalDivider()
                    DropdownMenuItem(
                        text = { Text("Remove from Playlist", color = DangerRed) },
                        onClick = { showMenu = false; onRemove() },
                        leadingIcon = { Icon(Icons.Default.Delete, contentDescription = null, tint = DangerRed) }
                    )
                }
            }
        }
    }

    if (showTrim) {
        TrimDialog(track, onSave = { s, e ->
            repository.setTrimTimes(track, s, e)
            showTrim = false
        }, onDismiss = { showTrim = false })
    }

    val move = transferMove
    if (move != null && playlistId != null) {
        val others = repository.playlists.collectAsState().value.filter { it.id != playlistId }
        AlertDialog(
            onDismissRequest = { transferMove = null },
            title = { Text(if (move) "Move to Playlist" else "Copy to Playlist") },
            text = {
                LazyColumn(Modifier.heightIn(max = 360.dp)) {
                    items(others, key = { it.id }) { pl ->
                        Row(
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).clickable {
                                val name = pl.name.trim()
                                val result = if (move) repository.moveTrack(track.id, playlistId, pl.id) else repository.copyTrack(track, pl.id)
                                val msg = when (result) {
                                    PlaylistRepository.TransferResult.MOVED -> "Moved to $name"
                                    PlaylistRepository.TransferResult.COPIED -> "Copied to $name"
                                    PlaylistRepository.TransferResult.ALREADY_THERE ->
                                        if (move) "Already in $name, removed from here" else "Already in $name"
                                    PlaylistRepository.TransferResult.NOT_FOUND -> "Couldn't find that playlist"
                                }
                                Toast.makeText(context, msg, Toast.LENGTH_SHORT).show()
                                transferMove = null
                            }.padding(vertical = 11.dp, horizontal = 6.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(if (pl.isBuiltIn) Icons.Default.Favorite else Icons.Default.QueueMusic, null, tint = NeonPurple)
                            Spacer(Modifier.width(12.dp))
                            Text(pl.name.trim(), modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text("${pl.tracks.size}", color = TextTertiary, fontSize = 12.sp)
                        }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { transferMove = null }) { Text("Cancel") } }
        )
    }
}
