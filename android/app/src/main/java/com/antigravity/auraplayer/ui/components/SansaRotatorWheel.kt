package com.antigravity.auraplayer.ui.components

import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.antigravity.auraplayer.ui.theme.SansaTheme
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

enum class SansaWheelMode(val title: String) {
    SEEK("Scrub Time"),
    VOLUME("Volume")
}

/**
 * SanDisk Sansa e260 iconic rotary click-wheel.
 * Features:
 *  - Outer ambient neon electric blue glow ring
 *  - Grooved machining texture & 16 tactile grip notches
 *  - Angular touch tracking with mechanical haptic ticks every 14 degrees
 *  - Center metallic SELECT / ACTION button
 */
@Composable
fun SansaRotatorWheel(
    diameter: Dp = 180.dp,
    isCenterActive: Boolean = false,
    hapticsEnabled: Boolean = true,
    onRotate: (steps: Int) -> Unit,
    onCenterTap: () -> Unit,
    modifier: Modifier = Modifier
) {
    val view = LocalView.current
    var rotationAngle by remember { mutableFloatStateOf(0f) }
    var previousTouchAngle by remember { mutableStateOf<Float?>(null) }
    var accumulatedDegrees by remember { mutableFloatStateOf(0f) }
    var isTouching by remember { mutableStateOf(false) }

    val tickStepDegrees = 14.0f

    val centerInteractionSource = remember { MutableInteractionSource() }
    val isCenterPressed by centerInteractionSource.collectIsPressedAsState()
    val centerScale by animateFloatAsState(
        targetValue = if (isCenterPressed) 0.93f else 1.0f,
        animationSpec = spring(dampingRatio = 0.7f, stiffness = 400f),
        label = "centerScale"
    )

    Box(
        modifier = modifier
            .size(diameter + 24.dp)
            .pointerInput(diameter) {
                detectDragGestures(
                    onDragStart = { offset ->
                        val centerX = size.width / 2f
                        val centerY = size.height / 2f
                        val dx = offset.x - centerX
                        val dy = offset.y - centerY
                        val dist = sqrt(dx * dx + dy * dy)
                        val innerRadius = (diameter.toPx() * 0.22f)
                        if (dist > innerRadius) {
                            isTouching = true
                            previousTouchAngle = Math.toDegrees(atan2(dy.toDouble(), dx.toDouble())).toFloat()
                        }
                    },
                    onDragEnd = {
                        isTouching = false
                        previousTouchAngle = null
                    },
                    onDragCancel = {
                        isTouching = false
                        previousTouchAngle = null
                    },
                    onDrag = { change, _ ->
                        val centerX = size.width / 2f
                        val centerY = size.height / 2f
                        val dx = change.position.x - centerX
                        val dy = change.position.y - centerY
                        val dist = sqrt(dx * dx + dy * dy)
                        val innerRadius = (diameter.toPx() * 0.22f)

                        if (dist > innerRadius) {
                            val currentAngle = Math.toDegrees(atan2(dy.toDouble(), dx.toDouble())).toFloat()
                            val prev = previousTouchAngle
                            if (prev != null) {
                                var diff = currentAngle - prev
                                if (diff > 180f) diff -= 360f
                                if (diff < -180f) diff += 360f

                                rotationAngle += diff
                                accumulatedDegrees += diff

                                if (kotlin.math.abs(accumulatedDegrees) >= tickStepDegrees) {
                                    val steps = (accumulatedDegrees / tickStepDegrees).toInt()
                                    accumulatedDegrees -= steps * tickStepDegrees
                                    if (hapticsEnabled) {
                                        view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                                    }
                                    onRotate(steps)
                                }
                            }
                            previousTouchAngle = currentAngle
                        } else {
                            previousTouchAngle = null
                        }
                    }
                )
            },
        contentAlignment = Alignment.Center
    ) {
        // 1. Ambient Outer Neon Blue Glow Ring
        Box(
            modifier = Modifier
                .size(diameter)
                .shadow(
                    elevation = if (isTouching) 20.dp else 12.dp,
                    shape = CircleShape,
                    ambientColor = SansaTheme.NeonBlue,
                    spotColor = SansaTheme.NeonBlue
                )
                .border(width = 5.dp, brush = SansaTheme.NeonBlueGradient, shape = CircleShape)
        )

        // 2. Beveled Dark Wheel Housing Ring
        Box(
            modifier = Modifier
                .size(diameter - 8.dp)
                .clip(CircleShape)
                .background(
                    Brush.radialGradient(
                        colors = listOf(
                            Color(0xFF222634),
                            Color(0xFF161822),
                            Color(0xFF0E1017)
                        )
                    )
                )
                .border(1.dp, Color.White.copy(alpha = 0.12f), CircleShape)
        )

        // 3. Rotating Grooved Wheel Texture & Grip Notches
        Box(
            modifier = Modifier
                .size(diameter - 12.dp)
                .rotate(rotationAngle),
            contentAlignment = Alignment.Center
        ) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val cx = size.width / 2f
                val cy = size.height / 2f
                val radius = size.width / 2f

                // Concentric machining micro-grooves
                for (i in 0 until 4) {
                    val r = radius * (0.55f + i * 0.1f)
                    drawCircle(
                        color = Color.White.copy(alpha = 0.04f),
                        radius = r,
                        center = Offset(cx, cy),
                        style = Stroke(width = 1f)
                    )
                }

                // 16 Radial Grip Notches around the wheel
                for (i in 0 until 16) {
                    val angleDeg = i * 22.5f
                    val angleRad = Math.toRadians(angleDeg.toDouble())
                    val notchDist = radius * 0.76f
                    val notchX = cx + (notchDist * sin(angleRad)).toFloat()
                    val notchY = cy - (notchDist * cos(angleRad)).toFloat()

                    drawCircle(
                        color = Color.White.copy(alpha = 0.35f),
                        radius = 2.5f,
                        center = Offset(notchX, notchY)
                    )
                }

                // Directional marker dot
                val markerX = cx
                val markerY = cy - radius * 0.82f
                drawCircle(
                    color = SansaTheme.NeonBlue,
                    radius = 3f,
                    center = Offset(markerX, markerY)
                )
            }
        }

        // 4. Center Metallic Select / Action Button
        val centerDiameter = diameter * 0.44f
        Box(
            modifier = Modifier
                .size(centerDiameter)
                .scale(centerScale)
                .shadow(elevation = 8.dp, shape = CircleShape)
                .clip(CircleShape)
                .background(
                    Brush.radialGradient(
                        colors = listOf(
                            Color(0xFF32384A),
                            Color(0xFF1E222D),
                            Color(0xFF14161E)
                        )
                    )
                )
                .border(1.2.dp, Color.White.copy(alpha = 0.22f), CircleShape)
                .clickable(
                    interactionSource = centerInteractionSource,
                    indication = null
                ) {
                    if (hapticsEnabled) {
                        view.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
                    }
                    onCenterTap()
                },
            contentAlignment = Alignment.Center
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Icon(
                    imageVector = if (isCenterActive) Icons.Default.Pause else Icons.Default.PlayArrow,
                    contentDescription = "Select",
                    tint = Color.White,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    text = "SELECT",
                    color = SansaTheme.LcdTextSecondary,
                    fontSize = 8.sp,
                    fontWeight = FontWeight.Black,
                    fontFamily = FontFamily.Monospace,
                    letterSpacing = 1.sp
                )
            }
        }
    }
}
