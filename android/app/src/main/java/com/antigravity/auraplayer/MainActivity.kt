package com.antigravity.auraplayer

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.util.Rational
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.*
import com.antigravity.auraplayer.data.PlaylistRepository
import com.antigravity.auraplayer.model.MediaType
import com.antigravity.auraplayer.service.PlaybackManager
import com.antigravity.auraplayer.ui.components.VideoPlayerView
import com.antigravity.auraplayer.ui.screens.MainScreen
import com.antigravity.auraplayer.ui.theme.AuraPlayerTheme

class MainActivity : ComponentActivity() {
    private lateinit var repository: PlaylistRepository
    private lateinit var playbackManager: PlaybackManager
    private var isInPiPMode by mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        repository = PlaylistRepository(applicationContext)
        playbackManager = PlaybackManager.getInstance(applicationContext)

        setContent {
            AuraPlayerTheme {
                val currentTrack by playbackManager.currentTrack.collectAsState()
                val isAudioOnly by playbackManager.isAudioOnly.collectAsState()

                if (isInPiPMode && currentTrack?.youtubeId != null && !isAudioOnly) {
                    VideoPlayerView(playbackManager = playbackManager)
                } else {
                    MainScreen(
                        repository = repository,
                        playbackManager = playbackManager,
                        onEnterPiP = { enterPictureInPicture() }
                    )
                }
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        val currentTrack = playbackManager.currentTrack.value
        val isAudioOnly = playbackManager.isAudioOnly.value
        val isPlaying = playbackManager.isPlaying.value

        if (isPlaying && currentTrack?.youtubeId != null && !isAudioOnly) {
            enterPictureInPicture()
        }
    }

    private fun enterPictureInPicture() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val aspectRatio = Rational(16, 9)
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(aspectRatio)
                .build()
            enterPictureInPictureMode(params)
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        isInPiPMode = isInPictureInPictureMode
    }
}
