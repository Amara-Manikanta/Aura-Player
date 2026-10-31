package com.antigravity.auraplayer.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import com.antigravity.auraplayer.ui.components.ImportPlaylistDialog
import com.antigravity.auraplayer.ui.components.glass
import com.antigravity.auraplayer.ui.theme.*

/** Library, like the iPhone app: Favorites, Most Played, Recently Added, New Releases, Artists, Settings, playlists */
@Composable
fun LibraryScreen(
    repository: PlaylistRepository,
    onSelectPlaylist: (String) -> Unit,
    onMostPlayed: () -> Unit,
    onRecentlyAdded: () -> Unit,
    onNewReleases: () -> Unit,
    onArtists: () -> Unit,
    onSettings: () -> Unit
) {
    val playlists by repository.playlists.collectAsState()
    val counts = remember(playlists) {
        Triple(repository.mostPlayedTracks.size, repository.allUniqueTracks.size, repository.allArtists.size)
    }
    var showNewPlaylistDialog by remember { mutableStateOf(false) }
    var showImportDialog by remember { mutableStateOf(false) }
    var newPlaylistName by remember { mutableStateOf("") }
    val favorites = playlists.firstOrNull { it.id == repository.favoritesPlaylistId }

    LazyColumn(
        modifier = Modifier.fillMaxSize().statusBarsPadding().padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        contentPadding = PaddingValues(bottom = 130.dp, top = 12.dp)
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Library", color = TextPrimary, fontWeight = FontWeight.ExtraBold, fontSize = 28.sp, modifier = Modifier.weight(1f))
                IconButton(onClick = onSettings, modifier = Modifier.size(44.dp).glass(RoundedCornerShape(50))) {
                    Icon(Icons.Default.Settings, contentDescription = "Settings", tint = TextPrimary)
                }
            }
        }
        favorites?.let { fav ->
            item { LibraryLink(Icons.Default.Favorite, Color(0xFFFF8FB1), "Favorites", "${fav.tracks.size} tracks") { onSelectPlaylist(fav.id) } }
        }
        item { LibraryLink(Icons.Default.LocalFireDepartment, Color(0xFFFFB86B), "Most Played", "%,d tracks".format(counts.first), onMostPlayed) }
        item { LibraryLink(Icons.Default.History, Color(0xFF6FE3D8), "Recently Added", "%,d tracks".format(counts.second), onRecentlyAdded) }
        item { LibraryLink(Icons.Default.NewReleases, Color(0xFFE38CF2), "New Releases", "Latest YouTube music drops", onNewReleases) }
        item { LibraryLink(Icons.Default.Mic, Color(0xFF8FB8FF), "Singers & Artists", "%,d artists".format(counts.third), onArtists) }
        item { LibraryLink(Icons.Default.CloudDownload, Color(0xFF2BC5B4), "Import Playlist", "YouTube, Spotify, JioSaavn, Gaana...") { showImportDialog = true } }

        item {
            Row(Modifier.padding(top = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Playlists", color = TextPrimary, fontWeight = FontWeight.Bold, fontSize = 22.sp, modifier = Modifier.weight(1f))
                IconButton(
                    onClick = { showImportDialog = true },
                    modifier = Modifier.size(38.dp).glass(RoundedCornerShape(50))
                ) {
                    Icon(Icons.Default.CloudDownload, contentDescription = "Import Playlist", tint = TextPrimary)
                }
                Spacer(Modifier.width(8.dp))
                IconButton(
                    onClick = { showNewPlaylistDialog = true },
                    modifier = Modifier.size(38.dp).background(Color.White, RoundedCornerShape(50))
                ) {
                    Icon(Icons.Default.Add, contentDescription = "New Playlist", tint = BackdropMid)
                }
            }
        }
        items(playlists.filter { it.id != favorites?.id }, key = { it.id }) { pl ->
            PlaylistCard(playlist = pl, onClick = { onSelectPlaylist(pl.id) })
        }
    }

    if (showNewPlaylistDialog) {
        AlertDialog(
            onDismissRequest = { showNewPlaylistDialog = false },
            title = { Text("New Playlist") },
            text = {
                OutlinedTextField(
                    value = newPlaylistName,
                    onValueChange = { newPlaylistName = it },
                    label = { Text("Playlist Name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                Button(onClick = {
                    if (newPlaylistName.isNotBlank()) {
                        val created = repository.addPlaylist(newPlaylistName.trim())
                        showNewPlaylistDialog = false
                        newPlaylistName = ""
                        onSelectPlaylist(created.id)
                    }
                }) { Text("Create") }
            },
            dismissButton = { TextButton(onClick = { showNewPlaylistDialog = false }) { Text("Cancel") } }
        )
    }

    if (showImportDialog) {
        ImportPlaylistDialog(
            repository = repository,
            onDismiss = { showImportDialog = false },
            onImportSuccess = { newId, count ->
                if (newId != null) {
                    onSelectPlaylist(newId)
                }
            }
        )
    }
}

@Composable
private fun LibraryLink(icon: ImageVector, tint: Color, title: String, subtitle: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().glass(RoundedCornerShape(16.dp)).clickable { onClick() }.padding(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.size(44.dp).background(tint.copy(alpha = 0.25f), RoundedCornerShape(50)), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = tint)
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(title, color = TextPrimary, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
            Text(subtitle, color = TextSecondary, fontSize = 13.sp)
        }
        Icon(Icons.Default.ChevronRight, null, tint = TextTertiary)
    }
}

@Composable
fun PlaylistCard(playlist: Playlist, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().glass(RoundedCornerShape(16.dp)).clickable { onClick() }.padding(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.size(48.dp).background(Color.White.copy(alpha = 0.18f), RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) {
            Icon(playlistIcon(playlist), null, tint = Color.White, modifier = Modifier.size(24.dp))
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(playlist.name.trim(), color = TextPrimary, fontWeight = FontWeight.SemiBold, fontSize = 16.sp,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("%,d tracks".format(playlist.tracks.size), color = TextSecondary, fontSize = 13.sp)
        }
        Icon(Icons.Default.ChevronRight, null, tint = TextTertiary)
    }
}
