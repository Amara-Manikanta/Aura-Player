package com.antigravity.auraplayer.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.antigravity.auraplayer.model.MediaTrack
import com.antigravity.auraplayer.service.CustomLyricsStore
import com.antigravity.auraplayer.service.PlaybackManager
import com.antigravity.auraplayer.ui.theme.*
import kotlinx.coroutines.launch

private enum class EditorTab { WRITE, SYNC }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LyricsEditorDialog(
    track: MediaTrack,
    playbackManager: PlaybackManager,
    onDismiss: () -> Unit
) {
    val clipboardManager = LocalClipboardManager.current
    var tab by remember { mutableStateOf(EditorTab.WRITE) }
    var text by remember { mutableStateOf("") }
    var times by remember { mutableStateOf<List<Long?>>(emptyList()) }
    var selectedIndex by remember { mutableIntStateOf(0) }
    var hadCustom by remember { mutableStateOf(false) }

    val isPlaying by playbackManager.isPlaying.collectAsState()
    val position by playbackManager.currentPosition.collectAsState()
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()

    // Parse lines from text
    val lines = remember(text) {
        text.lines().map { it.trim() }.filter { it.isNotEmpty() }
    }

    // Load existing lyrics on appear
    LaunchedEffect(track.id) {
        playbackManager.holdForLyricsEditor = true
        val existing = CustomLyricsStore.getEntry(track.title, track.artist)
        if (existing != null && existing.lines.isNotEmpty()) {
            hadCustom = true
            text = existing.lines.joinToString("\n")
            times = existing.timesMs
        } else {
            val plain = playbackManager.plainLyrics.value
            val synced = playbackManager.syncedLyrics.value
            if (!synced.isNullOrEmpty()) {
                text = synced.joinToString("\n") { it.text }
                times = synced.map { it.timeMs }
            } else if (!plain.isNullOrBlank()) {
                text = plain
                times = emptyList()
            }
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            playbackManager.holdForLyricsEditor = false
        }
    }

    fun prepareSync() {
        if (times.size != lines.size) {
            val newTimes = MutableList<Long?>(lines.size) { null }
            for (i in 0 until minOf(times.size, lines.size)) {
                newTimes[i] = times[i]
            }
            times = newTimes
        }
        val firstUnset = times.indexOfFirst { it == null }
        selectedIndex = if (firstUnset >= 0) firstUnset else 0
    }

    fun formatTime(ms: Long): String {
        val s = (ms / 1000).toInt()
        val m = s / 60
        val sec = s % 60
        return "%d:%02d".format(m, sec)
    }

    fun markCurrentLineTime() {
        if (lines.isEmpty()) return
        val currentMs = position
        val updated = times.toMutableList()
        if (selectedIndex in updated.indices) {
            updated[selectedIndex] = currentMs
            times = updated
            if (selectedIndex + 1 < lines.size) {
                selectedIndex += 1
                scope.launch {
                    listState.animateScrollToItem((selectedIndex - 1).coerceAtLeast(0))
                }
            }
        }
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth(0.95f)
                .fillMaxHeight(0.92f)
                .clip(RoundedCornerShape(24.dp)),
            color = SurfaceDark
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(20.dp)
            ) {
                // Header
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = "Edit Lyrics",
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold,
                            color = TextPrimary
                        )
                        Text(
                            text = "${track.title} • ${track.artist}",
                            style = MaterialTheme.typography.bodySmall,
                            color = TextSecondary,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                    }

                    // Mode Toggle (Write vs Sync)
                    Row(
                        modifier = Modifier
                            .background(Color.White.copy(alpha = 0.08f), RoundedCornerShape(12.dp))
                            .padding(4.dp)
                    ) {
                        Surface(
                            shape = RoundedCornerShape(8.dp),
                            color = if (tab == EditorTab.WRITE) NeonPurple else Color.Transparent,
                            modifier = Modifier.clickable { tab = EditorTab.WRITE }
                        ) {
                            Text(
                                "Write",
                                color = Color.White,
                                fontWeight = FontWeight.SemiBold,
                                fontSize = 13.sp,
                                modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp)
                            )
                        }
                        Surface(
                            shape = RoundedCornerShape(8.dp),
                            color = if (tab == EditorTab.SYNC) NeonPurple else Color.Transparent,
                            modifier = Modifier.clickable {
                                prepareSync()
                                tab = EditorTab.SYNC
                            }
                        ) {
                            Text(
                                "Sync",
                                color = Color.White,
                                fontWeight = FontWeight.SemiBold,
                                fontSize = 13.sp,
                                modifier = Modifier.padding(horizontal = 14.dp, vertical = 6.dp)
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))

                // Body content based on tab
                Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                    if (tab == EditorTab.WRITE) {
                        Column(modifier = Modifier.fillMaxSize()) {
                            OutlinedTextField(
                                value = text,
                                onValueChange = { text = it },
                                placeholder = {
                                    Text(
                                        "Paste or type lyrics here, one line per lyric…\n[mm:ss] LRC timestamps are automatically supported.",
                                        color = TextTertiary,
                                        fontSize = 14.sp
                                    )
                                },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .weight(1f),
                                textStyle = LocalTextStyle.current.copy(
                                    color = TextPrimary,
                                    fontSize = 15.sp,
                                    lineHeight = 22.sp
                                ),
                                colors = OutlinedTextFieldDefaults.colors(
                                    focusedBorderColor = NeonPurple,
                                    unfocusedBorderColor = Color.White.copy(alpha = 0.15f),
                                    focusedContainerColor = Color.Black.copy(alpha = 0.3f),
                                    unfocusedContainerColor = Color.Black.copy(alpha = 0.2f)
                                ),
                                shape = RoundedCornerShape(14.dp)
                            )

                            Spacer(modifier = Modifier.height(10.dp))

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(10.dp)
                            ) {
                                Button(
                                    onClick = {
                                        val clip = clipboardManager.getText()?.text ?: ""
                                        if (clip.isNotEmpty()) {
                                            text = clip
                                        }
                                    },
                                    colors = ButtonDefaults.buttonColors(containerColor = Color.White.copy(alpha = 0.12f)),
                                    shape = RoundedCornerShape(10.dp)
                                ) {
                                    Icon(Icons.Default.ContentPaste, null, modifier = Modifier.size(16.dp))
                                    Spacer(Modifier.width(6.dp))
                                    Text("Paste")
                                }

                                Button(
                                    onClick = {
                                        clipboardManager.setText(AnnotatedString(text))
                                    },
                                    enabled = text.isNotBlank(),
                                    colors = ButtonDefaults.buttonColors(containerColor = Color.White.copy(alpha = 0.12f)),
                                    shape = RoundedCornerShape(10.dp)
                                ) {
                                    Icon(Icons.Default.ContentCopy, null, modifier = Modifier.size(16.dp))
                                    Spacer(Modifier.width(6.dp))
                                    Text("Copy")
                                }
                            }
                        }
                    } else {
                        // SYNC Tab
                        Column(modifier = Modifier.fillMaxSize()) {
                            // Player scrub & action bar
                            Surface(
                                color = Color.White.copy(alpha = 0.06f),
                                shape = RoundedCornerShape(16.dp),
                                modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp)
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth().padding(12.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        IconButton(
                                            onClick = {
                                                val back = (position - 5000L).coerceAtLeast(0L)
                                                playbackManager.seekTo(back)
                                            }
                                        ) {
                                            Icon(Icons.Default.Replay5, "Rewind 5s", tint = TextPrimary)
                                        }
                                        IconButton(
                                            onClick = { playbackManager.togglePlayPause() }
                                        ) {
                                            Icon(
                                                if (isPlaying) Icons.Default.PauseCircleFilled else Icons.Default.PlayCircleFilled,
                                                "Play/Pause",
                                                tint = NeonPurple,
                                                modifier = Modifier.size(36.dp)
                                            )
                                        }
                                        IconButton(
                                            onClick = {
                                                val fwd = position + 5000L
                                                playbackManager.seekTo(fwd)
                                            }
                                        ) {
                                            Icon(Icons.Default.Forward5, "Forward 5s", tint = TextPrimary)
                                        }
                                    }

                                    Text(
                                        text = formatTime(position),
                                        style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.Bold,
                                        color = NeonPink
                                    )
                                }
                            }

                            // Big Tap-to-Sync Target Button
                            Button(
                                onClick = { markCurrentLineTime() },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(56.dp),
                                shape = RoundedCornerShape(16.dp),
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = NeonPurple
                                )
                            ) {
                                Icon(Icons.Default.TouchApp, null, modifier = Modifier.size(24.dp))
                                Spacer(Modifier.width(8.dp))
                                Text(
                                    if (selectedIndex in lines.indices) "Tap as: \"${lines[selectedIndex].take(25)}…\" starts" else "All Lines Synced!",
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 16.sp,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }

                            Spacer(modifier = Modifier.height(12.dp))

                            // Sync Lines List
                            LazyColumn(
                                state = listState,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .weight(1f)
                                    .clip(RoundedCornerShape(14.dp))
                                    .background(Color.Black.copy(alpha = 0.25f)),
                                contentPadding = PaddingValues(10.dp),
                                verticalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                itemsIndexed(lines) { index, lineText ->
                                    val isSelected = index == selectedIndex
                                    val lineTime = if (index < times.size) times[index] else null

                                    Surface(
                                        color = if (isSelected) NeonPurple.copy(alpha = 0.25f) else Color.Transparent,
                                        shape = RoundedCornerShape(10.dp),
                                        border = if (isSelected) androidx.compose.foundation.BorderStroke(1.dp, NeonPurple) else null,
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clickable { selectedIndex = index }
                                    ) {
                                        Row(
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .padding(horizontal = 12.dp, vertical = 8.dp),
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            Text(
                                                text = if (lineTime != null) formatTime(lineTime) else "--:--",
                                                color = if (lineTime != null) NeonPink else TextTertiary,
                                                fontSize = 12.sp,
                                                fontWeight = FontWeight.Bold,
                                                modifier = Modifier.width(44.dp)
                                            )
                                            Text(
                                                text = lineText,
                                                color = if (isSelected) Color.White else TextPrimary.copy(alpha = 0.8f),
                                                fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                                                fontSize = 14.sp,
                                                modifier = Modifier.weight(1f)
                                            )
                                            if (lineTime != null) {
                                                IconButton(
                                                    onClick = {
                                                        val updated = times.toMutableList()
                                                        if (index in updated.indices) {
                                                            updated[index] = null
                                                            times = updated
                                                        }
                                                    },
                                                    modifier = Modifier.size(24.dp)
                                                ) {
                                                    Icon(Icons.Default.Close, "Clear Time", tint = TextTertiary, modifier = Modifier.size(16.dp))
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))

                // Footer Buttons
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    if (hadCustom) {
                        TextButton(
                            onClick = {
                                CustomLyricsStore.removeLyrics(track.title, track.artist)
                                playbackManager.reloadLyrics()
                                onDismiss()
                            },
                            colors = ButtonDefaults.textButtonColors(contentColor = Color(0xFFFF5C5C))
                        ) {
                            Icon(Icons.Default.DeleteOutline, null, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(4.dp))
                            Text("Remove My Lyrics")
                        }
                    } else {
                        Spacer(Modifier.width(1.dp))
                    }

                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TextButton(onClick = onDismiss) {
                            Text("Cancel", color = TextSecondary)
                        }
                        Button(
                            onClick = {
                                CustomLyricsStore.saveLyrics(track.title, track.artist, lines, times)
                                playbackManager.reloadLyrics()
                                onDismiss()
                            },
                            enabled = lines.isNotEmpty(),
                            colors = ButtonDefaults.buttonColors(containerColor = NeonPurple),
                            shape = RoundedCornerShape(12.dp)
                        ) {
                            Text("Save", fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        }
    }
}
