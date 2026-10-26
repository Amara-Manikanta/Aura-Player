package com.antigravity.auraplayer.ui.theme

import android.app.Activity
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

private val DarkColorScheme = darkColorScheme(
    primary = NeonPurple,
    secondary = NeonIndigo,
    tertiary = NeonPink,
    background = BackgroundDark,
    // Dialogs, menus and sheets need a solid surface: deep violet glass
    surface = Color(0xFF3A3190),
    surfaceVariant = Color(0xFF463CA0),
    surfaceContainer = Color(0xFF3A3190),
    surfaceContainerHigh = Color(0xFF433999),
    surfaceContainerHighest = Color(0xFF4C42A6),
    surfaceContainerLow = Color(0xFF342B86),
    onPrimary = Color(0xFF2E2678),
    onSecondary = TextPrimary,
    onBackground = TextPrimary,
    onSurface = TextPrimary,
    onSurfaceVariant = TextSecondary,
    outline = GlassBorder
)

@Composable
fun AuraPlayerTheme(
    content: @Composable () -> Unit
) {
    val colorScheme = DarkColorScheme
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.statusBarColor = android.graphics.Color.TRANSPARENT
            window.navigationBarColor = android.graphics.Color.TRANSPARENT
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = false
            WindowCompat.getInsetsController(window, view).isAppearanceLightNavigationBars = false
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography,
        content = content
    )
}
