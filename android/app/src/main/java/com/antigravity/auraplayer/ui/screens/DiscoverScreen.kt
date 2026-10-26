package com.antigravity.auraplayer.ui.screens

import android.content.Context
import android.text.format.DateUtils
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.antigravity.auraplayer.data.PlaylistRepository
import com.antigravity.auraplayer.model.MediaTrack
import com.antigravity.auraplayer.service.*
import com.antigravity.auraplayer.ui.components.*
import com.antigravity.auraplayer.ui.theme.*
import kotlinx.coroutines.launch

/**
 * Discover, like the Mac and iPhone apps: "Top Picks" (from YouTube's mixes of your favourite songs),
 * "New for You" (this month's releases ranked by the singers and languages you play) and New Releases.
 */
@Composable
fun DiscoverScreen(repository: PlaylistRepository, playbackManager: PlaybackManager) {
    val prefs = LocalContext.current.getSharedPreferences(PlaybackManager.PREFS, Context.MODE_PRIVATE)
    var tab by remember { mutableIntStateOf(prefs.getInt("discoverTab", 0)) }
    Column(Modifier.fillMaxSize().statusBarsPadding()) {
        Text("Discover", color = TextPrimary, fontWeight = FontWeight.Bold, fontSize = 26.sp,
            modifier = Modifier.padding(start = 20.dp, top = 12.dp, bottom = 10.dp))
        SegmentedTabs(
            listOf("Top Picks", "New for You", "New Releases"), tab,
            onSelect = { tab = it; prefs.edit().putInt("discoverTab", it).apply() },
            modifier = Modifier.padding(horizontal = 16.dp)
        )
        Spacer(Modifier.height(8.dp))
        when (tab) {
            0 -> TopPicks(repository, playbackManager)
            1 -> NewForYouList(repository, playbackManager)
            else -> NewReleasesContent(repository, playbackManager)
        }
    }
}

/** Pick a playlist for a song shown in Discover */
@Composable
private fun AddDialog(track: MediaTrack?, repository: PlaylistRepository, onDone: () -> Unit) {
    val t = track ?: return
    val context = LocalContext.current
    val playlists by repository.playlists.collectAsState()
    PlaylistPickerDialog(
        playlists = playlists,
        onPick = { pl ->
            val already = repository.playlistsContaining(t).any { it.id == pl.id }
            if (!already) repository.addTrackToPlaylist(pl.id, t)
            android.widget.Toast.makeText(context, if (already) "Already in ${pl.name.trim()}" else "Added to ${pl.name.trim()}",
                android.widget.Toast.LENGTH_SHORT).show()
            onDone()
        },
        onCreate = { name -> repository.addTrackToPlaylist(repository.addPlaylist(name).id, t); onDone() },
        onDismiss = onDone
    )
}

@Composable
private fun HeaderRow(subtitle: String, busy: Boolean, onRefresh: () -> Unit, onPlayAll: (() -> Unit)?) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(subtitle, color = TextTertiary, fontSize = 12.sp, modifier = Modifier.weight(1f), maxLines = 2)
        IconButton(onClick = onRefresh, enabled = !busy, modifier = Modifier.size(38.dp).glass(RoundedCornerShape(50))) {
            Icon(Icons.Default.Refresh, contentDescription = "Refresh", tint = NeonPurple)
        }
        Spacer(Modifier.width(8.dp))
        Button(
            onClick = { onPlayAll?.invoke() }, enabled = onPlayAll != null,
            colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = BackdropMid),
            contentPadding = PaddingValues(horizontal = 14.dp)
        ) { Icon(Icons.Default.PlayArrow, null, Modifier.size(18.dp)); Spacer(Modifier.width(4.dp)); Text("Play All", fontWeight = FontWeight.Bold) }
    }
}

@Composable
private fun Waiting(progress: Pair<Int, Int>?, text: String) {
    Column(Modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        if (progress != null && progress.second > 0) {
            LinearProgressIndicator(progress = { progress.first.toFloat() / progress.second }, modifier = Modifier.width(220.dp), color = NeonPurple)
        } else CircularProgressIndicator(color = NeonPurple)
        Spacer(Modifier.height(14.dp))
        Text(text, color = TextSecondary, fontSize = 13.sp, textAlign = TextAlign.Center)
    }
}

@Composable
private fun TopPicks(repository: PlaylistRepository, playbackManager: PlaybackManager) {
    val scope = rememberCoroutineScope()
    val current by playbackManager.currentTrack.collectAsState()
    val isPlaying by playbackManager.isPlaying.collectAsState()
    var picks by remember { mutableStateOf(RecommendationService.cached()) }
    var working by remember { mutableStateOf(false) }
    var progress by remember { mutableStateOf(0 to 0) }
    var toAdd by remember { mutableStateOf<MediaTrack?>(null) }

    fun load(forceNew: Boolean) {
        if (working) return
        if (!forceNew && picks.isNotEmpty() && System.currentTimeMillis() - RecommendationService.generatedAt < 86_400_000) return
        working = true
        progress = 0 to 0
        scope.launch {
            val result = RecommendationService.generate(
                TasteBuilder.seeds(repository, 20), TasteBuilder.knownSongs(repository),
                repository.allUniqueTracks.mapNotNull { it.youtubeId }.toSet()
            ) { d, t -> scope.launch { progress = d to t } }
            if (result.isNotEmpty()) picks = result
            working = false
        }
    }
    LaunchedEffect(Unit) { load(false) }

    val tracks = remember(picks) { picks.map { it.video.toRawTrack() } }
    val subtitle = when {
        working -> if (progress.second > 0) "Learning from your favourite songs… ${progress.first}/${progress.second}" else "Finding songs for you…"
        picks.isEmpty() -> "Songs you don't have yet that match what you play"
        else -> "${picks.size} songs • updated ${DateUtils.getRelativeTimeSpanString(RecommendationService.generatedAt)}"
    }
    HeaderRow(subtitle, working, { load(true) }, tracks.firstOrNull()?.let { { playbackManager.playTrack(it, tracks, PlayContext.None) } })
    if (working && picks.isEmpty()) {
        Waiting(progress, "Listening to YouTube's mixes of your favourite songs…\nThe first time takes about a minute.")
    } else {
        LazyColumn(contentPadding = PaddingValues(bottom = 120.dp)) {
            itemsIndexed(picks, key = { _, s -> s.videoId }) { i, s ->
                DiscoverRow(
                    video = s.video, reason = s.reason,
                    isCurrent = current?.youtubeId == s.videoId, isPlaying = isPlaying,
                    onPlay = { playbackManager.playTrack(tracks[i], tracks, PlayContext.None) },
                    onAdd = { toAdd = tracks[i] },
                    onNotInterested = { RecommendationService.markNotInterested(s.videoId); picks = RecommendationService.cached() }
                )
            }
        }
    }
    AddDialog(toAdd, repository) { toAdd = null }
}

@Composable
private fun NewForYouList(repository: PlaylistRepository, playbackManager: PlaybackManager) {
    val scope = rememberCoroutineScope()
    val current by playbackManager.currentTrack.collectAsState()
    val isPlaying by playbackManager.isPlaying.collectAsState()
    var items by remember { mutableStateOf(NewForYouCache.items) }
    var working by remember { mutableStateOf(false) }
    var toAdd by remember { mutableStateOf<MediaTrack?>(null) }

    fun load() {
        if (working) return
        working = true
        scope.launch {
            items = RecommendationService.newForYou(TasteBuilder.profile(repository))
            NewForYouCache.items = items
            working = false
        }
    }
    LaunchedEffect(Unit) { if (items.isEmpty()) load() }

    val tracks = remember(items) { items.map { it.release.video.toRawTrack() } }
    HeaderRow(
        if (working) "Checking this month's releases in your languages…" else "${items.size} new songs this month, ranked by your singers and languages",
        working, { load() }, tracks.firstOrNull()?.let { { playbackManager.playTrack(it, tracks, PlayContext.None) } }
    )
    if (working && items.isEmpty()) {
        Waiting(null, "Checking this month's releases in your languages…")
    } else {
        LazyColumn(contentPadding = PaddingValues(bottom = 120.dp)) {
            itemsIndexed(items, key = { _, n -> n.release.id }) { i, n ->
                DiscoverRow(
                    video = n.release.video, reason = n.reason, views = n.release.views, uploadedAgo = n.release.uploadedAgo,
                    isCurrent = current?.youtubeId == n.release.id, isPlaying = isPlaying,
                    onPlay = { playbackManager.playTrack(tracks[i], tracks, PlayContext.None) },
                    onAdd = { toAdd = tracks[i] },
                    onNotInterested = {
                        RecommendationService.markNotInterested(n.release.id)
                        items = items.filter { it.release.id != n.release.id }
                        NewForYouCache.items = items
                    }
                )
            }
        }
    }
    AddDialog(toAdd, repository) { toAdd = null }
}

/** Keeps New for You while the app runs (it takes a few seconds to build) */
private object NewForYouCache {
    var items: List<RecommendationService.NewForYou> = emptyList()
}

/** Songs uploaded this week / this month in a language (same search and filters as the Mac app) */
@Composable
fun NewReleasesContent(repository: PlaylistRepository, playbackManager: PlaybackManager) {
    val prefs = LocalContext.current.getSharedPreferences(PlaybackManager.PREFS, Context.MODE_PRIVATE)
    val scope = rememberCoroutineScope()
    val current by playbackManager.currentTrack.collectAsState()
    val isPlaying by playbackManager.isPlaying.collectAsState()
    val languages = listOf("Telugu", "Hindi", "Tamil", "English", "Kannada", "Malayalam", "Punjabi")
    var language by remember { mutableStateOf(prefs.getString("newReleasesLanguage", "Telugu") ?: "Telugu") }
    var period by remember { mutableStateOf(ReleasePeriod.WEEK) }
    var releases by remember { mutableStateOf<List<NewRelease>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var toAdd by remember { mutableStateOf<MediaTrack?>(null) }

    fun load(force: Boolean) {
        loading = true
        if (!force) releases = emptyList()
        scope.launch {
            releases = YouTubeService.newReleases(language, period, force)
            loading = false
        }
    }
    LaunchedEffect(language, period) { load(false) }

    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        languages.forEach { l ->
            val on = l == language
            Text(l, color = if (on) BackdropBottom else TextSecondary, fontWeight = FontWeight.SemiBold, fontSize = 13.sp,
                modifier = Modifier.clip(RoundedCornerShape(50))
                    .then(if (on) Modifier.background(Color.White) else Modifier.glass(RoundedCornerShape(50)))
                    .clickable { language = l; prefs.edit().putString("newReleasesLanguage", l).apply() }
                    .padding(horizontal = 16.dp, vertical = 8.dp))
        }
    }
    val tracks = remember(releases) { releases.map { it.video.toRawTrack() } }
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        SegmentedTabs(ReleasePeriod.entries.map { it.label }, period.ordinal, { period = ReleasePeriod.entries[it] }, Modifier.width(220.dp))
        Spacer(Modifier.weight(1f))
        Button(
            onClick = { tracks.firstOrNull()?.let { playbackManager.playTrack(it, tracks, PlayContext.None) } },
            enabled = tracks.isNotEmpty(),
            colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = BackdropMid),
            contentPadding = PaddingValues(horizontal = 14.dp)
        ) { Icon(Icons.Default.PlayArrow, null, Modifier.size(18.dp)); Text("Play All", fontWeight = FontWeight.Bold) }
    }
    when {
        loading && releases.isEmpty() -> Waiting(null, "Searching YouTube for new $language songs…")
        releases.isEmpty() -> Column(Modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("No new $language songs found ${period.label.lowercase()}.", color = TextSecondary)
            if (period == ReleasePeriod.WEEK) TextButton(onClick = { period = ReleasePeriod.MONTH }) { Text("Show This Month", color = NeonPurple) }
            TextButton(onClick = { load(true) }) { Text("Try Again", color = NeonPurple) }
        }
        else -> LazyColumn(contentPadding = PaddingValues(bottom = 120.dp)) {
            item {
                Text("${releases.size} songs uploaded ${period.label.lowercase()}", color = TextTertiary, fontSize = 12.sp,
                    modifier = Modifier.padding(start = 16.dp, bottom = 4.dp))
            }
            itemsIndexed(releases, key = { _, r -> r.id }) { i, r ->
                DiscoverRow(
                    video = r.video, views = r.views, uploadedAgo = r.uploadedAgo,
                    isCurrent = current?.youtubeId == r.id, isPlaying = isPlaying,
                    onPlay = { playbackManager.playTrack(tracks[i], tracks, PlayContext.None) },
                    onAdd = { toAdd = tracks[i] }
                )
            }
        }
    }
    AddDialog(toAdd, repository) { toAdd = null }
}
