package com.antigravity.auraplayer.ui.components

import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.antigravity.auraplayer.R
import com.antigravity.auraplayer.model.MediaTrack
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

enum class DevotionalDeity {
    AYYAPPA,
    SHIVA,
    RAMA,
    VENKATESWARA,
    SAI_BABA,
    GANESHA,
    GENERIC
}

object DeityDetector {
    fun detect(track: MediaTrack?): DevotionalDeity? {
        if (track == null) return null
        val title = track.title.lowercase()
        val artist = track.artist.lowercase()
        val album = (track.album ?: "").lowercase()
        val genre = (track.genre ?: "").lowercase()
        val text = "$title $artist $album $genre"

        val isDevotional = genre.contains("devotional") ||
                listOf(
                    "ayyappa", "manikanta", "harivarasanam", "uyyala", "yedakeltav",
                    "shiva", "manjunatha", "lingashtakam", "mahaprana",
                    "rama", "ramadasu", "bhadra shaila", "andari bandhuvaya",
                    "venkateswara", "om namo venkatesaya", "adhivo", "annamayya",
                    "sai baba", "shirdi", "vakratunda", "vinayaka", "swamy", "saranam"
                ).any { text.contains(it) }

        if (!isDevotional) return null

        return when {
            listOf("ayyappa", "manikanta", "harivarasanam", "uyyala", "yedakeltav", "sabarimala",
                   "erumeli", "pamba", "irumudi", "bhagavan saranam", "pallikattu", "karthika").any { text.contains(it) } -> DevotionalDeity.AYYAPPA
            listOf("manjunatha", "shiva", "mahaprana", "lingashtakam", "brahma murari", "shankara").any { text.contains(it) } -> DevotionalDeity.SHIVA
            listOf("ramadasu", "bhadra shaila", "andari bandhuvaya", "ramayya", "kodandaram", "sitarama", "ayodhya").any { text.contains(it) } -> DevotionalDeity.RAMA
            listOf("venkateswara", "akhilanda koti", "om namo venkatesaya", "adhivo", "annamayya", "govinda").any { text.contains(it) } -> DevotionalDeity.VENKATESWARA
            listOf("sai baba", "shirdi", "sai saranam", "baba sai baba").any { text.contains(it) } -> DevotionalDeity.SAI_BABA
            listOf("vakratunda", "kanipaka", "vinayaka", "ganapathi", "vighneshwara").any { text.contains(it) } -> DevotionalDeity.GANESHA
            else -> DevotionalDeity.GENERIC
        }
    }
}

/**
 * Animated divine background with radiant halo, floating deepam sparks,
 * and Lord Ayyappa / deity idol illustration.
 */
@Composable
fun DevotionalGodEffects(
    deity: DevotionalDeity,
    modifier: Modifier = Modifier,
    isPlaying: Boolean = true
) {
    val transition = rememberInfiniteTransition(label = "DevotionalEffects")

    // Slow majestic halo rotation (360 degrees over 40 seconds)
    val haloRotation by transition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(40_000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "haloRotation"
    )

    // Breathing divine aura pulse
    val auraPulse by transition.animateFloat(
        initialValue = 0.88f,
        targetValue = 1.08f,
        animationSpec = infiniteRepeatable(
            animation = tween(2800, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "auraPulse"
    )

    // Manikanta jewel sparkle pulse
    val jewelGlow by transition.animateFloat(
        initialValue = 0.4f,
        targetValue = 1.0f,
        animationSpec = infiniteRepeatable(
            animation = tween(1400, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "jewelGlow"
    )

    // Particle flow for rising aarthi sparks / deepam embers
    val particlePhase by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(5000, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "particlePhase"
    )

    val particles = remember {
        List(28) {
            SparkParticle(
                xNorm = Random.nextFloat(),
                speed = 0.6f + Random.nextFloat() * 0.8f,
                sizeDp = 2.5f + Random.nextFloat() * 3.5f,
                wobblePhase = Random.nextFloat() * 2f * PI.toFloat(),
                color = when (Random.nextInt(4)) {
                    0 -> Color(0xFFFFD54F) // Gold
                    1 -> Color(0xFFFF9800) // Saffron
                    2 -> Color(0xFFFFE082) // Amber Light
                    else -> Color(0xFFFFECB3) // Soft Divine Glow
                }
            )
        }
    }

    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        // Background temple sanctum glow & floating sparks
        Canvas(modifier = Modifier.fillMaxSize()) {
            val width = size.width
            val height = size.height
            val centerX = width / 2f
            val centerY = height / 2f

            // 1. Divine warm radial sanctuary lighting
            val sanctumGradient = Brush.radialGradient(
                colors = listOf(
                    Color(0xFF6B2600).copy(alpha = 0.45f * auraPulse),
                    Color(0xFF381400).copy(alpha = 0.35f),
                    Color(0xFF140500).copy(alpha = 0.15f),
                    Color.Transparent
                ),
                center = Offset(centerX, centerY),
                radius = width.coerceAtLeast(height) * 0.75f * auraPulse
            )
            drawRect(brush = sanctumGradient)

            // 2. Rising glowing deepam embers / aarthi sparks
            particles.forEach { p ->
                val progress = (particlePhase * p.speed + p.wobblePhase) % 1f
                val y = height * (1f - progress)
                val xWobble = sin((progress * 4f * PI.toFloat()) + p.wobblePhase) * (width * 0.04f)
                val x = (p.xNorm * width + xWobble).coerceIn(0f, width)
                val alpha = (sin(progress * PI.toFloat()) * 0.75f).coerceIn(0f, 1f)

                drawCircle(
                    color = p.color.copy(alpha = alpha),
                    radius = p.sizeDp * density,
                    center = Offset(x, y)
                )
            }
        }

        // Lord Ayyappa / Deity Idol Illustration & Prabhavali Arch
        Box(
            modifier = Modifier
                .size(310.dp)
                .padding(16.dp),
            contentAlignment = Alignment.Center
        ) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val cx = size.width / 2f
                val cy = size.height / 2f
                val r = (size.width / 2f).coerceAtMost(size.height / 2f)

                // 1. Radiant Prabhavali (Halo with rotating divine sunbeams)
                rotate(haloRotation, pivot = Offset(cx, cy)) {
                    val numRays = 24
                    for (i in 0 until numRays) {
                        val angle = (i * 360f / numRays) * (PI.toFloat() / 180f)
                        val rayInner = r * 0.45f
                        val rayOuter = r * (0.85f + 0.10f * auraPulse)
                        val start = Offset(cx + rayInner * cos(angle), cy + rayInner * sin(angle))
                        val end = Offset(cx + rayOuter * cos(angle), cy + rayOuter * sin(angle))
                        drawLine(
                            brush = Brush.linearGradient(
                                colors = listOf(
                                    Color(0xFFFFD54F).copy(alpha = 0.30f),
                                    Color(0xFFFF8F00).copy(alpha = 0.08f),
                                    Color.Transparent
                                ),
                                start = start,
                                end = end
                            ),
                            start = start,
                            end = end,
                            strokeWidth = 3f * density,
                            cap = StrokeCap.Round
                        )
                    }
                }

                // 2. Halo Center Disc
                drawCircle(
                    brush = Brush.radialGradient(
                        colors = listOf(
                            Color(0xFFFFE082).copy(alpha = 0.28f * auraPulse),
                            Color(0xFFFF8F00).copy(alpha = 0.15f * auraPulse),
                            Color.Transparent
                        ),
                        center = Offset(cx, cy),
                        radius = r * 0.70f * auraPulse
                    ),
                    radius = r * 0.70f * auraPulse,
                    center = Offset(cx, cy)
                )

                // 3. Deity Specific Idol
                if (deity != DevotionalDeity.AYYAPPA) {
                    when (deity) {
                        DevotionalDeity.SHIVA -> drawShivaTrishul(cx, cy, r, auraPulse)
                        DevotionalDeity.RAMA -> drawRamaKodanda(cx, cy, r, auraPulse)
                        DevotionalDeity.VENKATESWARA -> drawVenkateswaraShankhaChakra(cx, cy, r, auraPulse)
                        DevotionalDeity.SAI_BABA -> drawSaiBabaAura(cx, cy, r, auraPulse)
                        DevotionalDeity.GANESHA -> drawGaneshaIdol(cx, cy, r, auraPulse)
                        DevotionalDeity.GENERIC -> drawSacredOm(cx, cy, r, auraPulse)
                        else -> {}
                    }
                }
            }

            // Authentic Swami Ayyappa Idol Image
            if (deity == DevotionalDeity.AYYAPPA) {
                Image(
                    painter = painterResource(id = R.drawable.ayyappa_idol),
                    contentDescription = "Lord Ayyappa",
                    modifier = Modifier
                        .fillMaxSize(0.86f)
                        .scale(auraPulse.coerceIn(0.96f, 1.04f))
                        .alpha(0.88f),
                    contentScale = ContentScale.Fit
                )
            }
        }
    }
}

private class SparkParticle(
    val xNorm: Float,
    val speed: Float,
    val sizeDp: Float,
    val wobblePhase: Float,
    val color: Color
)

/**
 * Majestic Swami Ayyappa Idol in the iconic Yogic Asana
 * (Chinmudra / Abhaya Hastha, Yogapatta, Lotus Padmasanam, Kireetam, Manikanta Gem).
 */
private fun DrawScope.drawAyyappaIdol(
    cx: Float,
    cy: Float,
    r: Float,
    pulse: Float,
    jewelGlow: Float
) {
    val goldPrimary = Color(0xFFFFD54F)
    val goldSecondary = Color(0xFFFFA000)
    val goldDeep = Color(0xFFFF6F00)
    val sacredShine = Color(0xFFFFF9C4)

    val idolWidth = r * 1.05f
    val idolHeight = r * 1.35f
    val baseBottom = cy + idolHeight * 0.42f
    val headCenterY = cy - idolHeight * 0.25f

    // --- A. Lotus Pedestal (Padmasanam) ---
    val lotusPath = Path().apply {
        moveTo(cx - idolWidth * 0.45f, baseBottom)
        quadraticTo(cx - idolWidth * 0.25f, baseBottom - 18f, cx, baseBottom - 8f)
        quadraticTo(cx + idolWidth * 0.25f, baseBottom - 18f, cx + idolWidth * 0.45f, baseBottom)
        quadraticTo(cx, baseBottom + 22f, cx - idolWidth * 0.45f, baseBottom)
        close()
    }
    drawPath(
        path = lotusPath,
        brush = Brush.verticalGradient(
            colors = listOf(goldPrimary.copy(alpha = 0.50f), goldDeep.copy(alpha = 0.35f)),
            startY = baseBottom - 20f,
            endY = baseBottom + 25f
        )
    )
    drawPath(
        path = lotusPath,
        color = sacredShine.copy(alpha = 0.70f),
        style = Stroke(width = 2.2f, cap = StrokeCap.Round)
    )

    // --- B. Seated Folded Legs with Raised Knees in Yoga Asana ---
    val legsPath = Path().apply {
        moveTo(cx - idolWidth * 0.42f, baseBottom - 4f)
        // Left folded knee upward
        cubicTo(
            cx - idolWidth * 0.44f, baseBottom - 45f,
            cx - idolWidth * 0.26f, baseBottom - 80f,
            cx - idolWidth * 0.18f, baseBottom - 70f
        )
        // Center lap
        quadraticTo(cx, baseBottom - 35f, cx + idolWidth * 0.18f, baseBottom - 70f)
        // Right folded knee upward
        cubicTo(
            cx + idolWidth * 0.26f, baseBottom - 80f,
            cx + idolWidth * 0.44f, baseBottom - 45f,
            cx + idolWidth * 0.42f, baseBottom - 4f
        )
        close()
    }
    drawPath(
        path = legsPath,
        brush = Brush.verticalGradient(
            colors = listOf(goldPrimary.copy(alpha = 0.48f), goldSecondary.copy(alpha = 0.38f)),
            startY = baseBottom - 80f,
            endY = baseBottom
        )
    )
    drawPath(
        path = legsPath,
        color = goldPrimary.copy(alpha = 0.65f),
        style = Stroke(width = 2.5f)
    )

    // --- C. Sacred Yogapatta (The gold band tied around both knees) ---
    val kneeLeftX = cx - idolWidth * 0.25f
    val kneeRightX = cx + idolWidth * 0.25f
    val yogapattaY = baseBottom - 58f

    val yogapattaPath = Path().apply {
        moveTo(kneeLeftX - 10f, yogapattaY)
        quadraticTo(cx, yogapattaY + 12f, kneeRightX + 10f, yogapattaY)
        quadraticTo(cx, yogapattaY + 22f, kneeLeftX - 10f, yogapattaY + 10f)
        close()
    }
    drawPath(
        path = yogapattaPath,
        brush = Brush.horizontalGradient(
            colors = listOf(goldDeep.copy(alpha = 0.85f), sacredShine, goldDeep.copy(alpha = 0.85f)),
            startX = kneeLeftX,
            endX = kneeRightX
        )
    )
    drawPath(
        path = yogapattaPath,
        color = sacredShine,
        style = Stroke(width = 1.8f)
    )

    // --- D. Torso & Shoulders ---
    val torsoTopY = headCenterY + 22f
    val torsoPath = Path().apply {
        moveTo(cx - idolWidth * 0.26f, torsoTopY + 12f)
        // left arm and torso
        quadraticTo(cx - idolWidth * 0.18f, torsoTopY + 45f, cx - idolWidth * 0.14f, baseBottom - 42f)
        lineTo(cx + idolWidth * 0.14f, baseBottom - 42f)
        quadraticTo(cx + idolWidth * 0.18f, torsoTopY + 45f, cx + idolWidth * 0.26f, torsoTopY + 12f)
        // neckline
        quadraticTo(cx, torsoTopY + 25f, cx - idolWidth * 0.26f, torsoTopY + 12f)
        close()
    }
    drawPath(
        path = torsoPath,
        brush = Brush.verticalGradient(
            colors = listOf(goldPrimary.copy(alpha = 0.52f), goldSecondary.copy(alpha = 0.40f)),
            startY = torsoTopY,
            endY = baseBottom - 40f
        )
    )
    drawPath(
        path = torsoPath,
        color = goldPrimary.copy(alpha = 0.70f),
        style = Stroke(width = 2.4f)
    )

    // --- E. Right Hand in Chinmudra / Abhaya Hastha ---
    val rightHandPath = Path().apply {
        // Shoulder to elbow
        moveTo(cx + idolWidth * 0.24f, torsoTopY + 12f)
        quadraticTo(cx + idolWidth * 0.34f, torsoTopY + 36f, cx + idolWidth * 0.30f, torsoTopY + 60f)
        // Forearm raised in Chinmudra
        quadraticTo(cx + idolWidth * 0.36f, torsoTopY + 25f, cx + idolWidth * 0.28f, torsoTopY - 4f)
        // Hand fingers
        quadraticTo(cx + idolWidth * 0.25f, torsoTopY - 18f, cx + idolWidth * 0.22f, torsoTopY - 2f)
        quadraticTo(cx + idolWidth * 0.18f, torsoTopY + 30f, cx + idolWidth * 0.16f, torsoTopY + 45f)
    }
    drawPath(
        path = rightHandPath,
        color = sacredShine.copy(alpha = 0.75f),
        style = Stroke(width = 3.2f, cap = StrokeCap.Round, join = StrokeJoin.Round)
    )

    // Left Arm resting gently on left knee
    val leftArmPath = Path().apply {
        moveTo(cx - idolWidth * 0.24f, torsoTopY + 12f)
        quadraticTo(cx - idolWidth * 0.36f, torsoTopY + 45f, cx - idolWidth * 0.26f, baseBottom - 65f)
        quadraticTo(cx - idolWidth * 0.20f, baseBottom - 60f, cx - idolWidth * 0.16f, baseBottom - 55f)
    }
    drawPath(
        path = leftArmPath,
        color = sacredShine.copy(alpha = 0.75f),
        style = Stroke(width = 3.2f, cap = StrokeCap.Round, join = StrokeJoin.Round)
    )

    // --- F. Pushpamala (Garland) draped across chest ---
    val malaPath = Path().apply {
        moveTo(cx - idolWidth * 0.16f, torsoTopY + 15f)
        quadraticTo(cx, baseBottom - 48f, cx + idolWidth * 0.16f, torsoTopY + 15f)
    }
    drawPath(
        path = malaPath,
        color = Color(0xFFFFB300).copy(alpha = 0.85f),
        style = Stroke(width = 3.5f, cap = StrokeCap.Round, pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f), 0f))
    )

    // --- G. Head & Crown (Kireetam) ---
    // Divine Face
    drawOval(
        brush = Brush.verticalGradient(
            colors = listOf(sacredShine.copy(alpha = 0.65f), goldPrimary.copy(alpha = 0.50f)),
            startY = headCenterY - 25f,
            endY = headCenterY + 20f
        ),
        topLeft = Offset(cx - 20f, headCenterY - 20f),
        size = Size(40f, 44f)
    )
    drawOval(
        color = sacredShine.copy(alpha = 0.85f),
        topLeft = Offset(cx - 20f, headCenterY - 20f),
        size = Size(40f, 44f),
        style = Stroke(width = 2.2f)
    )

    // Conical Stepped Crown (Kireetam)
    val crownPath = Path().apply {
        moveTo(cx - 24f, headCenterY - 14f)
        lineTo(cx - 18f, headCenterY - 45f)
        lineTo(cx - 10f, headCenterY - 72f)
        // Pinnacle jewel
        lineTo(cx, headCenterY - 86f)
        lineTo(cx + 10f, headCenterY - 72f)
        lineTo(cx + 18f, headCenterY - 45f)
        lineTo(cx + 24f, headCenterY - 14f)
        close()
    }
    drawPath(
        path = crownPath,
        brush = Brush.verticalGradient(
            colors = listOf(sacredShine, goldPrimary.copy(alpha = 0.75f), goldDeep.copy(alpha = 0.60f)),
            startY = headCenterY - 86f,
            endY = headCenterY - 14f
        )
    )
    drawPath(
        path = crownPath,
        color = sacredShine,
        style = Stroke(width = 2.4f)
    )

    // Crown Top Pinnacle Gem
    drawCircle(
        color = Color(0xFFFFF176).copy(alpha = 0.90f * pulse),
        radius = 5.5f * pulse,
        center = Offset(cx, headCenterY - 86f)
    )

    // --- H. The Iconic Manikanta Radiant Bell / Jewel on Neck ---
    val jewelCenter = Offset(cx, torsoTopY + 16f)
    drawCircle(
        brush = Brush.radialGradient(
            colors = listOf(
                Color.White,
                Color(0xFFFFD54F),
                Color(0xFFFF6F00).copy(alpha = 0.4f),
                Color.Transparent
            ),
            center = jewelCenter,
            radius = 16f * jewelGlow
        ),
        radius = 16f * jewelGlow,
        center = jewelCenter
    )
    drawCircle(
        color = Color.White,
        radius = 4.5f * jewelGlow,
        center = jewelCenter
    )
}

/** Shiva Trishul & Crescent Moon */
private fun DrawScope.drawShivaTrishul(cx: Float, cy: Float, r: Float, pulse: Float) {
    val gold = Color(0xFFFFD54F)
    val trishulPath = Path().apply {
        moveTo(cx, cy + r * 0.55f)
        lineTo(cx, cy - r * 0.55f)
    }
    drawLine(gold.copy(alpha = 0.8f), Offset(cx, cy + r * 0.55f), Offset(cx, cy - r * 0.55f), strokeWidth = 4f)
    // Left prong
    val leftProng = Path().apply {
        moveTo(cx, cy - r * 0.25f)
        cubicTo(cx - r * 0.35f, cy - r * 0.35f, cx - r * 0.30f, cy - r * 0.65f, cx - r * 0.25f, cy - r * 0.58f)
    }
    drawPath(leftProng, gold.copy(alpha = 0.8f), style = Stroke(4f))
    // Right prong
    val rightProng = Path().apply {
        moveTo(cx, cy - r * 0.25f)
        cubicTo(cx + r * 0.35f, cy - r * 0.35f, cx + r * 0.30f, cy - r * 0.65f, cx + r * 0.25f, cy - r * 0.58f)
    }
    drawPath(rightProng, gold.copy(alpha = 0.8f), style = Stroke(4f))
}

/** Rama Kodanda Bow & Arrow */
private fun DrawScope.drawRamaKodanda(cx: Float, cy: Float, r: Float, pulse: Float) {
    val gold = Color(0xFFFFD54F)
    val bowPath = Path().apply {
        moveTo(cx - r * 0.35f, cy + r * 0.50f)
        cubicTo(cx - r * 0.60f, cy, cx - r * 0.60f, cy - r * 0.30f, cx - r * 0.35f, cy - r * 0.50f)
    }
    drawPath(bowPath, gold.copy(alpha = 0.8f), style = Stroke(4f))
    drawLine(gold.copy(alpha = 0.5f), Offset(cx - r * 0.35f, cy + r * 0.50f), Offset(cx - r * 0.35f, cy - r * 0.50f), strokeWidth = 2f)
}

/** Venkateswara Shankha, Chakra & Namam */
private fun DrawScope.drawVenkateswaraShankhaChakra(cx: Float, cy: Float, r: Float, pulse: Float) {
    val gold = Color(0xFFFFD54F)
    // Sacred Namam in center
    val namamPath = Path().apply {
        moveTo(cx - 18f, cy - r * 0.30f)
        lineTo(cx - 18f, cy + r * 0.20f)
        quadraticTo(cx, cy + r * 0.32f, cx + 18f, cy + r * 0.20f)
        lineTo(cx + 18f, cy - r * 0.30f)
        lineTo(cx + 10f, cy - r * 0.30f)
        lineTo(cx + 10f, cy + r * 0.15f)
        quadraticTo(cx, cy + r * 0.22f, cx - 10f, cy + r * 0.15f)
        lineTo(cx - 10f, cy - r * 0.30f)
        close()
    }
    drawPath(namamPath, Color.White.copy(alpha = 0.85f))
    // Srichoornam (red line in middle)
    drawRect(Color(0xFFE53935).copy(alpha = 0.9f), topLeft = Offset(cx - 3.5f, cy - r * 0.30f), size = Size(7f, r * 0.45f))
}

/** Sai Baba Divine Blessing & Abhaya Halo */
private fun DrawScope.drawSaiBabaAura(cx: Float, cy: Float, r: Float, pulse: Float) {
    val gold = Color(0xFFFFD54F)
    drawCircle(
        brush = Brush.radialGradient(
            listOf(gold.copy(alpha = 0.45f), Color.Transparent),
            center = Offset(cx, cy),
            radius = r * 0.65f
        ),
        radius = r * 0.65f,
        center = Offset(cx, cy)
    )
}

/** Ganesha Elephant Contour & Om */
private fun DrawScope.drawGaneshaIdol(cx: Float, cy: Float, r: Float, pulse: Float) {
    val gold = Color(0xFFFFD54F)
    drawCircle(gold.copy(alpha = 0.35f), radius = r * 0.55f, center = Offset(cx, cy), style = Stroke(3f))
}

/** Sacred Om Symbol */
private fun DrawScope.drawSacredOm(cx: Float, cy: Float, r: Float, pulse: Float) {
    val gold = Color(0xFFFFD54F)
    drawCircle(gold.copy(alpha = 0.35f), radius = r * 0.55f, center = Offset(cx, cy), style = Stroke(3f))
}
