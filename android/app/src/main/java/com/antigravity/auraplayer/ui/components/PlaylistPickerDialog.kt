package com.antigravity.auraplayer.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.QueueMusic
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.antigravity.auraplayer.model.Playlist
import com.antigravity.auraplayer.ui.theme.NeonPurple
import com.antigravity.auraplayer.ui.theme.TextSecondary

@Composable
fun PlaylistPickerDialog(
    playlists: List<Playlist>,
    onPick: (Playlist) -> Unit,
    onCreate: (String) -> Unit,
    onDismiss: () -> Unit
) {
    var newName by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add to Playlist") },
        text = {
            Column {
                LazyColumn(modifier = Modifier.heightIn(max = 280.dp)) {
                    itemsIndexed(playlists, key = { _, p -> p.id }) { _, pl ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(8.dp))
                                .clickable { onPick(pl) }
                                .padding(vertical = 10.dp, horizontal = 4.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                if (pl.isBuiltIn) Icons.Default.Favorite else Icons.Default.QueueMusic,
                                contentDescription = null,
                                tint = NeonPurple
                            )
                            Spacer(Modifier.width(10.dp))
                            Text(pl.name, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text("${pl.tracks.size}", color = TextSecondary, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = newName,
                    onValueChange = { newName = it },
                    placeholder = { Text("New playlist name") },
                    singleLine = true,
                    trailingIcon = {
                        IconButton(onClick = { onCreate(newName) }, enabled = newName.isNotBlank()) {
                            Icon(Icons.Default.Add, contentDescription = "Create playlist")
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } }
    )
}
