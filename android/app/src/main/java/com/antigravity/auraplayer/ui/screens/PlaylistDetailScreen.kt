package com.antigravity.auraplayer.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.antigravity.auraplayer.data.PlaylistRepository
import com.antigravity.auraplayer.model.MediaTrack
import com.antigravity.auraplayer.model.Playlist
import com.antigravity.auraplayer.service.DisplayMode
import com.antigravity.auraplayer.service.PlayContext
import com.antigravity.auraplayer.service.PlaybackManager
import com.antigravity.auraplayer.ui.components.GlassSearchField
import com.antigravity.auraplayer.ui.components.glass
import com.antigravity.auraplayer.ui.components.ChangeVideoLinkDialog
import com.antigravity.auraplayer.ui.components.MergePlaylistDialog
import com.antigravity.auraplayer.ui.components.TrackRow
import com.antigravity.auraplayer.ui.theme.*
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlaylistDetailScreen(
    playlistId: String,
    repository: PlaylistRepository,
    playbackManager: PlaybackManager,
    onBack: () -> Unit,
    onAddSongs: () -> Unit
) {
    val playlists by repository.playlists.collectAsState()
    val playlist = playlists.firstOrNull { it.id == playlistId }

    
    var trackToAdd by remember { mutableStateOf<com.antigravity.auraplayer.model.MediaTrack?>(null) }
    val playlistsState by repository.playlists.collectAsState()

    trackToAdd?.let { t ->
        com.antigravity.auraplayer.ui.components.PlaylistPickerDialog(
            playlists = playlistsState,
            onPick = { pl ->
                repository.addTrackToPlaylist(pl.id, t)
                trackToAdd = null
            },
            onCreate = { name ->
                val pl = repository.addPlaylist(name)
                repository.addTrackToPlaylist(pl.id, t)
                trackToAdd = null
            },
            onDismiss = { trackToAdd = null }
        )
    }

    val currentTrack by playbackManager.currentTrack.collectAsState()
    val isPlaying by playbackManager.isPlaying.collectAsState()

    var searchText by remember { mutableStateOf("") }
    var showRenameDialog by remember { mutableStateOf(false) }
    var renameText by remember { mutableStateOf("") }
    var showMergeDialog by remember { mutableStateOf(false) }
    var trackToChangeVideo by remember { mutableStateOf<MediaTrack?>(null) }
    var showHeaderMenu by remember { mutableStateOf(false) }

    val scope = rememberCoroutineScope()

    if (playlist == null) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text("Playlist not found", color = TextSecondary)
        }
        return
    }

    // Title, singer, album or movie; every word must match; spelling variants count ("Chinnadana" finds "Chinnadhana")
    val filteredTracks = remember(playlist.tracks, searchText) { repository.filter(playlist.tracks, searchText) }
    val context = PlayContext.FromPlaylist(playlist.id)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(playlist.name, maxLines = 1, fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { onAddSongs() }) {
                        Icon(Icons.Default.Add, contentDescription = "Add Track")
                    }
                    Box {
                        IconButton(onClick = { showHeaderMenu = true }) {
                            Icon(Icons.Default.MoreVert, contentDescription = "More")
                        }
                        DropdownMenu(
                            expanded = showHeaderMenu,
                            onDismissRequest = { showHeaderMenu = false }
                        ) {
                            DropdownMenuItem(
                                text = { Text("Rename Playlist") },
                                onClick = {
                                    showHeaderMenu = false
                                    renameText = playlist.name
                                    showRenameDialog = true
                                },
                                leadingIcon = { Icon(Icons.Default.Edit, contentDescription = null) }
                            )
                            DropdownMenuItem(
                                text = { Text("Merge with Another Playlist") },
                                onClick = {
                                    showHeaderMenu = false
                                    showMergeDialog = true
                                },
                                leadingIcon = { Icon(Icons.Default.MergeType, contentDescription = null) }
                            )
                            if (!playlist.isBuiltIn) {
                                DropdownMenuItem(
                                    text = { Text("Delete Playlist", color = DangerRed) },
                                    onClick = {
                                        showHeaderMenu = false
                                        repository.deletePlaylist(playlist.id)
                                        onBack()
                                    },
                                    leadingIcon = { Icon(Icons.Default.Delete, contentDescription = null, tint = DangerRed) }
                                )
                            }
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = androidx.compose.ui.graphics.Color.Transparent)
            )
        },
        containerColor = androidx.compose.ui.graphics.Color.Transparent
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp)
        ) {
            // Header Action Buttons
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Button(
                    onClick = {
                        playlist.tracks.firstOrNull()?.let {
                            playbackManager.playTrack(it, playlist.tracks, context)
                        }
                    },
                    enabled = playlist.tracks.isNotEmpty(),
                    modifier = Modifier.weight(1f).height(48.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = androidx.compose.ui.graphics.Color.White, contentColor = BackdropMid)
                ) {
                    Icon(Icons.Default.PlayArrow, contentDescription = null)
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("Play All")
                }

                Button(
                    onClick = {
                        val tracks = playlist.tracks
                        if (tracks.isNotEmpty()) {
                            val cur = playbackManager.currentTrack.value
                            val pool = if (tracks.size > 1 && cur != null) tracks.filter { it.id != cur.id } else tracks
                            val start = pool.random()
                            val shuffled = listOf(start) + tracks.filter { it.id != start.id }.shuffled()
                            playbackManager.setShuffle(true)
                            playbackManager.playTrack(start, shuffled, context)
                        }
                    },
                    enabled = playlist.tracks.isNotEmpty(),
                    modifier = Modifier.weight(1f).height(48.dp).glass(RoundedCornerShape(50)),
                    colors = ButtonDefaults.buttonColors(containerColor = androidx.compose.ui.graphics.Color.Transparent)
                ) {
                    Icon(Icons.Default.Shuffle, contentDescription = null, tint = TextPrimary)
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("Shuffle", color = TextPrimary)
                }
            }

            // Search in this playlist
            GlassSearchField(
                value = searchText,
                onValueChange = { searchText = it },
                placeholder = "Search in ${playlist.name.trim()}",
                modifier = Modifier.padding(bottom = 6.dp)
            )
            if (searchText.isNotBlank()) {
                Text(
                    if (filteredTracks.isEmpty()) "No songs match \"$searchText\"" else "${filteredTracks.size} of ${playlist.tracks.size} songs",
                    color = TextTertiary, style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier.padding(start = 6.dp, bottom = 6.dp)
                )
            }

            // Tracks
            if (filteredTracks.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                    contentAlignment = Alignment.Center
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(Icons.Default.MusicNote, contentDescription = null, tint = TextTertiary, modifier = Modifier.size(48.dp))
                        Spacer(modifier = Modifier.height(10.dp))
                        Text("No Tracks", style = MaterialTheme.typography.titleMedium, color = TextSecondary)
                        Spacer(modifier = Modifier.height(4.dp))
                        Text("Add songs using the + button above", style = MaterialTheme.typography.bodyMedium, color = TextTertiary)
                    }
                }
            } else {
                LazyColumn(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                    contentPadding = PaddingValues(bottom = 100.dp)
                ) {
                    items(filteredTracks, key = { it.id }) { track ->
                        TrackRow(
                            onAddToPlaylist = { trackToAdd = track },
                            track = track,
                            isCurrent = currentTrack?.id == track.id,
                            isPlaying = isPlaying && currentTrack?.id == track.id,
                            onPlay = { playbackManager.playTrack(track, playlist.tracks, context) },
                            onPlayVideo = {
                                playbackManager.setDisplayMode(DisplayMode.VIDEO)
                                playbackManager.playTrack(track, playlist.tracks, context)
                            },
                            onToggleFavorite = {
                                repository.toggleFavorite(track)
                            },
                            onChangeVideo = {
                                trackToChangeVideo = track
                            },
                            onRemove = {
                                repository.removeTrackFromPlaylist(playlist.id, track.id)
                            },
                            playlistId = playlist.id
                        )
                    }
                }
            }
        }
    }

    // Rename Dialog
    if (showRenameDialog) {
        AlertDialog(
            onDismissRequest = { showRenameDialog = false },
            title = { Text("Rename Playlist") },
            text = {
                OutlinedTextField(
                    value = renameText,
                    onValueChange = { renameText = it },
                    label = { Text("Playlist Name") },
                    singleLine = true
                )
            },
            confirmButton = {
                Button(onClick = {
                    if (renameText.isNotBlank()) {
                        repository.renamePlaylist(playlist.id, renameText.trim())
                    }
                    showRenameDialog = false
                }) {
                    Text("Rename")
                }
            },
            dismissButton = {
                TextButton(onClick = { showRenameDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }

    // Merge Dialog
    if (showMergeDialog) {
        MergePlaylistDialog(
            sourcePlaylist = playlist,
            allPlaylists = playlists,
            onDismiss = { showMergeDialog = false },
            onMergeIntoExisting = { targetId, skipDups, deleteSource ->
                repository.mergePlaylists(playlist.id, targetId, skipDups, deleteSource)
                showMergeDialog = false
                if (deleteSource) onBack()
            },
            onCreateNewMerged = { name, ids, skipDups, deleteSources ->
                val newId = repository.createMergedPlaylist(name, ids, skipDups, deleteSources)
                showMergeDialog = false
                if (deleteSources) onBack()
            }
        )
    }

    // Change Video Dialog
    trackToChangeVideo?.let { tr ->
        ChangeVideoLinkDialog(
            track = tr,
            onDismiss = { trackToChangeVideo = null },
            onConfirm = { newId ->
                repository.updateTrackVideo(tr.id, newId)
                trackToChangeVideo = null
            }
        )
    }
}
