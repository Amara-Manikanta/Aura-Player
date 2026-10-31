package com.antigravity.auraplayer.ui.components

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.antigravity.auraplayer.model.LyricLine
import com.antigravity.auraplayer.ui.theme.*

@Composable
fun LyricsView(
    syncedLyrics: List<LyricLine>?,
    plainLyrics: String?,
    currentLyricIndex: Int,
    onSeekToTime: (Long) -> Unit,
    modifier: Modifier = Modifier,
    /** Smaller text, for the strip under the video */
    compact: Boolean = false,
    isPlaying: Boolean = false,
    onAddLyrics: (() -> Unit)? = null
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = if (compact) 12.dp else 20.dp),
        contentAlignment = Alignment.Center
    ) {
        if (!syncedLyrics.isNullOrEmpty()) {
            val listState = rememberLazyListState()

            // When current line changes, scroll it towards the center
            LaunchedEffect(currentLyricIndex) {
                if (currentLyricIndex in syncedLyrics.indices) {
                    val target = (currentLyricIndex - (if (compact) 1 else 2)).coerceAtLeast(0)
                    listState.animateScrollToItem(target)
                }
            }

            LazyColumn(
                state = listState,
                modifier = Modifier
                    .fillMaxSize()
                    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                    .drawWithContent {
                        drawContent()
                        drawRect(
                            brush = Brush.verticalGradient(
                                0.0f to Color.Transparent,
                                0.08f to Color.Black,
                                0.92f to Color.Black,
                                1.0f to Color.Transparent
                            ),
                            blendMode = BlendMode.DstIn
                        )
                    },
                contentPadding = PaddingValues(vertical = if (compact) 24.dp else 120.dp),
                verticalArrangement = Arrangement.spacedBy(if (compact) 10.dp else 18.dp)
            ) {
                itemsIndexed(syncedLyrics) { index, line ->
                    val isActive = index == currentLyricIndex
                    val isPast = currentLyricIndex >= 0 && index < currentLyricIndex

                    val scale by animateFloatAsState(
                        targetValue = if (isActive) (if (compact) 1.02f else 1.03f) else (if (compact) 0.98f else 0.96f),
                        animationSpec = spring(dampingRatio = 0.72f, stiffness = Spring.StiffnessMediumLow),
                        label = "scale"
                    )
                    val alpha by animateFloatAsState(
                        targetValue = if (isActive) 1f else if (isPast) 0.60f else 0.35f,
                        animationSpec = spring(dampingRatio = 0.78f, stiffness = Spring.StiffnessMediumLow),
                        label = "alpha"
                    )

                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .graphicsLayer {
                                scaleX = scale
                                scaleY = scale
                                transformOrigin = TransformOrigin(0.5f, 0.5f)
                            }
                            .then(
                                if (isActive) {
                                    Modifier
                                        .background(
                                            brush = Brush.linearGradient(
                                                listOf(
                                                    Color.White.copy(alpha = 0.18f),
                                                    NeonPurple.copy(alpha = 0.15f),
                                                    Color.White.copy(alpha = 0.06f)
                                                )
                                            ),
                                            shape = RoundedCornerShape(if (compact) 14.dp else 18.dp)
                                        )
                                        .border(
                                            width = 1.2.dp,
                                            brush = Brush.linearGradient(
                                                listOf(
                                                    Color.White.copy(alpha = 0.55f),
                                                    NeonPurple.copy(alpha = 0.35f),
                                                    Color.White.copy(alpha = 0.08f)
                                                )
                                            ),
                                            shape = RoundedCornerShape(if (compact) 14.dp else 18.dp)
                                        )
                                } else Modifier
                            )
                            .clip(RoundedCornerShape(if (compact) 14.dp else 18.dp))
                            .clickable { onSeekToTime(line.timeMs) }
                            .padding(
                                horizontal = if (compact) 12.dp else 18.dp,
                                vertical = if (compact) 6.dp else 10.dp
                            ),
                        contentAlignment = Alignment.Center
                    ) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.Center
                        ) {
                            if (isActive && isPlaying) {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                                    modifier = Modifier.padding(end = 8.dp)
                                ) {
                                    Icon(
                                        imageVector = Icons.Default.MusicNote,
                                        contentDescription = null,
                                        tint = NeonPink,
                                        modifier = Modifier.size(if (compact) 14.dp else 18.dp)
                                    )
                                    Box(
                                        modifier = Modifier
                                            .size(5.dp)
                                            .background(NeonPink, CircleShape)
                                    )
                                }
                            }
                            Text(
                                text = line.text,
                                style = MaterialTheme.typography.headlineMedium.copy(
                                    fontSize = if (compact) 17.sp else 24.sp,
                                    lineHeight = if (compact) 23.sp else 32.sp
                                ),
                                color = if (isActive) Color.White else Color.White.copy(alpha = alpha),
                                fontWeight = if (isActive) FontWeight.Bold else FontWeight.Medium,
                                textAlign = TextAlign.Center
                            )
                        }
                    }
                }
            }
        } else if (!plainLyrics.isNullOrEmpty()) {
            val scrollState = rememberScrollState()
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(scrollState)
                    .padding(vertical = 40.dp, horizontal = 16.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = plainLyrics,
                    style = MaterialTheme.typography.bodyLarge.copy(fontSize = 17.sp, lineHeight = 28.sp),
                    color = Color.White.copy(alpha = 0.85f),
                    textAlign = TextAlign.Center
                )
                if (onAddLyrics != null) {
                    Spacer(modifier = Modifier.height(24.dp))
                    Button(
                        onClick = onAddLyrics,
                        colors = ButtonDefaults.buttonColors(containerColor = NeonPurple),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Icon(Icons.Default.Add, null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Edit or Sync Lyrics")
                    }
                }
            }
        } else {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Icon(
                    imageVector = Icons.Default.MusicNote,
                    contentDescription = null,
                    tint = TextTertiary,
                    modifier = Modifier.size(48.dp)
                )
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = "No Lyrics Available",
                    style = MaterialTheme.typography.titleMedium,
                    color = TextSecondary
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Lyrics could not be found or song is instrumental.",
                    style = MaterialTheme.typography.bodySmall,
                    color = TextTertiary,
                    textAlign = TextAlign.Center
                )
                if (onAddLyrics != null) {
                    Spacer(modifier = Modifier.height(16.dp))
                    Button(
                        onClick = onAddLyrics,
                        colors = ButtonDefaults.buttonColors(containerColor = NeonPurple),
                        shape = RoundedCornerShape(12.dp)
                    ) {
                        Icon(Icons.Default.Add, null, modifier = Modifier.size(16.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Add Lyrics")
                    }
                }
            }
        }
    }
}
