package com.antigravity.auraplayer.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.antigravity.auraplayer.data.PlaylistRepository
import com.antigravity.auraplayer.service.PlatformImportService
import com.antigravity.auraplayer.service.PlatformType
import com.antigravity.auraplayer.ui.theme.*
import kotlinx.coroutines.launch

@Composable
fun ImportPlaylistDialog(
    repository: PlaylistRepository,
    targetPlaylistId: String? = null,
    targetPlaylistName: String? = null,
    onDismiss: () -> Unit,
    onImportSuccess: (playlistId: String?, trackCount: Int) -> Unit
) {
    val clipboardManager = LocalClipboardManager.current
    val scope = rememberCoroutineScope()

    var inputText by remember { mutableStateOf("") }
    var customPlaylistName by remember { mutableStateOf("") }
    var importIntoCurrent by remember { mutableStateOf(targetPlaylistId != null) }
    var isLoading by remember { mutableStateOf(false) }
    var statusMessage by remember { mutableStateOf("") }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val detectedPlatform = remember(inputText) {
        PlatformImportService.detectPlatform(inputText)
    }

    val platforms = remember {
        listOf(
            PlatformType.YOUTUBE,
            PlatformType.SPOTIFY,
            PlatformType.JIOSAAVN,
            PlatformType.GAANA,
            PlatformType.AMAZON_MUSIC,
            PlatformType.TEXT
        )
    }

    AlertDialog(
        onDismissRequest = { if (!isLoading) onDismiss() },
        modifier = Modifier
            .fillMaxWidth(0.96f)
            .padding(vertical = 12.dp),
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(38.dp)
                        .background(NeonPurple.copy(alpha = 0.2f), CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = Icons.Default.CloudDownload,
                        contentDescription = null,
                        tint = NeonPurple,
                        modifier = Modifier.size(22.dp)
                    )
                }
                Spacer(modifier = Modifier.width(12.dp))
                Column {
                    Text(
                        text = "Import Music",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        color = TextPrimary
                    )
                    Text(
                        text = "YouTube, Spotify, JioSaavn, Gaana, Amazon, Text",
                        style = MaterialTheme.typography.bodySmall,
                        color = TextSecondary,
                        fontSize = 11.sp
                    )
                }
            }
        },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                // Platform pills row
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    platforms.forEach { platform ->
                        val isMatched = detectedPlatform == platform
                        val chipColor = Color(platform.badgeColor)
                        Surface(
                            shape = RoundedCornerShape(20.dp),
                            color = if (isMatched) chipColor.copy(alpha = 0.25f) else SurfaceCard,
                            border = androidx.compose.foundation.BorderStroke(
                                1.dp,
                                if (isMatched) chipColor else GlassBorder
                            ),
                            modifier = Modifier.clickable {
                                if (inputText.isBlank()) {
                                    when (platform) {
                                        PlatformType.YOUTUBE -> inputText = "https://www.youtube.com/playlist?list="
                                        PlatformType.SPOTIFY -> inputText = "https://open.spotify.com/playlist/"
                                        PlatformType.JIOSAAVN -> inputText = "https://www.jiosaavn.com/featured/"
                                        PlatformType.GAANA -> inputText = "https://gaana.com/song/"
                                        PlatformType.AMAZON_MUSIC -> inputText = "https://music.amazon.in/"
                                        PlatformType.TEXT -> inputText = "Song Title 1 - Artist Name\nSong Title 2 - Artist Name"
                                        else -> {}
                                    }
                                }
                            }
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(8.dp)
                                        .background(chipColor, CircleShape)
                                )
                                Spacer(modifier = Modifier.width(6.dp))
                                Text(
                                    text = platform.displayName,
                                    fontSize = 12.sp,
                                    fontWeight = if (isMatched) FontWeight.Bold else FontWeight.Normal,
                                    color = if (isMatched) TextPrimary else TextSecondary
                                )
                            }
                        }
                    }
                }

                // Input Box with Paste Button
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Paste Link or Song List",
                            style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.Medium,
                            color = TextSecondary
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            TextButton(
                                onClick = {
                                    val clip = clipboardManager.getText()?.text
                                    if (!clip.isNullOrBlank()) {
                                        inputText = clip.trim()
                                        errorMessage = null
                                    }
                                },
                                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp),
                                modifier = Modifier.height(28.dp)
                            ) {
                                Icon(Icons.Default.ContentPaste, contentDescription = null, modifier = Modifier.size(14.dp), tint = NeonPurple)
                                Spacer(Modifier.width(4.dp))
                                Text("Paste", fontSize = 12.sp, color = NeonPurple)
                            }
                            if (inputText.isNotBlank()) {
                                TextButton(
                                    onClick = { inputText = ""; errorMessage = null },
                                    contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp),
                                    modifier = Modifier.height(28.dp)
                                ) {
                                    Text("Clear", fontSize = 12.sp, color = TextTertiary)
                                }
                            }
                        }
                    }

                    OutlinedTextField(
                        value = inputText,
                        onValueChange = {
                            inputText = it
                            errorMessage = null
                        },
                        placeholder = {
                            Text(
                                "Paste YouTube/Spotify link, or lines of songs (e.g. Title - Artist)...",
                                fontSize = 13.sp,
                                color = TextTertiary
                            )
                        },
                        minLines = 3,
                        maxLines = 6,
                        modifier = Modifier.fillMaxWidth(),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = NeonPurple,
                            unfocusedBorderColor = GlassBorder,
                            focusedTextColor = TextPrimary,
                            unfocusedTextColor = TextPrimary
                        ),
                        shape = RoundedCornerShape(12.dp)
                    )
                }

                // Live Detection Status Badge
                AnimatedVisibility(visible = detectedPlatform != null && inputText.isNotBlank()) {
                    detectedPlatform?.let { p ->
                        Surface(
                            shape = RoundedCornerShape(8.dp),
                            color = Color(p.badgeColor).copy(alpha = 0.15f),
                            border = androidx.compose.foundation.BorderStroke(1.dp, Color(p.badgeColor).copy(alpha = 0.4f)),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Row(
                                modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    imageVector = Icons.Default.CheckCircle,
                                    contentDescription = null,
                                    tint = Color(p.badgeColor),
                                    modifier = Modifier.size(16.dp)
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                                Text(
                                    text = "Ready to import from ${p.displayName}",
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.Medium,
                                    color = TextPrimary
                                )
                            }
                        }
                    }
                }

                // Destination options (if called from a playlist)
                if (targetPlaylistId != null) {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(
                            text = "Destination",
                            style = MaterialTheme.typography.bodySmall,
                            color = TextSecondary
                        )
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { importIntoCurrent = true }
                                .padding(vertical = 4.dp)
                        ) {
                            RadioButton(
                                selected = importIntoCurrent,
                                onClick = { importIntoCurrent = true }
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = "Add into \"${targetPlaylistName ?: "Current Playlist"}\"",
                                color = TextPrimary,
                                fontSize = 14.sp
                            )
                        }
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { importIntoCurrent = false }
                                .padding(vertical = 4.dp)
                        ) {
                            RadioButton(
                                selected = !importIntoCurrent,
                                onClick = { importIntoCurrent = false }
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = "Create as New Playlist",
                                color = TextPrimary,
                                fontSize = 14.sp
                            )
                        }
                    }
                }

                // Optional Custom Playlist Name (when creating a new playlist)
                if (!importIntoCurrent) {
                    OutlinedTextField(
                        value = customPlaylistName,
                        onValueChange = { customPlaylistName = it },
                        label = { Text("Playlist Name (Optional)") },
                        placeholder = { Text("Auto-detect from source") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = NeonPurple,
                            unfocusedBorderColor = GlassBorder,
                            focusedTextColor = TextPrimary,
                            unfocusedTextColor = TextPrimary
                        ),
                        shape = RoundedCornerShape(12.dp)
                    )
                }

                // Error Message Banner
                errorMessage?.let { err ->
                    Surface(
                        shape = RoundedCornerShape(8.dp),
                        color = DangerRed.copy(alpha = 0.15f),
                        border = androidx.compose.foundation.BorderStroke(1.dp, DangerRed.copy(alpha = 0.5f)),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier.padding(10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(Icons.Default.ErrorOutline, contentDescription = null, tint = DangerRed, modifier = Modifier.size(18.dp))
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(err, color = DangerRed, fontSize = 12.sp)
                        }
                    }
                }

                // Loading Indicator with Status
                AnimatedVisibility(visible = isLoading) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.Center
                    ) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            strokeWidth = 2.dp,
                            color = NeonPurple
                        )
                        Spacer(modifier = Modifier.width(12.dp))
                        Text(
                            text = statusMessage.ifBlank { "Extracting songs..." },
                            color = TextSecondary,
                            fontSize = 13.sp
                        )
                    }
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    if (inputText.isBlank()) return@Button
                    isLoading = true
                    errorMessage = null
                    val plat = detectedPlatform?.displayName ?: "source"
                    statusMessage = "Connecting to $plat..."

                    scope.launch {
                        val result = PlatformImportService.parseLinkOrText(inputText)
                        result.onSuccess { imported ->
                            statusMessage = "Found ${imported.tracks.size} tracks! Saving..."
                            if (importIntoCurrent && targetPlaylistId != null) {
                                val added = repository.addTracksToPlaylist(targetPlaylistId, imported.tracks)
                                isLoading = false
                                onImportSuccess(targetPlaylistId, added)
                                onDismiss()
                            } else {
                                val finalName = customPlaylistName.trim().ifEmpty { imported.name }
                                val created = repository.createPlaylistWithTracks(finalName, imported.tracks)
                                isLoading = false
                                onImportSuccess(created.id, imported.tracks.size)
                                onDismiss()
                            }
                        }.onFailure { ex ->
                            isLoading = false
                            errorMessage = ex.message ?: "Failed to import tracks. Please check link or text."
                        }
                    }
                },
                enabled = !isLoading && inputText.isNotBlank(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = NeonPurple,
                    contentColor = BackgroundDark,
                    disabledContainerColor = SurfaceCard,
                    disabledContentColor = TextTertiary
                )
            ) {
                Icon(Icons.Default.FileDownload, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(6.dp))
                Text("Import Tracks", fontWeight = FontWeight.SemiBold)
            }
        },
        dismissButton = {
            TextButton(
                onClick = onDismiss,
                enabled = !isLoading
            ) {
                Text("Cancel", color = TextSecondary)
            }
        }
    )
}
