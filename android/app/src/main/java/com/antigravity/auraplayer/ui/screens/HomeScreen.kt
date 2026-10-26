package com.antigravity.auraplayer.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.antigravity.auraplayer.data.PlaylistRepository
import com.antigravity.auraplayer.model.Playlist
import com.antigravity.auraplayer.service.PlaybackManager
import com.antigravity.auraplayer.ui.components.glass
import com.antigravity.auraplayer.ui.theme.*

/** Icon for a playlist (the Mac stores SF Symbol names like "heart.fill") */
fun playlistIcon(p: Playlist): ImageVector = when {
    p.iconName.contains("folder") -> Icons.Default.Folder
    p.iconName.contains("heart") || p.iconName == "favorite" || p.name.equals("Favorites", true) -> Icons.Default.Favorite
    p.iconName.contains("cup") -> Icons.Default.LocalCafe
    p.iconName.contains("video") || p.iconName.contains("film") -> Icons.Default.VideoLibrary
    else -> Icons.Default.QueueMusic
}

/** Home, like the iPhone app: your playlists, then your most played songs */
@Composable
fun HomeScreen(
    repository: PlaylistRepository,
    playbackManager: PlaybackManager,
    onOpenPlaylist: (String) -> Unit,
    onSeeAllPlaylists: () -> Unit,
    onOpenDiscover: () -> Unit
) {
    val playlists by repository.playlists.collectAsState()
    val mostPlayed = remember(playlists) { repository.mostPlayedTracks.take(25) }
    val current by playbackManager.currentTrack.collectAsState()
    val isPlaying by playbackManager.isPlaying.collectAsState()
    val dialogs = rememberSongListDialogs()

    LazyColumn(Modifier.fillMaxSize().statusBarsPadding(), contentPadding = PaddingValues(bottom = 130.dp)) {
        item {
            Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 16.dp, top = 18.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("Aura Player", color = TextPrimary, fontWeight = FontWeight.ExtraBold, fontSize = 30.sp)
                    Text("Listen without limits", color = TextSecondary, fontSize = 15.sp)
                }
                IconButton(onClick = onOpenDiscover, modifier = Modifier.size(48.dp).glass(RoundedCornerShape(50), alpha = 0.22f)) {
                    Icon(Icons.Default.AutoAwesome, contentDescription = "Discover", tint = Color.White)
                }
            }
        }
        item {
            Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Your Playlists", color = TextPrimary, fontWeight = FontWeight.Bold, fontSize = 22.sp, modifier = Modifier.weight(1f))
                Text("See All", color = NeonPurple, fontWeight = FontWeight.SemiBold, modifier = Modifier.clickable { onSeeAllPlaylists() })
            }
        }
        // Two-column grid of the first playlists
        val shown = playlists.take(8).chunked(2)
        shown.forEach { pair ->
            item {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 5.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    pair.forEach { pl ->
                        Row(
                            Modifier.weight(1f).glass(RoundedCornerShape(16.dp)).clickable { onOpenPlaylist(pl.id) }.padding(10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Box(Modifier.size(42.dp).background(Color.White.copy(alpha = 0.18f), RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) {
                                Icon(playlistIcon(pl), null, tint = Color.White)
                            }
                            Spacer(Modifier.width(10.dp))
                            Column {
                                Text(pl.name.trim(), color = TextPrimary, fontWeight = FontWeight.SemiBold, fontSize = 14.sp,
                                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text("%,d tracks".format(pl.tracks.size), color = TextSecondary, fontSize = 12.sp)
                            }
                        }
                    }
                    if (pair.size == 1) Spacer(Modifier.weight(1f))
                }
            }
        }
        if (mostPlayed.isNotEmpty()) {
            item {
                Text("Most Played", color = TextPrimary, fontWeight = FontWeight.Bold, fontSize = 22.sp,
                    modifier = Modifier.padding(start = 20.dp, top = 22.dp, bottom = 6.dp))
            }
            item { Spacer(Modifier.height(0.dp)) }
        }
        songRowsPadded(mostPlayed, repository, playbackManager, current?.id, isPlaying, dialogs)
    }
    SongListDialogsHost(dialogs, repository)
}

private fun androidx.compose.foundation.lazy.LazyListScope.songRowsPadded(
    tracks: List<com.antigravity.auraplayer.model.MediaTrack>,
    repository: PlaylistRepository,
    playbackManager: PlaybackManager,
    currentId: String?,
    isPlaying: Boolean,
    dialogs: SongListDialogs
) {
    item { Spacer(Modifier.height(0.dp)) }
    songRows(tracks, repository, playbackManager, currentId, isPlaying, dialogs,
        subtitle = { t -> "${t.artist} • ${t.totalPlays} plays" })
}
