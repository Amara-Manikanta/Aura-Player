package com.antigravity.auraplayer.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.antigravity.auraplayer.service.PlaybackManager
import com.antigravity.auraplayer.ui.theme.BackdropTop
import com.antigravity.auraplayer.ui.theme.NeonPurple
import com.antigravity.auraplayer.ui.theme.TextPrimary
import com.antigravity.auraplayer.ui.theme.TextSecondary

@Composable
fun SleepTimerDialog(
    playbackManager: PlaybackManager,
    onDismiss: () -> Unit
) {
    val currentTimer by playbackManager.sleepTimerMinutes.collectAsState()
    val remainingSec by playbackManager.sleepTimerRemainingSeconds.collectAsState()

    val options = listOf(
        15 to "15 minutes",
        30 to "30 minutes",
        45 to "45 minutes",
        60 to "1 hour",
        -1 to "End of current song"
    )

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Bedtime, null, tint = NeonPurple)
                Spacer(Modifier.width(8.dp))
                Text("Sleep Timer", fontWeight = FontWeight.Bold)
            }
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (remainingSec != null && remainingSec!! > 0) {
                    val m = remainingSec!! / 60
                    val s = remainingSec!! % 60
                    Text(
                        text = "Time remaining: %d:%02d".format(m, s),
                        color = NeonPurple,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 14.sp,
                        modifier = Modifier.padding(bottom = 6.dp)
                    )
                } else if (currentTimer == -1) {
                    Text(
                        text = "Playback will stop after current song ends",
                        color = NeonPurple,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 14.sp,
                        modifier = Modifier.padding(bottom = 6.dp)
                    )
                }

                options.forEach { (mins, label) ->
                    val isSelected = currentTimer == mins
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(10.dp))
                            .background(if (isSelected) NeonPurple.copy(alpha = 0.2f) else Color.Transparent)
                            .clickable {
                                playbackManager.setSleepTimer(mins)
                                onDismiss()
                            }
                            .padding(horizontal = 12.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(label, color = if (isSelected) Color.White else TextSecondary, fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal)
                        if (isSelected) {
                            Icon(Icons.Default.Check, null, tint = NeonPurple, modifier = Modifier.size(18.dp))
                        }
                    }
                }

                if (currentTimer != null) {
                    Spacer(Modifier.height(4.dp))
                    TextButton(
                        onClick = {
                            playbackManager.cancelSleepTimer()
                            onDismiss()
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text("Turn Off Timer", color = Color(0xFFFF6B81), fontWeight = FontWeight.Bold)
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("Close", color = TextPrimary)
            }
        }
    )
}
