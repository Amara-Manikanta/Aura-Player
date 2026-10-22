package com.antigravity.auraplayer.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.antigravity.auraplayer.model.LyricLine
import com.antigravity.auraplayer.ui.theme.*
import androidx.compose.runtime.getValue
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.TransformOrigin

@Composable
fun LyricsView(
    syncedLyrics: List<LyricLine>?,
    plainLyrics: String?,
    currentLyricIndex: Int,
    onSeekToTime: (Long) -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 24.dp),
        contentAlignment = Alignment.Center
    ) {
        if (!syncedLyrics.isNullOrEmpty()) {
            val listState = rememberLazyListState()

            LaunchedEffect(currentLyricIndex) {
                if (currentLyricIndex in syncedLyrics.indices) {
                    val target = (currentLyricIndex - 2).coerceAtLeast(0)
                    listState.animateScrollToItem(target)
                }
            }

            LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(vertical = 120.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp)
            ) {
                itemsIndexed(syncedLyrics) { index, line ->
                    val isActive = index == currentLyricIndex
                    val isPast = index < currentLyricIndex
                    
                    val scale by androidx.compose.animation.core.animateFloatAsState(
                        targetValue = if (isActive) 1.05f else 1f,
                        label = "scale"
                    )
                    val alpha by androidx.compose.animation.core.animateFloatAsState(
                        targetValue = if (isActive) 1f else if (isPast) 0.5f else 0.3f,
                        label = "alpha"
                    )
                    
                    Text(
                        text = line.text,
                        style = MaterialTheme.typography.headlineMedium.copy(
                            fontSize = 28.sp,
                            lineHeight = 36.sp
                        ),
                        color = NeonPink.copy(alpha = alpha),
                        fontWeight = if (isActive) FontWeight.Bold else FontWeight.Medium,
                        textAlign = TextAlign.Start,
                        modifier = Modifier
                            .fillMaxWidth()
                            .graphicsLayer {
                                scaleX = scale
                                scaleY = scale
                                transformOrigin = TransformOrigin(0f, 0.5f)
                            }
                            .clickable { onSeekToTime(line.timeMs) }
                            .padding(vertical = 4.dp)
                    )
                }
            }
        } else if (!plainLyrics.isNullOrEmpty()) {
            val scrollState = rememberScrollState()
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(scrollState)
                    .padding(vertical = 40.dp)
            ) {
                Text(
                    text = plainLyrics,
                    style = MaterialTheme.typography.bodyLarge.copy(lineHeight = 28.sp),
                    color = TextSecondary,
                    textAlign = TextAlign.Start
                )
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
                    text = "Enjoy the music!",
                    style = MaterialTheme.typography.bodyMedium,
                    color = TextTertiary
                )
            }
        }
    }
}
