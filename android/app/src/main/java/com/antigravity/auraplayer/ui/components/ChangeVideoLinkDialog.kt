package com.antigravity.auraplayer.ui.components

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.antigravity.auraplayer.model.MediaTrack
import com.antigravity.auraplayer.service.YouTubeService
import com.antigravity.auraplayer.ui.theme.*

@Composable
fun ChangeVideoLinkDialog(
    track: MediaTrack,
    onDismiss: () -> Unit,
    onConfirm: (newVideoId: String) -> Unit
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    var urlOrId by remember { mutableStateOf(track.youtubeId?.let { "https://www.youtube.com/watch?v=$it" } ?: "") }
    var errorText by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Link, contentDescription = null, tint = NeonPurple)
                Spacer(modifier = Modifier.width(8.dp))
                Text("Change Video Link")
            }
        },
        text = {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text(
                    text = "Track: ${track.title} - ${track.artist}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = TextSecondary
                )
                OutlinedTextField(
                    value = urlOrId,
                    onValueChange = {
                        urlOrId = it
                        errorText = null
                    },
                    label = { Text("YouTube link or video ID") },
                    placeholder = { Text("Paste a YouTube link or video ID") },
                    singleLine = true,
                    trailingIcon = {
                        // ⓧ clears the field; when empty, paste a link copied from Discover / YouTube
                        if (urlOrId.isNotEmpty()) {
                            IconButton(onClick = { urlOrId = ""; errorText = null }) {
                                Icon(Icons.Default.Cancel, contentDescription = "Clear")
                            }
                        } else {
                            IconButton(onClick = { pasteFromClipboard(context)?.let { urlOrId = it } }) {
                                Icon(Icons.Default.ContentPaste, contentDescription = "Paste", tint = NeonPurple)
                            }
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                    isError = errorText != null
                )
                if (errorText != null) {
                    Text(
                        text = errorText ?: "",
                        style = MaterialTheme.typography.labelSmall,
                        color = DangerRed
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    val extracted = YouTubeService.extractVideoId(urlOrId)
                    if (extracted != null) {
                        onConfirm(extracted)
                    } else {
                        errorText = "Invalid YouTube video link or ID."
                    }
                },
                colors = ButtonDefaults.buttonColors(containerColor = NeonPurple)
            ) {
                Text("Update Video")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel", color = TextSecondary)
            }
        }
    )
}
