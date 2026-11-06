package com.antigravity.auraplayer.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.antigravity.auraplayer.service.PlaybackManager
import com.antigravity.auraplayer.ui.theme.NeonPurple
import com.antigravity.auraplayer.ui.theme.TextPrimary
import com.antigravity.auraplayer.ui.theme.TextSecondary
import kotlinx.coroutines.delay

@Composable
fun VideoFullScreenView(
    playbackManager: PlaybackManager,
    onDismiss: () -> Unit,
    onEnterPiP: () -> Unit,
    modifier: Modifier = Modifier
) {
    val track by playbackManager.currentTrack.collectAsState()
    val isPlaying by playbackManager.isPlaying.collectAsState()
    val positionMs by playbackManager.currentPosition.collectAsState()
    val durationMs by playbackManager.duration.collectAsState()
    val isShuffled by playbackManager.isShuffled.collectAsState()

    var showControls by remember { mutableStateOf(true) }
    var hideTrigger by remember { mutableIntStateOf(0) }

    fun poke() {
        showControls = true
        hideTrigger++
    }

    LaunchedEffect(hideTrigger, isPlaying) {
        if (isPlaying && showControls) {
            delay(3500)
            showControls = false
        }
    }

    val t = track ?: return

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Color.Black)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null
            ) {
                showControls = !showControls
                if (showControls) poke()
            }
    ) {
        // Video Player Area
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(16f / 9f)
            ) {
                VideoPlayerView(playbackManager = playbackManager)
            }
        }

        // Overlay Controls
        AnimatedVisibility(
            visible = showControls,
            enter = fadeIn(),
            exit = fadeOut()
        ) {
            Box(modifier = Modifier.fillMaxSize()) {
                // Top Overlay Bar
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .align(Alignment.TopCenter)
                        .background(
                            Brush.verticalGradient(
                                colors = listOf(Color.Black.copy(alpha = 0.75f), Color.Transparent)
                            )
                        )
                        .statusBarsPadding()
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        IconButton(onClick = onDismiss) {
                            Icon(Icons.Default.Close, contentDescription = "Close Full Screen", tint = Color.White)
                        }

                        Column(
                            modifier = Modifier
                                .weight(1f)
                                .padding(horizontal = 12.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Text(
                                text = t.title,
                                color = TextPrimary,
                                fontWeight = FontWeight.Bold,
                                fontSize = 14.sp,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                            Text(
                                text = t.artist,
                                color = TextSecondary,
                                fontSize = 12.sp,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }

                        IconButton(onClick = onEnterPiP) {
                            Icon(Icons.Default.PictureInPictureAlt, contentDescription = "PiP", tint = Color.White)
                        }
                    }
                }

                // Bottom Overlay Bar
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .align(Alignment.BottomCenter)
                        .background(
                            Brush.verticalGradient(
                                colors = listOf(Color.Transparent, Color.Black.copy(alpha = 0.85f))
                            )
                        )
                        .navigationBarsPadding()
                        .padding(horizontal = 24.dp, vertical = 14.dp)
                ) {
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        // Scrubber Slider
                        val progress = if (durationMs > 0) (positionMs.toFloat() / durationMs.toFloat()).coerceIn(0f, 1f) else 0f
                        Slider(
                            value = progress,
                            onValueChange = {
                                poke()
                                playbackManager.seekTo((it * durationMs).toLong())
                            },
                            colors = SliderDefaults.colors(
                                thumbColor = Color.White,
                                activeTrackColor = NeonPurple,
                                inactiveTrackColor = Color.White.copy(alpha = 0.25f)
                            )
                        )

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            val posSec = positionMs / 1000
                            val durSec = durationMs / 1000
                            Text(
                                "%d:%02d".format(posSec / 60, posSec % 60),
                                color = TextSecondary,
                                fontSize = 11.sp
                            )
                            Text(
                                "%d:%02d".format(durSec / 60, durSec % 60),
                                color = TextSecondary,
                                fontSize = 11.sp
                            )
                        }

                        Spacer(Modifier.height(8.dp))

                        // Controls Row
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceEvenly,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            IconButton(onClick = {
                                poke()
                                playbackManager.toggleShuffle()
                            }) {
                                Icon(
                                    Icons.Default.Shuffle,
                                    contentDescription = "Shuffle",
                                    tint = if (isShuffled) NeonPurple else TextSecondary
                                )
                            }

                            IconButton(
                                onClick = {
                                    poke()
                                    playbackManager.playPrevious()
                                },
                                modifier = Modifier.size(46.dp)
                            ) {
                                Icon(Icons.Default.SkipPrevious, "Previous", tint = Color.White, modifier = Modifier.size(34.dp))
                            }

                            Box(
                                modifier = Modifier
                                    .size(56.dp)
                                    .clip(CircleShape)
                                    .background(Color.White)
                                    .clickable {
                                        poke()
                                        playbackManager.togglePlayPause()
                                    },
                                contentAlignment = Alignment.Center
                            ) {
                                Icon(
                                    imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                                    contentDescription = "Play/Pause",
                                    tint = Color.Black,
                                    modifier = Modifier.size(32.dp)
                                )
                            }

                            IconButton(
                                onClick = {
                                    poke()
                                    playbackManager.playNext()
                                },
                                modifier = Modifier.size(46.dp)
                            ) {
                                Icon(Icons.Default.SkipNext, "Next", tint = Color.White, modifier = Modifier.size(34.dp))
                            }

                            IconButton(onClick = {
                                poke()
                                playbackManager.toggleRepeat()
                            }) {
                                Icon(
                                    Icons.Default.Repeat,
                                    contentDescription = "Repeat",
                                    tint = TextSecondary
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
