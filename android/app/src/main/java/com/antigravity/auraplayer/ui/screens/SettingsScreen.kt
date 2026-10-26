package com.antigravity.auraplayer.ui.screens

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.antigravity.auraplayer.data.PlaylistRepository
import com.antigravity.auraplayer.service.PlaybackManager
import com.antigravity.auraplayer.ui.components.glass
import com.antigravity.auraplayer.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(repository: PlaylistRepository, playbackManager: PlaybackManager, onBack: () -> Unit) {
    val context = LocalContext.current
    val playlists by repository.playlists.collectAsState()
    var language by remember { mutableStateOf(playbackManager.preferredLanguage ?: "none") }
    var confirmRestore by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings", fontWeight = FontWeight.Bold) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent)
            )
        },
        containerColor = Color.Transparent
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Section("PREFERRED SONG LANGUAGE")
            Text("Indian film songs play in this language when a version exists (songs played from a language playlist like \"Hindi Music\" always use that playlist's language).",
                color = TextSecondary, fontSize = 13.sp)
            val langs = listOf("none" to "Original", "telugu" to "Telugu", "hindi" to "Hindi", "tamil" to "Tamil",
                "kannada" to "Kannada", "malayalam" to "Malayalam", "punjabi" to "Punjabi")
            langs.chunked(4).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    row.forEach { (key, label) ->
                        val on = language == key
                        Text(label, color = if (on) BackdropBottom else TextPrimary, fontWeight = FontWeight.SemiBold, fontSize = 13.sp,
                            modifier = Modifier
                                .then(if (on) Modifier.background(Color.White, RoundedCornerShape(50)) else Modifier.glass(RoundedCornerShape(50)))
                                .clickable {
                                    language = key
                                    playbackManager.preferredLanguage = key.takeIf { it != "none" }
                                }
                                .padding(horizontal = 14.dp, vertical = 8.dp))
                    }
                }
            }

            Section("LIBRARY")
            Row(Modifier.fillMaxWidth().glass(RoundedCornerShape(14.dp)).padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.LibraryMusic, null, tint = TextPrimary)
                Spacer(Modifier.width(12.dp))
                Text("Your library", color = TextPrimary, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                Text("${playlists.size} playlists • %,d songs".format(repository.allUniqueTracks.size), color = TextSecondary, fontSize = 13.sp)
            }
            Row(
                Modifier.fillMaxWidth().glass(RoundedCornerShape(14.dp)).clickable { confirmRestore = true }.padding(14.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Default.Restore, null, tint = Color(0xFFFFB86B))
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text("Restore Mac Library", color = Color(0xFFFFB86B), fontWeight = FontWeight.SemiBold)
                    Text("Start again from the playlists, play counts and dates bundled from your Mac", color = TextSecondary, fontSize = 12.sp)
                }
            }
            Text("Apple Music can't be read on Android, so play counts and Recently Added come from the Mac library bundled with the app; plays here are counted on top.",
                color = TextTertiary, fontSize = 12.sp)

            Section("ABOUT")
            Text("Aura Player for Android • same features as the Mac and iPhone apps", color = TextSecondary, fontSize = 13.sp)
            Spacer(Modifier.height(120.dp))
        }
    }

    if (confirmRestore) {
        AlertDialog(
            onDismissRequest = { confirmRestore = false },
            title = { Text("Restore Mac Library?") },
            text = { Text("Playlists and changes made on this phone will be replaced by the library bundled from your Mac.") },
            confirmButton = {
                Button(onClick = {
                    repository.resetToMacLibrary()
                    confirmRestore = false
                    Toast.makeText(context, "Mac library restored", Toast.LENGTH_SHORT).show()
                }, colors = ButtonDefaults.buttonColors(containerColor = DangerRed)) { Text("Restore") }
            },
            dismissButton = { TextButton(onClick = { confirmRestore = false }) { Text("Cancel") } }
        )
    }
}

@Composable
private fun Section(title: String) {
    Text(title, color = TextTertiary, fontWeight = FontWeight.Bold, fontSize = 12.sp, letterSpacing = 1.sp,
        modifier = Modifier.padding(top = 14.dp, start = 4.dp))
}
