package com.antigravity.auraplayer.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.antigravity.auraplayer.data.PlaylistRepository
import com.antigravity.auraplayer.service.PlaybackManager
import com.antigravity.auraplayer.ui.components.TrackRow
import com.antigravity.auraplayer.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MostPlayedScreen(
    repository: PlaylistRepository,
    playbackManager: PlaybackManager
) {
    val mostPlayed = remember(repository.playlists.collectAsState().value) {
        repository.mostPlayedTracks
    }
    
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

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.LocalFireDepartment, contentDescription = null, tint = AccentCyan)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("Most Played", fontWeight = FontWeight.Bold)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = BackgroundDark)
            )
        },
        containerColor = BackgroundDark
    ) { padding ->
        if (mostPlayed.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(Icons.Default.LocalFireDepartment, contentDescription = null, tint = TextTertiary, modifier = Modifier.size(48.dp))
                    Spacer(modifier = Modifier.height(10.dp))
                    Text("No Play History Yet", style = MaterialTheme.typography.titleMedium, color = TextSecondary)
                    Spacer(modifier = Modifier.height(4.dp))
                    Text("Play your favorite tracks to see your top songs here!", style = MaterialTheme.typography.bodyMedium, color = TextTertiary)
                }
            }
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                contentPadding = PaddingValues(bottom = 120.dp, top = 8.dp)
            ) {
                itemsIndexed(mostPlayed, key = { _, tr -> tr.id }) { index, track ->
                    TrackRow(
                            onAddToPlaylist = { trackToAdd = track },
                        track = track,
                        isCurrent = currentTrack?.id == track.id,
                        isPlaying = isPlaying && currentTrack?.id == track.id,
                        onPlay = {
                            playbackManager.playTrack(track, mostPlayed)
                            repository.recordPlay(track)
                        },
                            onPlayVideo = { 
                                playbackManager.playTrack(track)
                                if (playbackManager.isAudioOnly.value) playbackManager.toggleAudioOnly()
                            },
                        onToggleFavorite = { repository.toggleFavorite(track) },
                        onChangeVideo = {}
                    )
                }
            }
        }
    }
}
