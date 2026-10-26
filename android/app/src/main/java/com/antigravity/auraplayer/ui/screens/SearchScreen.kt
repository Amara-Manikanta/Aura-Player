package com.antigravity.auraplayer.ui.screens

import com.antigravity.auraplayer.ui.components.PlaylistPickerDialog

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.antigravity.auraplayer.data.PlaylistRepository
import com.antigravity.auraplayer.model.MediaTrack
import com.antigravity.auraplayer.model.Playlist
import com.antigravity.auraplayer.service.PlaybackManager
import com.antigravity.auraplayer.service.YouTubeSearchResult
import com.antigravity.auraplayer.service.YouTubeService
import com.antigravity.auraplayer.ui.theme.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** A song the user tried to add that's already in one or more playlists. */
private data class PendingDuplicate(val track: MediaTrack, val playlistId: String, val inPlaylists: List<String>)

/**
 * YouTube search: type a song name (results appear as you type, best official video first)
 * or paste a link. Results can be played right away or added to a playlist.
 *
 * @param targetPlaylistId when opened from a playlist, "Add" goes straight into it;
 *   otherwise the user picks a playlist.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(
    repository: PlaylistRepository,
    playbackManager: PlaybackManager,
    targetPlaylistId: String? = null,
    onBack: (() -> Unit)? = null
) {
    val playlists by repository.playlists.collectAsState()
    val targetPlaylist = playlists.firstOrNull { it.id == targetPlaylistId }
    val scope = rememberCoroutineScope()
    val focusManager = LocalFocusManager.current
    val snackbar = remember { SnackbarHostState() }

    var query by rememberSaveable { mutableStateOf("") }
    var results by remember { mutableStateOf<List<YouTubeSearchResult>>(emptyList()) }
    var linkTrack by remember { mutableStateOf<MediaTrack?>(null) }
    var isSearching by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var searchToken by remember { mutableIntStateOf(0) }

    var trackToAdd by remember { mutableStateOf<MediaTrack?>(null) } // waiting for a playlist choice
    var pendingDuplicate by remember { mutableStateOf<PendingDuplicate?>(null) }

    fun runSearch(q: String) {
        val trimmed = q.trim()
        if (trimmed.isEmpty()) return
        val token = ++searchToken
        isSearching = true
        error = null
        scope.launch {
            try {
                if (YouTubeService.isYouTubeLink(trimmed)) {
                    val t = YouTubeService.fetchTrack(trimmed)
                    if (token != searchToken) return@launch
                    linkTrack = t
                    results = emptyList()
                    if (t == null) error = "Couldn't load that link"
                } else {
                    val r = YouTubeService.search(trimmed, limit = 10)
                    if (token != searchToken) return@launch // a newer search started
                    linkTrack = null
                    results = r
                    if (r.isEmpty()) error = "No official video found for \"$trimmed\""
                }
            } catch (e: Exception) {
                if (token == searchToken) error = "Search failed: ${e.message ?: "network error"}"
            } finally {
                if (token == searchToken) isSearching = false
            }
        }
    }

    // Search as you type (links load on Enter)
    LaunchedEffect(query) {
        val q = query.trim()
        if (q.length < 3 || YouTubeService.isYouTubeLink(q)) return@LaunchedEffect
        delay(500)
        runSearch(q)
    }

    fun addTo(playlistId: String, track: MediaTrack) {
        val matches = repository.playlistsContaining(track)
        if (matches.isNotEmpty()) {
            pendingDuplicate = PendingDuplicate(track, playlistId, matches.map { it.name })
            return
        }
        repository.addTrackToPlaylist(playlistId, track)
        val name = playlists.firstOrNull { it.id == playlistId }?.name ?: "playlist"
        scope.launch { snackbar.showSnackbar("Added to $name") }
    }

    fun requestAdd(track: MediaTrack) {
        if (targetPlaylistId != null) addTo(targetPlaylistId, track) else trackToAdd = track
    }

    fun play(track: MediaTrack) {
        focusManager.clearFocus()
        playbackManager.playTrack(track)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        if (targetPlaylist != null) "Add to ${targetPlaylist.name}" else "Search",
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                },
                navigationIcon = {
                    if (onBack != null) {
                        IconButton(onClick = onBack) { Icon(Icons.Default.ArrowBack, contentDescription = "Back") }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = androidx.compose.ui.graphics.Color.Transparent)
            )
        },
        snackbarHost = { SnackbarHost(snackbar) },
        containerColor = androidx.compose.ui.graphics.Color.Transparent
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp)
        ) {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                placeholder = { Text("Song name or YouTube link") },
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                trailingIcon = {
                    if (query.isNotEmpty()) {
                        IconButton(onClick = {
                            query = ""
                            results = emptyList()
                            linkTrack = null
                            error = null
                            searchToken++
                            isSearching = false
                        }) { Icon(Icons.Default.Close, contentDescription = "Clear") }
                    }
                },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = {
                    focusManager.clearFocus()
                    runSearch(query)
                }),
                shape = RoundedCornerShape(14.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = NeonPurple,
                    unfocusedBorderColor = GlassBorder,
                    focusedContainerColor = SurfaceCard,
                    unfocusedContainerColor = SurfaceCard
                ),
                modifier = Modifier.fillMaxWidth()
            )

            Spacer(Modifier.height(10.dp))

            // Play Best Match: find the official video and play it in one tap
            if (query.isNotBlank() && !YouTubeService.isYouTubeLink(query)) {
                Button(
                    onClick = {
                        focusManager.clearFocus()
                        val best = results.firstOrNull()
                        if (best != null && !isSearching) {
                            play(best.toTrack())
                        } else {
                            isSearching = true
                            scope.launch {
                                val b = YouTubeService.bestOfficialVideo(query.trim())
                                isSearching = false
                                if (b != null) play(b.toTrack()) else error = "No official video found"
                            }
                        }
                    },
                    enabled = !isSearching,
                    colors = ButtonDefaults.buttonColors(containerColor = NeonPurple),
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Icon(Icons.Default.PlayArrow, contentDescription = null)
                    Spacer(Modifier.width(6.dp))
                    Text("Play Best Match", fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.height(10.dp))
            }

            if (isSearching) {
                LinearProgressIndicator(
                    modifier = Modifier.fillMaxWidth(),
                    color = NeonPurple,
                    trackColor = SurfaceCard
                )
                Spacer(Modifier.height(8.dp))
            }

            error?.let {
                Text(it, color = DangerRed, style = MaterialTheme.typography.bodySmall)
                Spacer(Modifier.height(8.dp))
            }

            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(8.dp),
                contentPadding = PaddingValues(bottom = 96.dp) // room for the mini player
            ) {
                linkTrack?.let { t ->
                    item(key = "link-${t.youtubeId}") {
                        ResultRow(
                            title = t.title,
                            subtitle = "${t.artist} • ${formatDuration(t.duration)}",
                            thumbnail = t.thumbnailURL,
                            isBest = false,
                            onPlay = { play(t) },
                            onAdd = { requestAdd(t) }
                        )
                    }
                }
                itemsIndexed(results, key = { _, r -> r.id }) { index, r ->
                    ResultRow(
                        title = r.title,
                        subtitle = "${r.channel} • ${r.formattedDuration}",
                        thumbnail = r.thumbnailUrl,
                        isBest = index == 0,
                        onPlay = { play(r.toTrack()) },
                        onAdd = { requestAdd(r.toTrack()) }
                    )
                }
                if (results.isEmpty() && linkTrack == null && !isSearching && error == null) {
                    item {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 48.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Icon(Icons.Default.LibraryMusic, contentDescription = null, tint = NeonPurple.copy(alpha = 0.7f), modifier = Modifier.size(48.dp))
                            Spacer(Modifier.height(12.dp))
                            Text("Find any song", color = TextPrimary, fontWeight = FontWeight.Bold)
                            Text(
                                "Type a song name — the official video song comes first.\nLyric videos, Shorts and reels are skipped.",
                                color = TextSecondary,
                                style = MaterialTheme.typography.bodySmall,
                                modifier = Modifier.padding(top = 4.dp)
                            )
                        }
                    }
                }
            }
        }
    }

    // Choose a playlist (Search tab)
    trackToAdd?.let { track ->
        PlaylistPickerDialog(
            playlists = playlists,
            onPick = { pl ->
                trackToAdd = null
                addTo(pl.id, track)
            },
            onCreate = { name ->
                trackToAdd = null
                val pl = repository.addPlaylist(name)
                addTo(pl.id, track)
            },
            onDismiss = { trackToAdd = null }
        )
    }

    // Already added somewhere
    pendingDuplicate?.let { dup ->
        AlertDialog(
            onDismissRequest = { pendingDuplicate = null },
            title = { Text("Song Already Added") },
            text = { Text("\"${dup.track.title}\" is already in: ${dup.inPlaylists.joinToString(", ")}.") },
            confirmButton = {
                TextButton(onClick = {
                    repository.addTrackToPlaylist(dup.playlistId, dup.track, allowDuplicate = true)
                    pendingDuplicate = null
                    scope.launch { snackbar.showSnackbar("Added again") }
                }) { Text("Add Anyway") }
            },
            dismissButton = {
                TextButton(onClick = { pendingDuplicate = null }) { Text("Cancel") }
            }
        )
    }
}

@Composable
private fun ResultRow(
    title: String,
    subtitle: String,
    thumbnail: String?,
    isBest: Boolean,
    onPlay: () -> Unit,
    onAdd: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(if (isBest) NeonPurple.copy(alpha = 0.12f) else SurfaceCard)
            .clickable { onPlay() }
            .padding(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        AsyncImage(
            model = thumbnail,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .size(width = 96.dp, height = 54.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(SurfaceDark)
        )
        Spacer(Modifier.width(10.dp))
        Column(modifier = Modifier.weight(1f)) {
            if (isBest) {
                Text(
                    "BEST MATCH",
                    color = NeonPurple,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .background(NeonPurple.copy(alpha = 0.2f))
                        .padding(horizontal = 6.dp, vertical = 1.dp)
                )
                Spacer(Modifier.height(2.dp))
            }
            Text(title, color = TextPrimary, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyMedium)
            Text(subtitle, color = TextSecondary, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall)
        }
        IconButton(onClick = onPlay) {
            Icon(Icons.Default.PlayCircle, contentDescription = "Play", tint = TextPrimary)
        }
        IconButton(onClick = onAdd) {
            Icon(Icons.Default.PlaylistAdd, contentDescription = "Add to playlist", tint = NeonPurple)
        }
    }
}

private fun formatDuration(seconds: Double): String {
    if (seconds <= 0) return "--:--"
    val total = seconds.toInt()
    return "%d:%02d".format(total / 60, total % 60)
}
