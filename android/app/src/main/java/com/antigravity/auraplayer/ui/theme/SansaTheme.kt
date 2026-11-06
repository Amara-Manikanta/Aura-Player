package com.antigravity.auraplayer.ui.theme

import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

enum class PlayerTheme(val title: String, val subtitle: String) {
    MODERN("Modern Glass", "Fluid violet glass UI, album art scale & neon glow"),
    SANSA("Sansa e260 Retro", "SanDisk Sansa MP3 player with neon blue virtual rotator")
}

/** SanDisk Sansa e260 Retro Theme Palette */
object SansaTheme {
    // Chassis & Metallic Hardware
    val MetallicDark = Color(0xFF12141B)
    val MetallicMid = Color(0xFF1E212B)
    val MetallicLight = Color(0xFF2E3342)
    val MetallicHighlight = Color(0xFF485066)
    val MetallicEdge = Color(0x38FFFFFF)

    val ChassisGradient = Brush.verticalGradient(
        colors = listOf(Color(0xFF2C303F), Color(0xFF1B1D26), Color(0xFF0F1015))
    )

    // Screen & LCD Bezel
    val ScreenBezel = Color(0xFF08090C)
    val ScreenInnerBezel = Color(0xFF11131A)
    val LcdBacklight = Color(0xFF07111D)
    val LcdGlassReflection = Brush.linearGradient(
        colors = listOf(Color(0x1FFFFFFF), Color(0x05FFFFFF), Color.Transparent)
    )

    // The Iconic Sansa Electric Neon Blue Glowing Ring
    val NeonBlue = Color(0xFF00D4FF)
    val NeonBlueGlow = Color(0xFF0088FF)
    val NeonBlueDark = Color(0xFF004CB3)
    val NeonBlueGradient = Brush.linearGradient(
        colors = listOf(Color(0xFF66E5FF), Color(0xFF00D4FF), Color(0xFF0066FF))
    )

    // LCD Digital Text & Indicators
    val LcdTextPrimary = Color.White
    val LcdTextCyan = Color(0xFF00E5FF)
    val LcdTextSecondary = Color(0xFF7E9EB8)
    val LcdProgressBar = Color(0xFF00D4FF)
    val LcdProgressTrack = Color(0xFF132338)

    // Buttons
    val ButtonSurface = Color(0xFF1C202C)
    val ButtonSurfaceActive = Color(0xFF2A3042)
    val ButtonBorder = Color(0x29FFFFFF)
}
