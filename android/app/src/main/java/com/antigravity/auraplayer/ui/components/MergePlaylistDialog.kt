package com.antigravity.auraplayer.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.antigravity.auraplayer.model.Playlist
import com.antigravity.auraplayer.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MergePlaylistDialog(
    sourcePlaylist: Playlist,
    allPlaylists: List<Playlist>,
    onDismiss: () -> Unit,
    onMergeIntoExisting: (targetId: String, skipDuplicates: Boolean, deleteSource: Boolean) -> Unit,
    onCreateNewMerged: (name: String, sourceIds: List<String>, skipDuplicates: Boolean, deleteSources: Boolean) -> Unit
) {
    val otherPlaylists = remember(allPlaylists, sourcePlaylist) {
        allPlaylists.filter { it.id != sourcePlaylist.id }
    }

    var isCreateNew by remember { mutableStateOf(false) }
    var selectedTargetId by remember {
        mutableStateOf(otherPlaylists.firstOrNull { !it.isBuiltIn }?.id ?: otherPlaylists.firstOrNull()?.id ?: "")
    }
    val selectedAdditionalIds = remember { mutableStateListOf<String>() }
    var newPlaylistName by remember { mutableStateOf("${sourcePlaylist.name} + Merged") }
    var skipDuplicates by remember { mutableStateOf(true) }
    var deleteSource by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        modifier = Modifier.fillMaxWidth(0.95f),
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.MergeType, contentDescription = null, tint = NeonPurple)
                Spacer(modifier = Modifier.width(8.dp))
                Text("Merge Playlists", style = MaterialTheme.typography.titleLarge)
            }
        },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                // Source Card
                Surface(
                    shape = RoundedCornerShape(10.dp),
                    color = SurfaceDark,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Default.MusicNote, contentDescription = null, tint = NeonPurple)
                        Spacer(modifier = Modifier.width(10.dp))
                        Column {
                            Text(sourcePlaylist.name, fontWeight = FontWeight.Bold, color = TextPrimary)
                            Text("${sourcePlaylist.tracks.size} tracks", style = MaterialTheme.typography.labelSmall, color = TextSecondary)
                        }
                    }
                }

                // Mode Tabs
                SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                    SegmentedButton(
                        selected = !isCreateNew,
                        onClick = { isCreateNew = false },
                        shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2)
                    ) {
                        Text("Into Existing", style = MaterialTheme.typography.labelSmall)
                    }
                    SegmentedButton(
                        selected = isCreateNew,
                        onClick = { isCreateNew = true },
                        shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2)
                    ) {
                        Text("Create New", style = MaterialTheme.typography.labelSmall)
                    }
                }

                if (!isCreateNew) {
                    // Pick target
                    Text("Select Target Playlist:", style = MaterialTheme.typography.labelSmall, color = TextSecondary)
                    var expanded by remember { mutableStateOf(false) }
                    val target = otherPlaylists.firstOrNull { it.id == selectedTargetId }

                    ExposedDropdownMenuBox(
                        expanded = expanded,
                        onExpandedChange = { expanded = !expanded }
                    ) {
                        OutlinedTextField(
                            value = target?.let { "${it.name} (${it.tracks.size} tracks)" } ?: "No playlist available",
                            onValueChange = {},
                            readOnly = true,
                            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                            modifier = Modifier
                                .fillMaxWidth()
                                .menuAnchor()
                        )
                        ExposedDropdownMenu(
                            expanded = expanded,
                            onDismissRequest = { expanded = false }
                        ) {
                            otherPlaylists.forEach { pl ->
                                DropdownMenuItem(
                                    text = { Text("${pl.name} (${pl.tracks.size} tracks)") },
                                    onClick = {
                                        selectedTargetId = pl.id
                                        expanded = false
                                    }
                                )
                            }
                        }
                    }
                } else {
                    // New playlist name & other playlists to combine
                    OutlinedTextField(
                        value = newPlaylistName,
                        onValueChange = { newPlaylistName = it },
                        label = { Text("New Playlist Name") },
                        modifier = Modifier.fillMaxWidth()
                    )

                    Text("Select playlists to combine with source:", style = MaterialTheme.typography.labelSmall, color = TextSecondary)
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(max = 120.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        items(otherPlaylists) { pl ->
                            val isChecked = selectedAdditionalIds.contains(pl.id)
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(RoundedCornerShape(6.dp))
                                    .background(if (isChecked) NeonPurple.copy(alpha = 0.15f) else SurfaceDark)
                                    .clickable {
                                        if (isChecked) selectedAdditionalIds.remove(pl.id)
                                        else selectedAdditionalIds.add(pl.id)
                                    }
                                    .padding(8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Checkbox(
                                    checked = isChecked,
                                    onCheckedChange = {
                                        if (it) selectedAdditionalIds.add(pl.id) else selectedAdditionalIds.remove(pl.id)
                                    }
                                )
                                Spacer(modifier = Modifier.width(6.dp))
                                Text(pl.name, color = TextPrimary, style = MaterialTheme.typography.bodyMedium)
                                Spacer(modifier = Modifier.weight(1f))
                                Text("${pl.tracks.size} tracks", color = TextTertiary, style = MaterialTheme.typography.labelSmall)
                            }
                        }
                    }
                }

                // Options
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Checkbox(
                        checked = skipDuplicates,
                        onCheckedChange = { skipDuplicates = it }
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Skip duplicate songs (by title & artist)", style = MaterialTheme.typography.bodyMedium)
                }

                if (!sourcePlaylist.isBuiltIn) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Checkbox(
                            checked = deleteSource,
                            onCheckedChange = { deleteSource = it }
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            if (!isCreateNew) "Delete \"${sourcePlaylist.name}\" after merge"
                            else "Delete merged playlists after creation",
                            style = MaterialTheme.typography.bodyMedium,
                            color = if (deleteSource) DangerRed else TextPrimary
                        )
                    }
                }
            }
        },
        confirmButton = {
            Button(
                onClick = {
                    if (!isCreateNew) {
                        if (selectedTargetId.isNotEmpty()) {
                            onMergeIntoExisting(selectedTargetId, skipDuplicates, deleteSource)
                        }
                    } else {
                        if (newPlaylistName.isNotBlank()) {
                            val allIds = listOf(sourcePlaylist.id) + selectedAdditionalIds
                            onCreateNewMerged(newPlaylistName.trim(), allIds, skipDuplicates, deleteSource)
                        }
                    }
                },
                colors = ButtonDefaults.buttonColors(containerColor = NeonPurple)
            ) {
                Text("Merge Playlists")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel", color = TextSecondary)
            }
        }
    )
}
