package com.antigravity.auraplayer.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.antigravity.auraplayer.data.PlaylistRepository
import com.antigravity.auraplayer.model.MediaTrack
import com.antigravity.auraplayer.service.PlaybackManager
import com.antigravity.auraplayer.ui.components.*
import com.antigravity.auraplayer.ui.theme.*

enum class AppTab(val title: String, val icon: ImageVector) {
    HOME("Home", Icons.Default.Home),
    DISCOVER("For You", Icons.Default.AutoAwesome),
    SEARCH("Search", Icons.Default.Search),
    LIBRARY("Library", Icons.Default.LibraryMusic)
}

/** Screens opened on top of a tab */
sealed class Route {
    data class PlaylistDetail(val id: String) : Route()
    data class AddSongs(val playlistId: String) : Route()
    data object MostPlayed : Route()
    data object RecentlyAdded : Route()
    data object NewReleases : Route()
    data object Artists : Route()
    data object Settings : Route()
}

@Composable
fun MainScreen(
    repository: PlaylistRepository,
    playbackManager: PlaybackManager,
    onEnterPiP: () -> Unit
) {
    var selectedTab by remember { mutableStateOf(AppTab.HOME) }
    val stack = remember { mutableStateListOf<Route>() }
    var isFullPlayerExpanded by remember { mutableStateOf(false) }
    var showChangeVideo by remember { mutableStateOf(false) }
    var addCurrentToPlaylist by remember { mutableStateOf(false) }
    val snackbar = remember { SnackbarHostState() }
    val errorMessage by playbackManager.errorMessage.collectAsState()
    LaunchedEffect(errorMessage) { errorMessage?.let { snackbar.showSnackbar(it) } }
    val currentTrack by playbackManager.currentTrack.collectAsState()
    val playlists by repository.playlists.collectAsState()

    fun open(route: Route) { stack.add(route) }
    fun back() { if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex) }
    BackHandler(enabled = stack.isNotEmpty() && !isFullPlayerExpanded) { back() }
    BackHandler(enabled = isFullPlayerExpanded) { isFullPlayerExpanded = false }

    Box(Modifier.fillMaxSize()) {
        AuraBackground()

        // Content: the open screen, or the tab
        Box(Modifier.fillMaxSize()) {
            when (val route = stack.lastOrNull()) {
                is Route.PlaylistDetail -> Box(Modifier.statusBarsPadding()) {
                    PlaylistDetailScreen(route.id, repository, playbackManager, onBack = { back() },
                        onAddSongs = { open(Route.AddSongs(route.id)) })
                }
                is Route.AddSongs -> Box(Modifier.statusBarsPadding()) {
                    SearchScreen(repository, playbackManager, targetPlaylistId = route.playlistId, onBack = { back() })
                }
                Route.MostPlayed -> Box(Modifier.statusBarsPadding()) {
                    SongListScreen("Most Played", remember(playlists) { repository.mostPlayedTracks }, repository, playbackManager,
                        onBack = { back() }, subtitle = { t -> "${t.artist} • ${t.totalPlays} plays" })
                }
                Route.RecentlyAdded -> Box(Modifier.statusBarsPadding()) {
                    val fmt = remember { java.text.SimpleDateFormat("d MMM yyyy", java.util.Locale.getDefault()) }
                    SongListScreen("Recently Added", remember(playlists) { repository.recentlyAddedTracks }, repository, playbackManager,
                        onBack = { back() }, subtitle = { t -> "${t.artist} • added ${fmt.format(java.util.Date(t.dateAdded))}" })
                }
                Route.NewReleases -> Column(Modifier.statusBarsPadding()) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        IconButton(onClick = { back() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = TextPrimary) }
                        Text("New Releases", color = TextPrimary, fontWeight = FontWeight.Bold, fontSize = 20.sp)
                    }
                    NewReleasesContent(repository, playbackManager)
                }
                Route.Artists -> Box(Modifier.statusBarsPadding()) {
                    ArtistsScreen(repository, playbackManager, onBack = { back() })
                }
                Route.Settings -> Box(Modifier.statusBarsPadding()) {
                    SettingsScreen(repository, playbackManager, onBack = { back() })
                }
                null -> when (selectedTab) {
                    AppTab.HOME -> HomeScreen(
                        repository, playbackManager,
                        onOpenPlaylist = { open(Route.PlaylistDetail(it)) },
                        onSeeAllPlaylists = { selectedTab = AppTab.LIBRARY },
                        onOpenDiscover = { selectedTab = AppTab.DISCOVER }
                    )
                    AppTab.DISCOVER -> DiscoverScreen(repository, playbackManager)
                    AppTab.SEARCH -> Box(Modifier.statusBarsPadding()) { SearchScreen(repository, playbackManager) }
                    AppTab.LIBRARY -> LibraryScreen(
                        repository,
                        onSelectPlaylist = { open(Route.PlaylistDetail(it)) },
                        onMostPlayed = { open(Route.MostPlayed) },
                        onRecentlyAdded = { open(Route.RecentlyAdded) },
                        onNewReleases = { open(Route.NewReleases) },
                        onArtists = { open(Route.Artists) },
                        onSettings = { open(Route.Settings) }
                    )
                }
            }
        }

        // Floating mini player + glass tab bar
        Column(Modifier.align(Alignment.BottomCenter).navigationBarsPadding()) {
            if (currentTrack != null) {
                MiniPlayer(
                    playbackManager = playbackManager,
                    onClick = { isFullPlayerExpanded = true },
                    onChangeVideo = { showChangeVideo = true },
                    onAddToPlaylist = { addCurrentToPlaylist = true }
                )
            }
            GlassTabBar(selectedTab) { tab ->
                selectedTab = tab
                stack.clear()
            }
        }

        SnackbarHost(snackbar, Modifier.align(Alignment.TopCenter).statusBarsPadding())

        // Full Player
        AnimatedVisibility(
            visible = isFullPlayerExpanded,
            enter = slideInVertically(initialOffsetY = { it }) + fadeIn(),
            exit = slideOutVertically(targetOffsetY = { it }) + fadeOut()
        ) {
            FullPlayerSheet(
                playbackManager = playbackManager,
                onDismiss = { isFullPlayerExpanded = false },
                onChangeVideo = { showChangeVideo = true },
                onAddToPlaylist = { addCurrentToPlaylist = true },
                onEnterPiP = onEnterPiP
            )
        }

        // Change the current song's video (saved to every copy of the song)
        val trackForChange = currentTrack
        if (showChangeVideo && trackForChange != null) {
            ChangeVideoLinkDialog(
                track = trackForChange,
                onDismiss = { showChangeVideo = false },
                onConfirm = { newId ->
                    showChangeVideo = false
                    repository.setVideo(trackForChange.id, newId)
                    playbackManager.playTrack(
                        trackForChange.copy(youtubeId = newId, thumbnailURL = "https://i.ytimg.com/vi/$newId/hqdefault.jpg"),
                        playbackManager.queue.value
                    )
                }
            )
        }

        if (addCurrentToPlaylist && trackForChange != null) {
            PlaylistPickerDialog(
                playlists = playlists,
                onPick = { pl -> repository.addTrackToPlaylist(pl.id, trackForChange); addCurrentToPlaylist = false },
                onCreate = { name -> repository.addTrackToPlaylist(repository.addPlaylist(name).id, trackForChange); addCurrentToPlaylist = false },
                onDismiss = { addCurrentToPlaylist = false }
            )
        }
    }
}

/** Floating frosted tab bar, like iOS 26's */
@Composable
private fun GlassTabBar(selected: AppTab, onSelect: (AppTab) -> Unit) {
    val shape = RoundedCornerShape(32.dp)
    Row(
        Modifier
            .fillMaxWidth()
            .padding(start = 16.dp, end = 16.dp, bottom = 8.dp)
            .shadow(12.dp, shape, ambientColor = Color(0x55000000), spotColor = Color(0x55000000))
            .background(BackdropBottom.copy(alpha = 0.95f), shape)
            .glass(shape, alpha = 0.12f)
            .padding(6.dp)
    ) {
        AppTab.entries.forEach { tab ->
            val on = tab == selected
            Column(
                Modifier.weight(1f)
                    .background(if (on) Color.White.copy(alpha = 0.22f) else Color.Transparent, RoundedCornerShape(26.dp))
                    .clickable { onSelect(tab) }
                    .padding(vertical = 7.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Icon(tab.icon, contentDescription = tab.title, tint = if (on) Color.White else TextSecondary, modifier = Modifier.size(24.dp))
                Text(tab.title, color = if (on) Color.White else TextSecondary, fontSize = 11.sp,
                    fontWeight = if (on) FontWeight.Bold else FontWeight.Medium)
            }
        }
    }
}
