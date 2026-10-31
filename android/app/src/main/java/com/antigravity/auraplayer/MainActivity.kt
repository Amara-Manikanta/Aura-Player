package com.antigravity.auraplayer

import android.Manifest
import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.util.Rational
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.*
import androidx.core.content.ContextCompat
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

    private val requestNotificationPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { /* system notification permission result */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        checkNotificationPermission()

        repository = PlaylistRepository.getInstance(applicationContext)
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

    private fun checkNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                requestNotificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
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
