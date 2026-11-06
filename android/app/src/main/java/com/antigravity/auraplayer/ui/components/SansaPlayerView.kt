package com.antigravity.auraplayer.ui.components

import android.content.res.Configuration
import android.view.HapticFeedbackConstants
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.*
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.antigravity.auraplayer.data.PlaylistRepository
import com.antigravity.auraplayer.model.MediaTrack
import com.antigravity.auraplayer.service.DisplayMode
import com.antigravity.auraplayer.service.PlaybackManager
import com.antigravity.auraplayer.ui.theme.SansaTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun SansaPlayerView(
    playbackManager: PlaybackManager,
    repository: PlaylistRepository,
    onDismiss: () -> Unit,
    onOpenSettings: () -> Unit,
    onChangeTheme: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val view = LocalView.current
    val track by playbackManager.currentTrack.collectAsState()
    val isPlaying by playbackManager.isPlaying.collectAsState()
    val displayMode by playbackManager.displayMode.collectAsState()
    val positionMs by playbackManager.currentPosition.collectAsState()
    val durationMs by playbackManager.duration.collectAsState()
    val isShuffled by playbackManager.isShuffled.collectAsState()
    val repeatMode by playbackManager.repeatMode.collectAsState()
    val syncedLyrics by playbackManager.syncedLyrics.collectAsState()
    val plainLyrics by playbackManager.plainLyrics.collectAsState()
    val currentLyricIndex by playbackManager.currentLyricIndex.collectAsState()
    val artworkUrl by playbackManager.artworkUrl.collectAsState()

    val t = track ?: return
    val fav = repository.isFavorite(t)

    var wheelMode by remember { mutableStateOf(SansaWheelMode.SEEK) }
    var feedbackText by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    var showMenu by remember { mutableStateOf(false) }
    var showChangeVideo by remember { mutableStateOf(false) }
    var showAddToPlaylist by remember { mutableStateOf(false) }
    var showLyricsEditor by remember { mutableStateOf(false) }

    val isLandscape = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE

    fun showFeedback(msg: String) {
        feedbackText = msg
        scope.launch {
            delay(1800)
            if (feedbackText == msg) feedbackText = null
        }
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(SansaTheme.ChassisGradient)
            .statusBarsPadding()
            .navigationBarsPadding()
    ) {
        // Physical chassis chamfer border
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(4.dp)
                .border(
                    width = 1.5.dp,
                    brush = Brush.linearGradient(
                        listOf(SansaTheme.MetallicEdge, Color.Black.copy(alpha = 0.8f))
                    ),
                    shape = RoundedCornerShape(28.dp)
                )
        )

        if (isLandscape) {
            // Landscape 2-column Layout
            Row(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 20.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Left Column: LCD Display Screen
                Box(
                    modifier = Modifier
                        .weight(1.2f)
                        .fillMaxHeight(),
                    contentAlignment = Alignment.Center
                ) {
                    SansaLcdScreen(
                        track = t,
                        isPlaying = isPlaying,
                        displayMode = displayMode,
                        positionMs = positionMs,
                        durationMs = durationMs,
                        feedbackText = feedbackText,
                        wheelMode = wheelMode,
                        syncedLyrics = syncedLyrics,
                        plainLyrics = plainLyrics,
                        currentLyricIndex = currentLyricIndex,
                        artworkUrl = artworkUrl,
                        playbackManager = playbackManager,
                        onSeekTo = { playbackManager.seekTo(it) },
                        onEditLyrics = { showLyricsEditor = true },
                        modifier = Modifier.fillMaxSize()
                    )
                }

                Spacer(Modifier.width(16.dp))

                // Right Column: Hardware Wheel & Controls
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxHeight(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.SpaceBetween
                ) {
                    // Top Bar (Branding & Dismiss/Menu)
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        IconButton(onClick = onDismiss, modifier = Modifier.size(36.dp)) {
                            Icon(Icons.Default.KeyboardArrowDown, "Collapse", tint = SansaTheme.LcdTextSecondary)
                        }

                        // SanDisk Engraving
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("SanDisk", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Black, letterSpacing = 2.sp)
                            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text("sansa", color = SansaTheme.NeonBlue, fontSize = 9.sp, fontWeight = FontWeight.Bold)
                                Text("e260", color = SansaTheme.LcdTextSecondary, fontSize = 8.sp, fontFamily = FontFamily.Monospace)
                            }
                        }

                        Box {
                            IconButton(onClick = { showMenu = true }, modifier = Modifier.size(36.dp)) {
                                Icon(Icons.Default.MoreVert, "Menu", tint = SansaTheme.LcdTextSecondary)
                            }
                            SansaDropdownMenu(
                                expanded = showMenu,
                                onDismiss = { showMenu = false },
                                onChangeTheme = onChangeTheme,
                                onOpenSettings = onOpenSettings,
                                onChangeVideo = { showChangeVideo = true },
                                onAddToPlaylist = { showAddToPlaylist = true },
                                onEditLyrics = { showLyricsEditor = true }
                            )
                        }
                    }

                    // Rotator Wheel & Controls
                    SansaControlsCluster(
                        diameter = 145.dp,
                        isPlaying = isPlaying,
                        wheelMode = wheelMode,
                        isShuffled = isShuffled,
                        repeatMode = repeatMode,
                        isFav = fav,
                        onModeToggle = {
                            wheelMode = if (wheelMode == SansaWheelMode.SEEK) SansaWheelMode.VOLUME else SansaWheelMode.SEEK
                            showFeedback(if (wheelMode == SansaWheelMode.SEEK) "ROTATOR: SEEK" else "ROTATOR: VOL")
                        },
                        onMenuCycle = {
                            val nextMode = when (displayMode) {
                                DisplayMode.AUDIO -> DisplayMode.VIDEO
                                DisplayMode.VIDEO -> DisplayMode.LYRICS
                                DisplayMode.LYRICS -> DisplayMode.AUDIO
                            }
                            playbackManager.setDisplayMode(nextMode)
                            showFeedback("MODE: ${nextMode.name}")
                        },
                        onToggleFav = {
                            repository.toggleFavorite(t)
                            showFeedback(if (!fav) "FAVORITE: ADDED ♥" else "FAVORITE: REMOVED")
                        },
                        onPrev = {
                            playbackManager.playPrevious()
                            showFeedback("TRACK: PREV")
                        },
                        onNext = {
                            playbackManager.playNext()
                            showFeedback("TRACK: NEXT")
                        },
                        onPlayPause = {
                            playbackManager.togglePlayPause()
                            showFeedback(if (isPlaying) "STATE: PAUSED" else "STATE: PLAYING")
                        },
                        onToggleShuffle = {
                            playbackManager.toggleShuffle()
                            showFeedback(if (!isShuffled) "SHUFFLE: ON" else "SHUFFLE: OFF")
                        },
                        onToggleRepeat = {
                            playbackManager.toggleRepeat()
                            val nextRepeat = (repeatMode + 1) % 3
                            val repMsg = if (nextRepeat == 2) "REPEAT: 1 TRACK" else if (nextRepeat == 1) "REPEAT: ALL" else "REPEAT: OFF"
                            showFeedback(repMsg)
                        },
                        onWheelRotate = { steps ->
                            handleWheelRotation(steps, wheelMode, positionMs, durationMs, playbackManager, ::showFeedback)
                        }
                    )
                }
            }
        } else {
            // Portrait Layout (Exact authentic Sansa e260 handheld geometry)
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 16.dp, vertical = 6.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.SpaceBetween
            ) {
                // Top Hardware Bar
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    IconButton(
                        onClick = onDismiss,
                        modifier = Modifier
                            .size(38.dp)
                            .clip(CircleShape)
                            .background(SansaTheme.ButtonSurface)
                            .border(1.dp, SansaTheme.ButtonBorder, CircleShape)
                    ) {
                        Icon(Icons.Default.KeyboardArrowDown, "Collapse", tint = SansaTheme.LcdTextSecondary)
                    }

                    // SanDisk Engraved Branding
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            "SanDisk",
                            color = Color.White,
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Black,
                            letterSpacing = 2.sp
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text("sansa", color = SansaTheme.NeonBlue, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                            Text("e260", color = SansaTheme.LcdTextSecondary, fontSize = 9.sp, fontFamily = FontFamily.Monospace)
                        }
                    }

                    Box {
                        IconButton(
                            onClick = { showMenu = true },
                            modifier = Modifier
                                .size(38.dp)
                                .clip(CircleShape)
                                .background(SansaTheme.ButtonSurface)
                                .border(1.dp, SansaTheme.ButtonBorder, CircleShape)
                        ) {
                            Icon(Icons.Default.MoreVert, "Menu", tint = SansaTheme.LcdTextSecondary)
                        }
                        SansaDropdownMenu(
                            expanded = showMenu,
                            onDismiss = { showMenu = false },
                            onChangeTheme = onChangeTheme,
                            onOpenSettings = onOpenSettings,
                            onChangeVideo = { showChangeVideo = true },
                            onAddToPlaylist = { showAddToPlaylist = true },
                            onEditLyrics = { showLyricsEditor = true }
                        )
                    }
                }

                // Center LCD Display
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .padding(vertical = 8.dp),
                    contentAlignment = Alignment.Center
                ) {
                    SansaLcdScreen(
                        track = t,
                        isPlaying = isPlaying,
                        displayMode = displayMode,
                        positionMs = positionMs,
                        durationMs = durationMs,
                        feedbackText = feedbackText,
                        wheelMode = wheelMode,
                        syncedLyrics = syncedLyrics,
                        plainLyrics = plainLyrics,
                        currentLyricIndex = currentLyricIndex,
                        artworkUrl = artworkUrl,
                        playbackManager = playbackManager,
                        onSeekTo = { playbackManager.seekTo(it) },
                        onEditLyrics = { showLyricsEditor = true },
                        modifier = Modifier.fillMaxSize()
                    )
                }

                // Bottom Hardware Rotator & Buttons
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 12.dp),
                    contentAlignment = Alignment.Center
                ) {
                    SansaControlsCluster(
                        diameter = 170.dp,
                        isPlaying = isPlaying,
                        wheelMode = wheelMode,
                        isShuffled = isShuffled,
                        repeatMode = repeatMode,
                        isFav = fav,
                        onModeToggle = {
                            wheelMode = if (wheelMode == SansaWheelMode.SEEK) SansaWheelMode.VOLUME else SansaWheelMode.SEEK
                            showFeedback(if (wheelMode == SansaWheelMode.SEEK) "ROTATOR: SEEK" else "ROTATOR: VOL")
                        },
                        onMenuCycle = {
                            val nextMode = when (displayMode) {
                                DisplayMode.AUDIO -> DisplayMode.VIDEO
                                DisplayMode.VIDEO -> DisplayMode.LYRICS
                                DisplayMode.LYRICS -> DisplayMode.AUDIO
                            }
                            playbackManager.setDisplayMode(nextMode)
                            showFeedback("MODE: ${nextMode.name}")
                        },
                        onToggleFav = {
                            repository.toggleFavorite(t)
                            showFeedback(if (!fav) "FAVORITE: ADDED ♥" else "FAVORITE: REMOVED")
                        },
                        onPrev = {
                            playbackManager.playPrevious()
                            showFeedback("TRACK: PREV")
                        },
                        onNext = {
                            playbackManager.playNext()
                            showFeedback("TRACK: NEXT")
                        },
                        onPlayPause = {
                            playbackManager.togglePlayPause()
                            showFeedback(if (isPlaying) "STATE: PAUSED" else "STATE: PLAYING")
                        },
                        onToggleShuffle = {
                            playbackManager.toggleShuffle()
                            showFeedback(if (!isShuffled) "SHUFFLE: ON" else "SHUFFLE: OFF")
                        },
                        onToggleRepeat = {
                            playbackManager.toggleRepeat()
                            val nextRepeat = (repeatMode + 1) % 3
                            val repMsg = if (nextRepeat == 2) "REPEAT: 1 TRACK" else if (nextRepeat == 1) "REPEAT: ALL" else "REPEAT: OFF"
                            showFeedback(repMsg)
                        },
                        onWheelRotate = { steps ->
                            handleWheelRotation(steps, wheelMode, positionMs, durationMs, playbackManager, ::showFeedback)
                        }
                    )
                }
            }
        }
    }

    if (showChangeVideo) {
        ChangeVideoLinkDialog(
            track = t,
            onDismiss = { showChangeVideo = false },
            onConfirm = { newId ->
                showChangeVideo = false
                repository.setVideo(t.id, newId)
                playbackManager.playTrack(t.copy(youtubeId = newId))
            }
        )
    }

    if (showAddToPlaylist) {
        val allPlaylists by repository.playlists.collectAsState()
        PlaylistPickerDialog(
            playlists = allPlaylists,
            onPick = { pl ->
                repository.addTrackToPlaylist(pl.id, t)
                showAddToPlaylist = false
            },
            onCreate = { name ->
                val pl = repository.addPlaylist(name)
                repository.addTrackToPlaylist(pl.id, t)
                showAddToPlaylist = false
            },
            onDismiss = { showAddToPlaylist = false }
        )
    }

    if (showLyricsEditor) {
        LyricsEditorDialog(
            track = t,
            playbackManager = playbackManager,
            onDismiss = { showLyricsEditor = false }
        )
    }
}

private fun handleWheelRotation(
    steps: Int,
    wheelMode: SansaWheelMode,
    positionMs: Long,
    durationMs: Long,
    playbackManager: PlaybackManager,
    showFeedback: (String) -> Unit
) {
    when (wheelMode) {
        SansaWheelMode.SEEK -> {
            val deltaMs = steps * 4000L
            val targetMs = (positionMs + deltaMs).coerceIn(0L, durationMs.coerceAtLeast(1000L))
            playbackManager.seekTo(targetMs)
            val sec = targetMs / 1000
            showFeedback("SEEK: %d:%02d".format(sec / 60, sec % 60))
        }
        SansaWheelMode.VOLUME -> {
            // Relative volume feedback
            val volStep = steps * 5
            showFeedback("VOL STEP: ${if (volStep > 0) "+$volStep" else "$volStep"}")
        }
    }
}

@Composable
private fun SansaControlsCluster(
    diameter: Dp,
    isPlaying: Boolean,
    wheelMode: SansaWheelMode,
    isShuffled: Boolean,
    repeatMode: Int,
    isFav: Boolean,
    onModeToggle: () -> Unit,
    onMenuCycle: () -> Unit,
    onToggleFav: () -> Unit,
    onPrev: () -> Unit,
    onNext: () -> Unit,
    onPlayPause: () -> Unit,
    onToggleShuffle: () -> Unit,
    onToggleRepeat: () -> Unit,
    onWheelRotate: (Int) -> Unit
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        // Top Row: VOL/SCRUB, MENU, FAV
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            SansaHardwareButton(
                icon = if (wheelMode == SansaWheelMode.SEEK) Icons.AutoMirrored.Filled.VolumeUp else Icons.Default.FastForward,
                label = if (wheelMode == SansaWheelMode.SEEK) "VOL" else "SCRUB",
                isActive = wheelMode == SansaWheelMode.VOLUME,
                onClick = onModeToggle
            )
            SansaHardwareButton(
                icon = Icons.Default.Menu,
                label = "MENU",
                width = 56.dp,
                onClick = onMenuCycle
            )
            SansaHardwareButton(
                icon = if (isFav) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                label = "FAV",
                isActive = isFav,
                iconTint = if (isFav) SansaTheme.NeonBlue else Color.White,
                onClick = onToggleFav
            )
        }

        // Middle Row: PREV, ROTATOR WHEEL, NEXT
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically
        ) {
            SansaHardwareButton(
                icon = Icons.Default.SkipPrevious,
                label = "PREV",
                height = 50.dp,
                onClick = onPrev
            )

            SansaRotatorWheel(
                diameter = diameter,
                isCenterActive = isPlaying,
                onRotate = onWheelRotate,
                onCenterTap = onPlayPause
            )

            SansaHardwareButton(
                icon = Icons.Default.SkipNext,
                label = "NEXT",
                height = 50.dp,
                onClick = onNext
            )
        }

        // Bottom Row: SHUFFLE, PLAY/PAUSE (Accent), REPEAT
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            SansaHardwareButton(
                icon = Icons.Default.Shuffle,
                label = "SHUFFLE",
                isActive = isShuffled,
                onClick = onToggleShuffle
            )
            SansaHardwareButton(
                icon = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                label = if (isPlaying) "PAUSE" else "PLAY",
                isAccent = true,
                width = 62.dp,
                onClick = onPlayPause
            )
            SansaHardwareButton(
                icon = if (repeatMode == 2) Icons.Default.RepeatOne else Icons.Default.Repeat,
                label = if (repeatMode == 2) "REP 1" else if (repeatMode == 1) "REP ALL" else "REPEAT",
                isActive = repeatMode > 0,
                onClick = onToggleRepeat
            )
        }
    }
}

@Composable
private fun SansaLcdScreen(
    track: MediaTrack,
    isPlaying: Boolean,
    displayMode: DisplayMode,
    positionMs: Long,
    durationMs: Long,
    feedbackText: String?,
    wheelMode: SansaWheelMode,
    syncedLyrics: List<com.antigravity.auraplayer.model.LyricLine>?,
    plainLyrics: String?,
    currentLyricIndex: Int,
    artworkUrl: String?,
    playbackManager: PlaybackManager,
    onSeekTo: (Long) -> Unit,
    onEditLyrics: () -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .shadow(12.dp, RoundedCornerShape(18.dp))
            .clip(RoundedCornerShape(18.dp))
            .background(SansaTheme.ScreenBezel)
            .border(1.dp, SansaTheme.MetallicEdge.copy(alpha = 0.35f), RoundedCornerShape(18.dp))
            .padding(8.dp)
    ) {
        // Inner Backlit Display
        Box(
            modifier = Modifier
                .fillMaxSize()
                .clip(RoundedCornerShape(12.dp))
                .background(SansaTheme.LcdBacklight)
                .border(1.dp, Color(0xFF1E3B5C).copy(alpha = 0.5f), RoundedCornerShape(12.dp))
        ) {
            // Glass Reflection
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(SansaTheme.LcdGlassReflection)
            )

            // Screen Content
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.SpaceBetween
            ) {
                // Status Bar: PLAY/PAUSE, MODE / FEEDBACK, BATTERY
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        Box(
                            Modifier.size(6.dp).background(if (isPlaying) Color.Green else Color(0xFFFF9800), CircleShape)
                        )
                        Text(
                            text = if (isPlaying) "PLAY" else "PAUSE",
                            color = SansaTheme.LcdTextCyan,
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold,
                            fontFamily = FontFamily.Monospace
                        )
                    }

                    Text(
                        text = feedbackText ?: (if (wheelMode == SansaWheelMode.SEEK) "ROTATOR: SEEK" else "ROTATOR: VOL"),
                        color = if (feedbackText != null) SansaTheme.NeonBlue else SansaTheme.LcdTextSecondary,
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Bold,
                        fontFamily = FontFamily.Monospace
                    )

                    // Battery Indicator
                    Row(horizontalArrangement = Arrangement.spacedBy(1.5.dp)) {
                        repeat(4) {
                            Box(Modifier.width(3.5.dp).height(7.dp).background(SansaTheme.LcdTextCyan))
                        }
                    }
                }

                // Center Display Mode Area
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .padding(vertical = 4.dp),
                    contentAlignment = Alignment.Center
                ) {
                    when (displayMode) {
                        DisplayMode.VIDEO -> {
                            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                                Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(8.dp))) {
                                    VideoPlayerView(playbackManager = playbackManager)
                                }
                            }
                        }
                        DisplayMode.LYRICS -> {
                            LyricsView(
                                syncedLyrics = syncedLyrics,
                                plainLyrics = plainLyrics,
                                currentLyricIndex = currentLyricIndex,
                                onSeekToTime = onSeekTo,
                                compact = true,
                                isPlaying = isPlaying,
                                track = track,
                                onAddLyrics = onEditLyrics
                            )
                        }
                        DisplayMode.AUDIO -> {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceEvenly
                            ) {
                                // Square Artwork
                                Box(
                                    modifier = Modifier
                                        .size(100.dp)
                                        .shadow(8.dp, RoundedCornerShape(8.dp))
                                        .clip(RoundedCornerShape(8.dp))
                                        .background(Color(0xFF101724))
                                        .border(1.dp, SansaTheme.NeonBlue.copy(alpha = 0.3f), RoundedCornerShape(8.dp))
                                ) {
                                    TrackArtwork(track, 100.dp, 8.dp, overrideUrl = artworkUrl)
                                }

                                // 7-band Animated Equalizer Bars
                                Column(
                                    horizontalAlignment = Alignment.Start,
                                    verticalArrangement = Arrangement.Center
                                ) {
                                    Text(
                                        "EQUALIZER",
                                        color = SansaTheme.LcdTextSecondary,
                                        fontSize = 8.sp,
                                        fontWeight = FontWeight.Bold,
                                        fontFamily = FontFamily.Monospace
                                    )
                                    Spacer(Modifier.height(4.dp))
                                    Row(
                                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                                        verticalAlignment = Alignment.Bottom,
                                        modifier = Modifier.height(56.dp)
                                    ) {
                                        for (i in 0 until 7) {
                                            RetroEqBar(isActive = isPlaying, index = i)
                                        }
                                    }
                                    Spacer(Modifier.height(4.dp))
                                    Text(
                                        text = track.genre ?: "AURA AUDIO",
                                        color = SansaTheme.LcdTextCyan,
                                        fontSize = 9.sp,
                                        fontWeight = FontWeight.SemiBold,
                                        fontFamily = FontFamily.Monospace,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }
                            }
                        }
                    }
                }

                // Track Info & Monospaced Scrubber
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        text = track.title,
                        color = SansaTheme.LcdTextPrimary,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        textAlign = TextAlign.Center
                    )
                    Text(
                        text = track.artist,
                        color = SansaTheme.LcdTextCyan,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        textAlign = TextAlign.Center
                    )

                    Spacer(Modifier.height(6.dp))

                    // Scrubber Bar
                    val progress = if (durationMs > 0) (positionMs.toFloat() / durationMs.toFloat()).coerceIn(0f, 1f) else 0f
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(5.dp)
                            .clip(RoundedCornerShape(3.dp))
                            .background(SansaTheme.LcdProgressTrack)
                    ) {
                        Box(
                            modifier = Modifier
                                .fillMaxHeight()
                                .fillMaxWidth(progress)
                                .background(SansaTheme.NeonBlueGradient)
                        )
                    }

                    Spacer(Modifier.height(4.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        val posSec = positionMs / 1000
                        val durSec = durationMs / 1000
                        Text(
                            "%d:%02d".format(posSec / 60, posSec % 60),
                            color = SansaTheme.LcdTextCyan,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            fontFamily = FontFamily.Monospace
                        )
                        Text(
                            "%d:%02d".format(durSec / 60, durSec % 60),
                            color = SansaTheme.LcdTextSecondary,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            fontFamily = FontFamily.Monospace
                        )
                    }
                }
            }
        }
    }
}

/** 7-band retro LED equalizer bar */
@Composable
private fun RetroEqBar(isActive: Boolean, index: Int) {
    val infiniteTransition = rememberInfiniteTransition(label = "eq$index")
    val animFactor by infiniteTransition.animateFloat(
        initialValue = 0.2f,
        targetValue = 0.95f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 280 + index * 90, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "eqAnim$index"
    )

    val level = if (isActive) animFactor else 0.15f

    Column(
        verticalArrangement = Arrangement.spacedBy(1.5.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        for (barIdx in 0 until 8) {
            val lit = (7 - barIdx) < (level * 8).toInt()
            val color = when {
                barIdx < 2 -> Color.Red
                barIdx < 4 -> Color.Yellow
                else -> SansaTheme.LcdTextCyan
            }
            Box(
                modifier = Modifier
                    .width(6.dp)
                    .height(4.5.dp)
                    .background(if (lit) color else color.copy(alpha = 0.15f))
            )
        }
    }
}

/** Hardware Beveled Push-Button */
@Composable
private fun SansaHardwareButton(
    icon: ImageVector,
    label: String,
    modifier: Modifier = Modifier,
    isAccent: Boolean = false,
    isActive: Boolean = false,
    iconTint: Color = Color.White,
    width: Dp = 48.dp,
    height: Dp = 42.dp,
    onClick: () -> Unit
) {
    val view = LocalView.current
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (isPressed) 0.91f else 1.0f,
        animationSpec = spring(dampingRatio = 0.65f, stiffness = 500f),
        label = "btnScale"
    )

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier.scale(scale)
    ) {
        Box(
            modifier = Modifier
                .size(width = width, height = height)
                .clip(RoundedCornerShape(10.dp))
                .background(
                    if (isAccent) SansaTheme.NeonBlue.copy(alpha = 0.85f)
                    else if (isActive) SansaTheme.NeonBlue.copy(alpha = 0.35f)
                    else SansaTheme.ButtonSurface
                )
                .border(
                    width = 1.dp,
                    color = if (isAccent || isActive) SansaTheme.NeonBlue.copy(alpha = 0.8f) else SansaTheme.ButtonBorder,
                    shape = RoundedCornerShape(10.dp)
                )
                .clickable(interactionSource = interactionSource, indication = null) {
                    view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    onClick()
                },
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = label,
                tint = if (isAccent) Color.Black else if (isActive) SansaTheme.NeonBlue else iconTint,
                modifier = Modifier.size(20.dp)
            )
        }
        Spacer(Modifier.height(3.dp))
        Text(
            text = label,
            color = if (isActive) SansaTheme.NeonBlue else SansaTheme.LcdTextSecondary,
            fontSize = 7.5.sp,
            fontWeight = FontWeight.Bold,
            fontFamily = FontFamily.Monospace,
            letterSpacing = 0.5.sp
        )
    }
}

@Composable
private fun SansaDropdownMenu(
    expanded: Boolean,
    onDismiss: () -> Unit,
    onChangeTheme: () -> Unit,
    onOpenSettings: () -> Unit,
    onChangeVideo: () -> Unit,
    onAddToPlaylist: () -> Unit,
    onEditLyrics: () -> Unit
) {
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss) {
        DropdownMenuItem(
            text = { Text("Switch to Modern Glass Theme") },
            leadingIcon = { Icon(Icons.Default.PhoneAndroid, null) },
            onClick = { onDismiss(); onChangeTheme() }
        )
        HorizontalDivider()
        DropdownMenuItem(
            text = { Text("Add to Playlist…") },
            leadingIcon = { Icon(Icons.Default.PlaylistAdd, null) },
            onClick = { onDismiss(); onAddToPlaylist() }
        )
        DropdownMenuItem(
            text = { Text("Change Video Link…") },
            leadingIcon = { Icon(Icons.Default.Link, null) },
            onClick = { onDismiss(); onChangeVideo() }
        )
        DropdownMenuItem(
            text = { Text("Add / Edit Lyrics…") },
            leadingIcon = { Icon(Icons.Default.Lyrics, null) },
            onClick = { onDismiss(); onEditLyrics() }
        )
        HorizontalDivider()
        DropdownMenuItem(
            text = { Text("Player Settings…") },
            leadingIcon = { Icon(Icons.Default.Settings, null) },
            onClick = { onDismiss(); onOpenSettings() }
        )
    }
}
