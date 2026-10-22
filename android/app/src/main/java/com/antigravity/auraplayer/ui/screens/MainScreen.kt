package com.antigravity.auraplayer.ui.screens

import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.antigravity.auraplayer.data.PlaylistRepository
import com.antigravity.auraplayer.model.MediaTrack
import com.antigravity.auraplayer.service.PlaybackManager
import com.antigravity.auraplayer.ui.components.ChangeVideoLinkDialog
import com.antigravity.auraplayer.ui.components.FullPlayerSheet
import com.antigravity.auraplayer.ui.components.MiniPlayer
import com.antigravity.auraplayer.ui.theme.*

enum class AppTab(val title: String) {
    LIBRARY("Library"),
    SEARCH("Search"),
    MOST_PLAYED("Most Played"),
    ARTISTS("Artists")
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(
    repository: PlaylistRepository,
    playbackManager: PlaybackManager,
    onEnterPiP: () -> Unit
) {
    var selectedTab by remember { mutableStateOf(AppTab.LIBRARY) }
    var selectedPlaylistId by remember { mutableStateOf<String?>(null) }
    var isFullPlayerExpanded by remember { mutableStateOf(false) }
    var addSongsToPlaylistId by remember { mutableStateOf<String?>(null) }
    var showChangeVideo by remember { mutableStateOf(false) }
    val snackbar = remember { SnackbarHostState() }
    val errorMessage by playbackManager.errorMessage.collectAsState()
    LaunchedEffect(errorMessage) {
        errorMessage?.let { snackbar.showSnackbar(it) }
    }

    val currentTrack by playbackManager.currentTrack.collectAsState()
    val isPlaying by playbackManager.isPlaying.collectAsState()
    val currentPosition by playbackManager.currentPosition.collectAsState()
    val duration by playbackManager.duration.collectAsState()
    val isAudioOnly by playbackManager.isAudioOnly.collectAsState()
    val isShuffled by playbackManager.isShuffled.collectAsState()
    val syncedLyrics by playbackManager.syncedLyrics.collectAsState()
    val plainLyrics by playbackManager.plainLyrics.collectAsState()
    val currentLyricIndex by playbackManager.currentLyricIndex.collectAsState()

    val progress = if (duration > 0) currentPosition.toFloat() / duration.toFloat() else 0f

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(BackgroundDark)
    ) {
        Scaffold(
            bottomBar = {
                NavigationBar(
                    containerColor = SurfaceDark.copy(alpha = 0.95f),
                    contentColor = TextPrimary
                ) {
                    NavigationBarItem(
                        selected = selectedTab == AppTab.LIBRARY,
                        onClick = {
                            selectedTab = AppTab.LIBRARY
                            selectedPlaylistId = null
                            addSongsToPlaylistId = null
                        },
                        icon = { Icon(Icons.Default.LibraryMusic, contentDescription = "Library") },
                        label = { Text("Library") },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = NeonPurple,
                            selectedTextColor = NeonPurple,
                            indicatorColor = NeonPurple.copy(alpha = 0.2f),
                            unselectedIconColor = TextTertiary,
                            unselectedTextColor = TextTertiary
                        )
                    )

                    NavigationBarItem(
                        selected = selectedTab == AppTab.SEARCH,
                        onClick = {
                            selectedTab = AppTab.SEARCH
                            selectedPlaylistId = null
                            addSongsToPlaylistId = null
                        },
                        icon = { Icon(Icons.Default.Search, contentDescription = "Search") },
                        label = { Text("Search") },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = NeonPink,
                            selectedTextColor = NeonPink,
                            indicatorColor = NeonPink.copy(alpha = 0.2f),
                            unselectedIconColor = TextTertiary,
                            unselectedTextColor = TextTertiary
                        )
                    )

                    NavigationBarItem(
                        selected = selectedTab == AppTab.MOST_PLAYED,
                        onClick = {
                            selectedTab = AppTab.MOST_PLAYED
                            selectedPlaylistId = null
                            addSongsToPlaylistId = null
                        },
                        icon = { Icon(Icons.Default.LocalFireDepartment, contentDescription = "Most Played") },
                        label = { Text("Most Played") },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = AccentCyan,
                            selectedTextColor = AccentCyan,
                            indicatorColor = AccentCyan.copy(alpha = 0.2f),
                            unselectedIconColor = TextTertiary,
                            unselectedTextColor = TextTertiary
                        )
                    )

                    NavigationBarItem(
                        selected = selectedTab == AppTab.ARTISTS,
                        onClick = {
                            selectedTab = AppTab.ARTISTS
                            selectedPlaylistId = null
                            addSongsToPlaylistId = null
                        },
                        icon = { Icon(Icons.Default.Mic, contentDescription = "Artists") },
                        label = { Text("Singers") },
                        colors = NavigationBarItemDefaults.colors(
                            selectedIconColor = NeonIndigo,
                            selectedTextColor = NeonIndigo,
                            indicatorColor = NeonIndigo.copy(alpha = 0.2f),
                            unselectedIconColor = TextTertiary,
                            unselectedTextColor = TextTertiary
                        )
                    )
                }
            },
            snackbarHost = { SnackbarHost(snackbar) },
            containerColor = BackgroundDark
        ) { padding ->
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
            ) {
                // Tab Content
                if (addSongsToPlaylistId != null) {
                    SearchScreen(
                        repository = repository,
                        playbackManager = playbackManager,
                        targetPlaylistId = addSongsToPlaylistId,
                        onBack = { addSongsToPlaylistId = null }
                    )
                } else if (selectedPlaylistId != null) {
                    PlaylistDetailScreen(
                        playlistId = selectedPlaylistId!!,
                        repository = repository,
                        playbackManager = playbackManager,
                        onBack = { selectedPlaylistId = null },
                        onAddSongs = { addSongsToPlaylistId = selectedPlaylistId }
                    )
                } else {
                    when (selectedTab) {
                        AppTab.LIBRARY -> LibraryScreen(
                            repository = repository,
                            onSelectPlaylist = { id -> selectedPlaylistId = id }
                        )
                        AppTab.SEARCH -> SearchScreen(
                            repository = repository,
                            playbackManager = playbackManager
                        )
                        AppTab.MOST_PLAYED -> MostPlayedScreen(
                            repository = repository,
                            playbackManager = playbackManager
                        )
                        AppTab.ARTISTS -> ArtistsScreen(
                            repository = repository,
                            playbackManager = playbackManager
                        )
                    }
                }

                // Persistent Floating MiniPlayer
                if (currentTrack != null) {
                    MiniPlayer(
                        track = currentTrack,
                        isPlaying = isPlaying,
                        progress = progress,
                        isAudioOnly = isAudioOnly,
                        onPlayPause = { playbackManager.togglePlayPause() },
                        onNext = { playbackManager.playNext() },
                        onClick = { isFullPlayerExpanded = true },
                        modifier = Modifier
                            .align(Alignment.BottomCenter)
                            .padding(bottom = 8.dp)
                    )
                }
            }
        }

        // Full Player Modal
        AnimatedVisibility(
            visible = isFullPlayerExpanded,
            enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
            exit = slideOutVertically(targetOffsetY = { it }) + fadeOut()
        ) {
            FullPlayerSheet(
                playbackManager = playbackManager,
                track = currentTrack,
                isPlaying = isPlaying,
                positionMs = currentPosition,
                durationMs = duration,
                isAudioOnly = isAudioOnly,
                isShuffled = isShuffled,
                syncedLyrics = syncedLyrics,
                plainLyrics = plainLyrics,
                currentLyricIndex = currentLyricIndex,
                onDismiss = { isFullPlayerExpanded = false },
                onPlayPause = { playbackManager.togglePlayPause() },
                onSeek = { playbackManager.seekTo(it) },
                onPrevious = { playbackManager.playPrevious() },
                onNext = { playbackManager.playNext() },
                onToggleAudioOnly = { playbackManager.toggleAudioOnly() },
                onToggleShuffle = { playbackManager.toggleShuffle() },
                onToggleFavorite = { currentTrack?.let { repository.toggleFavorite(it) } },
                onChangeVideo = { showChangeVideo = true },
                onEnterPiP = onEnterPiP
            )
        }
    
        // Change the current song's video (saved to every playlist that has it)
        val trackForChange = currentTrack
        if (showChangeVideo && trackForChange != null) {
            ChangeVideoLinkDialog(
                track = trackForChange,
                onDismiss = { showChangeVideo = false },
                onConfirm = { newId ->
                    showChangeVideo = false
                    repository.updateTrackVideo(trackForChange.id, newId)
                    playbackManager.playTrack(
                        trackForChange.copy(
                            youtubeId = newId,
                            originalURL = "https://www.youtube.com/watch?v=$newId",
                            thumbnailURL = "https://img.youtube.com/vi/$newId/hqdefault.jpg"
                        ),
                        playbackManager.queue.value
                    )
                }
            )
        }
    }
}
