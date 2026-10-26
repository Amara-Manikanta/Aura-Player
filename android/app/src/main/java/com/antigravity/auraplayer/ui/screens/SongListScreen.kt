package com.antigravity.auraplayer.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.antigravity.auraplayer.data.PlaylistRepository
import com.antigravity.auraplayer.model.MediaTrack
import com.antigravity.auraplayer.service.DisplayMode
import com.antigravity.auraplayer.service.PlayContext
import com.antigravity.auraplayer.service.PlaybackManager
import com.antigravity.auraplayer.ui.components.*
import com.antigravity.auraplayer.ui.theme.*

/** The dialogs a list of songs needs: add to playlist, change video link */
class SongListDialogs {
    var trackToAdd by mutableStateOf<MediaTrack?>(null)
    var trackToChangeVideo by mutableStateOf<MediaTrack?>(null)
}

@Composable
fun rememberSongListDialogs() = remember { SongListDialogs() }

@Composable
fun SongListDialogsHost(dialogs: SongListDialogs, repository: PlaylistRepository) {
    val playlists by repository.playlists.collectAsState()
    dialogs.trackToAdd?.let { t ->
        PlaylistPickerDialog(
            playlists = playlists,
            onPick = { pl -> repository.addTrackToPlaylist(pl.id, t); dialogs.trackToAdd = null },
            onCreate = { name -> repository.addTrackToPlaylist(repository.addPlaylist(name).id, t); dialogs.trackToAdd = null },
            onDismiss = { dialogs.trackToAdd = null }
        )
    }
    dialogs.trackToChangeVideo?.let { t ->
        ChangeVideoLinkDialog(
            track = t,
            onDismiss = { dialogs.trackToChangeVideo = null },
            onConfirm = { id -> repository.setVideo(t.id, id); dialogs.trackToChangeVideo = null }
        )
    }
}

/** Rows for a list of songs, playing within that list */
fun LazyListScope.songRows(
    tracks: List<MediaTrack>,
    repository: PlaylistRepository,
    playbackManager: PlaybackManager,
    currentId: String?,
    isPlaying: Boolean,
    dialogs: SongListDialogs,
    playContext: PlayContext = PlayContext.None,
    subtitle: ((MediaTrack) -> String?)? = null
) {
    items(tracks, key = { it.id }) { track ->
        TrackRow(
            track = track,
            isCurrent = currentId == track.id,
            isPlaying = isPlaying && currentId == track.id,
            onPlay = { playbackManager.playTrack(track, tracks, playContext) },
            onPlayVideo = {
                playbackManager.setDisplayMode(DisplayMode.VIDEO)
                playbackManager.playTrack(track, tracks, playContext)
            },
            onToggleFavorite = { repository.toggleFavorite(track) },
            onChangeVideo = { dialogs.trackToChangeVideo = track },
            onAddToPlaylist = { dialogs.trackToAdd = track },
            subtitle = subtitle?.invoke(track)
        )
    }
}

/** A titled list of songs: Most Played, Recently Added */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SongListScreen(
    title: String,
    tracks: List<MediaTrack>,
    repository: PlaylistRepository,
    playbackManager: PlaybackManager,
    onBack: () -> Unit,
    subtitle: ((MediaTrack) -> String?)? = null
) {
    val current by playbackManager.currentTrack.collectAsState()
    val isPlaying by playbackManager.isPlaying.collectAsState()
    val dialogs = rememberSongListDialogs()
    var query by remember { mutableStateOf("") }
    val shown = remember(tracks, query) { repository.filter(tracks, query) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title, fontWeight = FontWeight.Bold) },
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
                Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Button(
                        onClick = { tracks.firstOrNull()?.let { playbackManager.playTrack(it, tracks, PlayContext.None) } },
                        enabled = tracks.isNotEmpty(),
                        modifier = Modifier.weight(1f).height(46.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = BackdropMid)
                    ) { Icon(Icons.Default.PlayArrow, null); Spacer(Modifier.width(6.dp)); Text("Play All") }
                    Button(
                        onClick = { val s = tracks.shuffled(); s.firstOrNull()?.let { playbackManager.playTrack(it, s, PlayContext.None) } },
                        enabled = tracks.isNotEmpty(),
                        modifier = Modifier.weight(1f).height(46.dp).glass(RoundedCornerShape(50)),
                        colors = ButtonDefaults.buttonColors(containerColor = Color.Transparent)
                    ) { Icon(Icons.Default.Shuffle, null, tint = TextPrimary); Spacer(Modifier.width(6.dp)); Text("Shuffle", color = TextPrimary) }
                }
                GlassSearchField(query, { query = it }, "Search ${tracks.size} songs", Modifier.padding(bottom = 6.dp))
            }
            songRows(shown, repository, playbackManager, current?.id, isPlaying, dialogs, subtitle = subtitle)
        }
    }
    SongListDialogsHost(dialogs, repository)
}
