package com.antigravity.auraplayer.ui.components

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.antigravity.auraplayer.model.MediaTrack
import com.antigravity.auraplayer.service.ArtistPhotoService
import com.antigravity.auraplayer.service.TrackArtworkService
import com.antigravity.auraplayer.service.YouTubeSearchResult
import com.antigravity.auraplayer.ui.theme.*

/**
 * The app's backdrop: a violet → indigo gradient with soft, blurred light blobs, so the glass
 * panels on top have something to show through (same as the iPhone app).
 */
@Composable
fun AuraBackground(modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxSize()
            .background(Brush.linearGradient(listOf(BackdropTop, BackdropMid, BackdropBottom)))
    ) {
        // Soft glows (radial gradients fade out on their own; a blur would stop at the box edge)
        Glow(Color(0x99E38CF2), 520.dp, x = 120.dp, y = (-180).dp)
        Glow(Color(0x806FB7FF), 460.dp, x = (-200).dp, y = 230.dp)
        Glow(Color(0x8CA77BFF), 560.dp, x = 60.dp, y = 520.dp)
    }
}

@Composable
private fun Glow(color: Color, size: Dp, x: Dp, y: Dp) {
    Box(
        Modifier.size(size).offset(x = x, y = y)
            .background(Brush.radialGradient(listOf(color, color.copy(alpha = 0f))), CircleShape)
    )
}

/** Frosted glass panel: translucent white with a light rim */
fun Modifier.glass(shape: Shape = RoundedCornerShape(18.dp), alpha: Float = 0.12f): Modifier = this
    .clip(shape)
    .background(Color.White.copy(alpha = alpha), shape)
    .border(
        1.dp,
        Brush.linearGradient(listOf(Color.White.copy(alpha = 0.45f), Color.White.copy(alpha = 0.08f))),
        shape
    )

/** Square cover: the album cover found by TrackArtworkService, otherwise the video thumbnail */
@Composable
fun TrackArtwork(track: MediaTrack, size: Dp, corner: Dp = 10.dp, overrideUrl: String? = null) {
    var cover by remember(track.id) { mutableStateOf(TrackArtworkService.cachedCover(track)) }
    LaunchedEffect(track.id) {
        if (cover == null) cover = TrackArtworkService.cover(track)
    }
    val url = overrideUrl ?: cover ?: track.effectiveThumbnailURL
    Box(
        Modifier.size(size).clip(RoundedCornerShape(corner)).background(SurfaceDark),
        contentAlignment = Alignment.Center
    ) {
        Icon(Icons.Default.MusicNote, contentDescription = null, tint = TextTertiary, modifier = Modifier.size(size * 0.38f))
        if (url != null) {
            AsyncImage(model = url, contentDescription = null, modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        }
    }
}

/** Round singer photo (Deezer), with the first letter while loading or when there's none */
@Composable
fun ArtistAvatar(name: String, size: Dp, fallbackUrl: String? = null) {
    var photo by remember(name) { mutableStateOf<String?>(null) }
    var done by remember(name) { mutableStateOf(false) }
    LaunchedEffect(name) {
        photo = ArtistPhotoService.photoUrl(name)
        done = true
    }
    Box(
        Modifier.size(size).clip(CircleShape)
            .background(Brush.linearGradient(listOf(NeonIndigo, NeonPink))),
        contentAlignment = Alignment.Center
    ) {
        Text(name.take(1).uppercase(), color = Color.White, fontWeight = FontWeight.Bold, fontSize = (size.value * 0.36f).sp)
        val url = photo ?: if (done) fallbackUrl else null
        if (url != null) {
            AsyncImage(model = url, contentDescription = null, modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        }
    }
}

/** Glass segmented control: "Top Picks | New for You | New Releases" */
@Composable
fun SegmentedTabs(options: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().glass(RoundedCornerShape(50)).padding(4.dp)) {
        options.forEachIndexed { i, label ->
            Box(
                Modifier.weight(1f).clip(RoundedCornerShape(50))
                    .background(if (i == selected) Color.White.copy(alpha = 0.25f) else Color.Transparent)
                    .clickable { onSelect(i) }
                    .padding(vertical = 9.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(label, color = if (i == selected) TextPrimary else TextSecondary,
                    fontWeight = if (i == selected) FontWeight.Bold else FontWeight.Medium, fontSize = 13.sp, maxLines = 1)
            }
        }
    }
}

/** Search field with an ⓧ clear button */
@Composable
fun GlassSearchField(value: String, onValueChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier) {
    TextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = { Text(placeholder, color = TextTertiary, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        leadingIcon = { Icon(Icons.Default.Search, contentDescription = null, tint = TextTertiary) },
        trailingIcon = {
            if (value.isNotEmpty()) IconButton(onClick = { onValueChange("") }) {
                Icon(Icons.Default.Cancel, contentDescription = "Clear", tint = TextTertiary)
            }
        },
        singleLine = true,
        colors = TextFieldDefaults.colors(
            focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent,
            focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent,
            focusedTextColor = TextPrimary, unfocusedTextColor = TextPrimary, cursorColor = NeonPurple
        ),
        modifier = modifier.fillMaxWidth().glass(RoundedCornerShape(16.dp))
    )
}

fun copyToClipboard(context: Context, text: String, toast: String = "Link copied") {
    val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    cm.setPrimaryClip(ClipData.newPlainText("YouTube link", text))
    Toast.makeText(context, toast, Toast.LENGTH_SHORT).show()
}

fun pasteFromClipboard(context: Context): String? {
    val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    return cm.primaryClip?.getItemAt(0)?.text?.toString()?.trim()
}

fun formatViews(n: Long): String = when {
    n >= 1_000_000 -> "%.1fM views".format(n / 1_000_000.0)
    n >= 1_000 -> "%.0fK views".format(n / 1_000.0)
    else -> "$n views"
}

fun formatTime(sec: Double): String = "%d:%02d".format(sec.toInt() / 60, sec.toInt() % 60)

/** "1:05" / "65" → 65 seconds */
fun parseTime(text: String): Double? {
    val t = text.trim()
    if (t.isEmpty()) return null
    val parts = t.split(":").map { it.trim().toIntOrNull() ?: return null }
    return parts.fold(0.0) { acc, p -> acc * 60 + p }
}

/** Set a song's start and end time (mm:ss); empty = from the beginning / to the end */
@Composable
fun TrimDialog(track: MediaTrack, onSave: (Double?, Double?) -> Unit, onDismiss: () -> Unit) {
    var start by remember { mutableStateOf(track.startTime?.let(::formatTime) ?: "") }
    var end by remember { mutableStateOf(track.endTime?.let(::formatTime) ?: "") }
    var error by remember { mutableStateOf<String?>(null) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Start & End Time") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("${track.title} • ${track.formattedDuration}", color = TextSecondary, maxLines = 2)
                OutlinedTextField(start, { start = it; error = null }, label = { Text("Start (m:ss) — empty = beginning") },
                    singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text))
                OutlinedTextField(end, { end = it; error = null }, label = { Text("End (m:ss) — empty = end of song") },
                    singleLine = true)
                error?.let { Text(it, color = DangerRed) }
            }
        },
        confirmButton = {
            Button(onClick = {
                val s = if (start.isBlank()) null else parseTime(start)
                val e = if (end.isBlank()) null else parseTime(end)
                when {
                    (start.isNotBlank() && s == null) || (end.isNotBlank() && e == null) -> error = "Use minutes:seconds, like 1:05"
                    s != null && e != null && e <= s -> error = "The end must be after the start"
                    else -> onSave(s, e)
                }
            }) { Text("Save") }
        },
        dismissButton = {
            Row {
                if (track.trimLabel != null) TextButton(onClick = { onSave(null, null) }) { Text("Clear") }
                TextButton(onClick = onDismiss) { Text("Cancel") }
            }
        }
    )
}

/** A suggested / new song: video thumbnail, title, channel, why it's here, views and age, ⋯ menu */
@Composable
fun DiscoverRow(
    video: YouTubeSearchResult,
    reason: String? = null,
    views: Long = 0,
    uploadedAgo: String = "",
    isCurrent: Boolean,
    isPlaying: Boolean,
    onPlay: () -> Unit,
    onAdd: () -> Unit,
    onNotInterested: (() -> Unit)? = null
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    var menu by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().clickable { onPlay() }.padding(horizontal = 16.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier.size(width = 128.dp, height = 72.dp).clip(RoundedCornerShape(10.dp))
                .border(if (isCurrent) 2.dp else 0.dp, if (isCurrent) NeonPurple else Color.Transparent, RoundedCornerShape(10.dp))
        ) {
            AsyncImage(model = video.thumbnailUrl, contentDescription = null, modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            if (isCurrent) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.4f)), contentAlignment = Alignment.Center) {
                Icon(if (isPlaying) Icons.Default.GraphicEq else Icons.Default.Pause, contentDescription = null, tint = Color.White)
            }
            Text(
                video.formattedDuration, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.align(Alignment.BottomEnd).padding(4.dp)
                    .background(Color.Black.copy(alpha = 0.75f), RoundedCornerShape(3.dp)).padding(horizontal = 4.dp, vertical = 1.dp)
            )
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(video.title, color = if (isCurrent) NeonPurple else TextPrimary, fontWeight = FontWeight.SemiBold,
                fontSize = 14.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(video.channel, color = TextSecondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (reason != null) Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.AutoAwesome, contentDescription = null, tint = NeonPurple, modifier = Modifier.size(11.dp))
                Spacer(Modifier.width(3.dp))
                Text(reason, color = NeonPurple, fontSize = 11.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            val stats = listOf(if (views > 0) formatViews(views) else "", uploadedAgo).filter { it.isNotEmpty() }
            if (stats.isNotEmpty()) Text(stats.joinToString(" • "), color = TextTertiary, fontSize = 11.sp, maxLines = 1)
        }
        Box {
            IconButton(onClick = { menu = true }) { Icon(Icons.Default.MoreHoriz, contentDescription = "More", tint = TextSecondary) }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text("Play") }, leadingIcon = { Icon(Icons.Default.PlayArrow, null) },
                    onClick = { menu = false; onPlay() })
                DropdownMenuItem(text = { Text("Add to Playlist") }, leadingIcon = { Icon(Icons.Default.PlaylistAdd, null) },
                    onClick = { menu = false; onAdd() })
                // e.g. to fix a song in a playlist that plays a fake video: copy here, paste in Change Video Link
                DropdownMenuItem(text = { Text("Copy YouTube Link") }, leadingIcon = { Icon(Icons.Default.ContentCopy, null) },
                    onClick = { menu = false; copyToClipboard(context, video.url) })
                if (onNotInterested != null) DropdownMenuItem(
                    text = { Text("Not Interested", color = DangerRed) },
                    leadingIcon = { Icon(Icons.Default.ThumbDown, null, tint = DangerRed) },
                    onClick = { menu = false; onNotInterested() })
            }
        }
    }
}
