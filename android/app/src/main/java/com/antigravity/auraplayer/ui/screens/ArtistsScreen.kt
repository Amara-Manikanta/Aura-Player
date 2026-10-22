package com.antigravity.auraplayer.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.antigravity.auraplayer.data.PlaylistRepository
import com.antigravity.auraplayer.model.ArtistGroup
import com.antigravity.auraplayer.service.PlaybackManager
import com.antigravity.auraplayer.ui.components.TrackRow
import com.antigravity.auraplayer.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ArtistsScreen(
    repository: PlaylistRepository,
    playbackManager: PlaybackManager
) {
    val artists = remember(repository.playlists.collectAsState().value) {
        repository.allArtists
    }
    var selectedArtist by remember { mutableStateOf<ArtistGroup?>(null) }
    
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

    if (selectedArtist != null) {
        val artist = selectedArtist!!
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(artist.name, fontWeight = FontWeight.Bold) },
                    navigationIcon = {
                        IconButton(onClick = { selectedArtist = null }) {
                            Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = BackgroundDark)
                )
            },
            containerColor = BackgroundDark
        ) { padding ->
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(horizontal = 16.dp)
            ) {
                // Play all artist songs
                Button(
                    onClick = {
                        artist.tracks.firstOrNull()?.let {
                            playbackManager.playTrack(it, artist.tracks)
                        }
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 12.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = NeonPurple)
                ) {
                    Icon(Icons.Default.PlayArrow, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Play All Songs (${artist.trackCount})")
                }

                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    contentPadding = PaddingValues(bottom = 120.dp)
                ) {
                    items(artist.tracks, key = { it.id }) { track ->
                        TrackRow(
                            onAddToPlaylist = { trackToAdd = track },
                            track = track,
                            isCurrent = currentTrack?.id == track.id,
                            isPlaying = isPlaying && currentTrack?.id == track.id,
                            onPlay = {
                                playbackManager.playTrack(track, artist.tracks)
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
    } else {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.Mic, contentDescription = null, tint = NeonIndigo)
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("Singers & Artists", fontWeight = FontWeight.Bold)
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = BackgroundDark)
                )
            },
            containerColor = BackgroundDark
        ) { padding ->
            if (artists.isEmpty()) {
                Box(modifier = Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    Text("No Artists Found", color = TextSecondary)
                }
            } else {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding)
                        .padding(horizontal = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                    contentPadding = PaddingValues(bottom = 120.dp, top = 8.dp)
                ) {
                    items(artists, key = { it.name }) { artist ->
                        Surface(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(14.dp))
                                .clickable { selectedArtist = artist },
                            color = SurfaceCard.copy(alpha = 0.6f),
                            shape = RoundedCornerShape(14.dp)
                        ) {
                            Row(
                                modifier = Modifier.padding(14.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(50.dp)
                                        .clip(CircleShape)
                                        .background(NeonIndigo.copy(alpha = 0.2f)),
                                    contentAlignment = Alignment.Center
                                ) {
                                    if (artist.sampleArtworkURL != null) {
                                        AsyncImage(
                                            model = artist.sampleArtworkURL,
                                            contentDescription = null,
                                            modifier = Modifier.fillMaxSize(),
                                            contentScale = ContentScale.Crop
                                        )
                                    } else {
                                        Icon(Icons.Default.Person, contentDescription = null, tint = NeonIndigo)
                                    }
                                }

                                Spacer(modifier = Modifier.width(14.dp))

                                Column(modifier = Modifier.weight(1f)) {
                                    Text(artist.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = TextPrimary)
                                    Text("${artist.trackCount} songs", style = MaterialTheme.typography.bodyMedium, color = TextSecondary)
                                }

                                Icon(Icons.Default.ChevronRight, contentDescription = null, tint = TextTertiary)
                            }
                        }
                    }
                }
            }
        }
    }
}
