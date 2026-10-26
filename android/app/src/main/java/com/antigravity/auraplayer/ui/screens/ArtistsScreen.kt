package com.antigravity.auraplayer.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.antigravity.auraplayer.data.PlaylistRepository
import com.antigravity.auraplayer.model.ArtistGroup
import com.antigravity.auraplayer.service.PlayContext
import com.antigravity.auraplayer.service.PlaybackManager
import com.antigravity.auraplayer.ui.components.ArtistAvatar
import com.antigravity.auraplayer.ui.components.GlassSearchField
import com.antigravity.auraplayer.ui.theme.*

/** Every singer separately (a duet under both), with real photos, most songs first (same as the Mac app) */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ArtistsScreen(
    repository: PlaylistRepository,
    playbackManager: PlaybackManager,
    onBack: (() -> Unit)? = null
) {
    val playlists by repository.playlists.collectAsState()
    val artists = remember(playlists) { repository.allArtists }
    var selected by remember { mutableStateOf<ArtistGroup?>(null) }
    var query by remember { mutableStateOf("") }

    val artist = selected
    if (artist != null) {
        BackHandler { selected = null }
        ArtistDetail(artist, repository, playbackManager, onBack = { selected = null })
        return
    }

    val shown = remember(artists, query) {
        if (query.isBlank()) artists else artists.filter { it.name.contains(query.trim(), ignoreCase = true) }
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Singers & Artists", fontWeight = FontWeight.Bold) },
                navigationIcon = { if (onBack != null) IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent)
            )
        },
        containerColor = Color.Transparent
    ) { padding ->
        LazyVerticalGrid(
            columns = GridCells.Fixed(3),
            modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = 12.dp),
            contentPadding = PaddingValues(bottom = 120.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            item(span = { GridItemSpan(3) }) {
                GlassSearchField(query, { query = it }, "Search ${artists.size} artists")
            }
            items(shown, key = { it.name }) { a ->
                Column(
                    Modifier.fillMaxWidth().clickable { selected = a },
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    ArtistAvatar(a.name, 92.dp, a.sampleArtworkURL)
                    Spacer(Modifier.height(8.dp))
                    Text(a.name, color = TextPrimary, fontWeight = FontWeight.SemiBold, fontSize = 13.sp,
                        maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
                    Text("${a.trackCount} songs", color = TextTertiary, fontSize = 11.sp)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ArtistDetail(
    artist: ArtistGroup,
    repository: PlaylistRepository,
    playbackManager: PlaybackManager,
    onBack: () -> Unit
) {
    val current by playbackManager.currentTrack.collectAsState()
    val isPlaying by playbackManager.isPlaying.collectAsState()
    val dialogs = rememberSongListDialogs()
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(artist.name, fontWeight = FontWeight.Bold) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent)
            )
        },
        containerColor = Color.Transparent
    ) { padding ->
        LazyColumn(
            Modifier.fillMaxSize().padding(padding).padding(horizontal = 12.dp),
            contentPadding = PaddingValues(bottom = 120.dp)
        ) {
            item {
                Column(Modifier.fillMaxWidth().padding(vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    ArtistAvatar(artist.name, 140.dp, artist.sampleArtworkURL)
                    Spacer(Modifier.height(12.dp))
                    Text(artist.name, color = TextPrimary, fontWeight = FontWeight.Bold, fontSize = 24.sp)
                    Text("${artist.trackCount} songs • ${artist.totalPlayCount} plays", color = TextSecondary, fontSize = 14.sp)
                    Spacer(Modifier.height(14.dp))
                    Button(
                        onClick = { artist.tracks.firstOrNull()?.let { playbackManager.playTrack(it, artist.tracks, PlayContext.None) } },
                        modifier = Modifier.fillMaxWidth().height(48.dp),
                        shape = RoundedCornerShape(50),
                        colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = BackdropMid)
                    ) { Icon(Icons.Default.PlayArrow, null); Spacer(Modifier.width(6.dp)); Text("Play All") }
                }
            }
            songRows(artist.tracks, repository, playbackManager, current?.id, isPlaying, dialogs)
        }
    }
    SongListDialogsHost(dialogs, repository)
}
