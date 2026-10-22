package com.antigravity.auraplayer.service

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.antigravity.auraplayer.model.LyricLine
import com.antigravity.auraplayer.model.MediaType
import com.antigravity.auraplayer.model.MediaTrack
import com.antigravity.auraplayer.model.TrackSourceType
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** Commands for the on-screen YouTube video player. */
sealed class VideoCommand {
    data class Load(val videoId: String, val startMs: Long, val autoplay: Boolean) : VideoCommand()
    data object Play : VideoCommand()
    data object Pause : VideoCommand()
    data class Seek(val positionMs: Long) : VideoCommand()
}

/**
 * Two players, one song:
 *  - ExoPlayer plays the audio stream (works in the background and with the screen off).
 *  - The YouTube player in a WebView plays the video while it's on screen.
 * Only one of them plays at a time; when the video appears or disappears, playback is handed
 * over at the current position.
 */
class PlaybackManager private constructor(private val context: Context) {
    companion object {
        private const val TAG = "AuraPlayer/Playback"

        @Volatile
        private var instance: PlaybackManager? = null

        fun getInstance(context: Context): PlaybackManager {
            return instance ?: synchronized(this) {
                instance ?: PlaybackManager(context.applicationContext).also { instance = it }
            }
        }
    }

    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var controllerFuture: ListenableFuture<MediaController>? = null
    var controller: MediaController? = null
        private set

    private val _currentTrack = MutableStateFlow<MediaTrack?>(null)
    val currentTrack: StateFlow<MediaTrack?> = _currentTrack.asStateFlow()

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _currentPosition = MutableStateFlow(0L)
    val currentPosition: StateFlow<Long> = _currentPosition.asStateFlow()

    private val _duration = MutableStateFlow(0L)
    val duration: StateFlow<Long> = _duration.asStateFlow()

    /** User's choice: audio (artwork) or video view. Audio by default. */
    private val _isAudioOnly = MutableStateFlow(true)
    val isAudioOnly: StateFlow<Boolean> = _isAudioOnly.asStateFlow()

    private val _queue = MutableStateFlow<List<MediaTrack>>(emptyList())
    val queue: StateFlow<List<MediaTrack>> = _queue.asStateFlow()

    private val _isShuffled = MutableStateFlow(false)
    val isShuffled: StateFlow<Boolean> = _isShuffled.asStateFlow()

    // Lyrics
    private val _syncedLyrics = MutableStateFlow<List<LyricLine>?>(null)
    val syncedLyrics: StateFlow<List<LyricLine>?> = _syncedLyrics.asStateFlow()

    private val _plainLyrics = MutableStateFlow<String?>(null)
    val plainLyrics: StateFlow<String?> = _plainLyrics.asStateFlow()

    private val _currentLyricIndex = MutableStateFlow(-1)
    val currentLyricIndex: StateFlow<Int> = _currentLyricIndex.asStateFlow()

    // Video player hand-over
    private val _videoCommands = MutableSharedFlow<VideoCommand>(extraBufferCapacity = 8)
    val videoCommands: SharedFlow<VideoCommand> = _videoCommands.asSharedFlow()

    /** True while the YouTube player is on screen and owns playback. */
    var isVideoActive = false
        private set
    private var videoPositionMs = 0L
    private var videoPlaying = false

    /** Video IDs that failed to embed, per track, so fallbacks never retry them. */
    private val failedVideoIds = mutableMapOf<String, MutableSet<String>>()

    private var progressJob: Job? = null
    private var playJob: Job? = null

    init {
        initMediaController()
    }

    private fun initMediaController() {
        val sessionToken = SessionToken(context, ComponentName(context, PlaybackService::class.java))
        controllerFuture = MediaController.Builder(context, sessionToken).buildAsync()
        controllerFuture?.addListener({
            controller = controllerFuture?.get()
            setupPlayerListener()
        }, MoreExecutors.directExecutor())
    }

    private fun setupPlayerListener() {
        controller?.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(playing: Boolean) {
                if (isVideoActive) return
                _isPlaying.value = playing
                if (playing) startProgressTicker() else stopProgressTicker()
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                if (isVideoActive) return
                when (playbackState) {
                    Player.STATE_BUFFERING -> _isLoading.value = true
                    Player.STATE_READY -> {
                        _isLoading.value = false
                        _duration.value = controller?.duration?.coerceAtLeast(0L) ?: 0L
                    }
                    Player.STATE_ENDED -> playNext()
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                Log.w(TAG, "ExoPlayer error: ${error.errorCodeName}", error)
                _isLoading.value = false
                _errorMessage.value = "Couldn't play audio (${error.errorCodeName})"
            }
        })
    }

    fun playTrack(track: MediaTrack, inQueue: List<MediaTrack> = emptyList()) {
        Log.i(TAG, "play \"${track.title}\" by ${track.artist} youtubeId=${track.youtubeId} videoActive=$isVideoActive")
        _currentTrack.value = track
        _queue.value = inQueue.ifEmpty { listOf(track) }
        _errorMessage.value = null
        _currentPosition.value = 0L
        _duration.value = (track.duration * 1000).toLong()
        if (track.sourceType == TrackSourceType.LOCAL && track.mediaType == MediaType.AUDIO) {
            _isAudioOnly.value = true
        }

        // Artwork if missing
        if (track.thumbnailURL == null) {
            scope.launch {
                val art = ArtworkService.fetchArtwork(track.title, track.artist)
                if (art != null && _currentTrack.value?.id == track.id) {
                    _currentTrack.value = _currentTrack.value?.copy(thumbnailURL = art)
                }
            }
        }

        // Lyrics
        scope.launch {
            _syncedLyrics.value = null
            _plainLyrics.value = null
            _currentLyricIndex.value = -1
            val (synced, plain) = LyricsService.fetchLyrics(track.title, track.artist, track.duration)
            if (_currentTrack.value?.id == track.id) {
                _syncedLyrics.value = synced
                _plainLyrics.value = plain
            }
        }

        playJob?.cancel()
        controller?.stop()
        _isLoading.value = true
        playJob = scope.launch {
            var t = track
            // Songs saved by name only: find the official video first
            if (t.sourceType == TrackSourceType.YOUTUBE && t.youtubeId.isNullOrEmpty()) {
                val id = YouTubeService.resolveVideoId(t)
                if (id == null) {
                    fail("Couldn't find this song on YouTube")
                    return@launch
                }
                t = t.copy(youtubeId = id)
                _currentTrack.value = t
            }

            if (isVideoActive && t.youtubeId != null) {
                // Video is on screen: the YouTube player plays it; prepare audio for later hand-over
                _videoCommands.tryEmit(VideoCommand.Load(t.youtubeId!!, 0L, autoplay = true))
                prepareAudio(t, playWhenReady = false)
            } else {
                prepareAudio(t, playWhenReady = true)
            }
        }
    }

    private suspend fun prepareAudio(track: MediaTrack, playWhenReady: Boolean) {
        val uri = when (track.sourceType) {
            TrackSourceType.LOCAL -> track.originalURL
            TrackSourceType.YOUTUBE -> track.youtubeId?.let { YouTubeService.audioStreamUrl(it) }
        }
        if (_currentTrack.value?.id != track.id) return // user moved on meanwhile
        if (uri == null) {
            fail("Couldn't load audio for this song")
            return
        }
        val mediaItem = MediaItem.Builder()
            .setMediaId(track.id)
            .setUri(Uri.parse(uri))
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(track.title)
                    .setArtist(track.artist)
                    .setArtworkUri(track.thumbnailURL?.let { Uri.parse(it) })
                    .build()
            )
            .build()
        controller?.setMediaItem(mediaItem)
        controller?.prepare()
        if (playWhenReady && !isVideoActive) {
            controller?.play()
        } else {
            _isLoading.value = false
        }
    }

    private fun fail(message: String) {
        Log.w(TAG, message)
        _errorMessage.value = message
        _isLoading.value = false
        _isPlaying.value = false
    }

    fun togglePlayPause() {
        if (isVideoActive) {
            _videoCommands.tryEmit(if (videoPlaying) VideoCommand.Pause else VideoCommand.Play)
            return
        }
        val c = controller ?: return
        if (c.isPlaying) c.pause() else c.play()
    }

    fun seekTo(positionMs: Long) {
        _currentPosition.value = positionMs
        updateCurrentLyric(positionMs)
        if (isVideoActive) {
            _videoCommands.tryEmit(VideoCommand.Seek(positionMs))
        } else {
            controller?.seekTo(positionMs)
        }
    }

    fun toggleAudioOnly() {
        _isAudioOnly.value = !_isAudioOnly.value
    }

    fun toggleShuffle() {
        _isShuffled.value = !_isShuffled.value
        if (_isShuffled.value) {
            _queue.value = _queue.value.shuffled()
        }
    }

    fun playNext() {
        val q = _queue.value
        if (q.isEmpty()) return
        val currentIdx = q.indexOfFirst { it.id == _currentTrack.value?.id }
        if (currentIdx in q.indices && currentIdx + 1 < q.size) {
            playTrack(q[currentIdx + 1], q)
        } else {
            playTrack(q.first(), q)
        }
    }

    fun playPrevious() {
        val q = _queue.value
        if (q.isEmpty()) return
        val currentIdx = q.indexOfFirst { it.id == _currentTrack.value?.id }
        if (currentIdx in q.indices && currentIdx - 1 >= 0) {
            playTrack(q[currentIdx - 1], q)
        } else {
            playTrack(q.last(), q)
        }
    }

    // region Video hand-over

    /**
     * The YouTube player appeared on screen: pause the audio player and tell the video player
     * where to start.
     */
    fun onVideoShown(): VideoCommand.Load? {
        val track = _currentTrack.value ?: return null
        val videoId = track.youtubeId ?: return null
        val c = controller
        val wasPlaying = c?.isPlaying == true || _isPlaying.value
        val position = c?.currentPosition ?: _currentPosition.value
        Log.i(TAG, "video shown: $videoId at ${position}ms playing=$wasPlaying")
        isVideoActive = true
        stopProgressTicker()
        c?.pause()
        videoPositionMs = position
        videoPlaying = wasPlaying
        // Returned rather than emitted: the view isn't collecting commands yet at this point
        return VideoCommand.Load(videoId, position, wasPlaying)
    }

    /** The YouTube player left the screen: continue with the audio player from the same spot. */
    fun onVideoHidden() {
        if (!isVideoActive) return
        Log.i(TAG, "video hidden at ${videoPositionMs}ms playing=$videoPlaying")
        isVideoActive = false
        val c = controller ?: return
        c.seekTo(videoPositionMs)
        if (videoPlaying) c.play()
        _isPlaying.value = videoPlaying
        if (videoPlaying) startProgressTicker()
    }

    /** Called from the YouTube player's JavaScript bridge. */
    fun onVideoTime(seconds: Double, durationSeconds: Double) {
        if (!isVideoActive) return
        videoPositionMs = (seconds * 1000).toLong()
        _currentPosition.value = videoPositionMs
        if (durationSeconds > 0) _duration.value = (durationSeconds * 1000).toLong()
        updateCurrentLyric(videoPositionMs)
    }

    /** YT.PlayerState: -1 unstarted, 0 ended, 1 playing, 2 paused, 3 buffering, 5 cued. */
    fun onVideoState(state: Int) {
        if (!isVideoActive) return
        Log.i(TAG, "video state $state")
        when (state) {
            1 -> { videoPlaying = true; _isPlaying.value = true; _isLoading.value = false }
            2 -> { videoPlaying = false; _isPlaying.value = false }
            3 -> _isLoading.value = true
            0 -> { videoPlaying = false; playNext() }
        }
    }

    /** The video can't be embedded (or was removed): try the next-best official video. */
    fun onVideoError(code: Int) {
        val track = _currentTrack.value ?: return
        val failedId = track.youtubeId ?: return
        Log.w(TAG, "video error $code on $failedId for \"${track.title}\"")
        val failed = failedVideoIds.getOrPut(track.id) { mutableSetOf() }.apply { add(failedId) }
        scope.launch {
            val alt = YouTubeService.resolveVideoId(track, excluding = failed)
            if (_currentTrack.value?.id != track.id) return@launch
            if (alt == null) {
                _errorMessage.value = "No playable video found. Switch to Audio to keep listening."
                return@launch
            }
            Log.i(TAG, "alternative video $alt for \"${track.title}\"")
            // Only the picture changes; the audio player keeps the original song's audio
            _currentTrack.value = track.copy(youtubeId = alt)
            if (isVideoActive) _videoCommands.tryEmit(VideoCommand.Load(alt, videoPositionMs, videoPlaying))
        }
    }

    // endregion

    private fun startProgressTicker() {
        progressJob?.cancel()
        progressJob = scope.launch {
            while (isActive) {
                if (!isVideoActive) {
                    val pos = controller?.currentPosition ?: 0L
                    _currentPosition.value = pos
                    val dur = controller?.duration ?: 0L
                    if (dur > 0) _duration.value = dur
                    updateCurrentLyric(pos)
                }
                delay(250)
            }
        }
    }

    private fun stopProgressTicker() {
        progressJob?.cancel()
    }

    private fun updateCurrentLyric(posMs: Long) {
        val lyrics = _syncedLyrics.value ?: return
        var activeIdx = -1
        for (i in lyrics.indices) {
            if (posMs >= lyrics[i].timeMs) activeIdx = i else break
        }
        _currentLyricIndex.value = activeIdx
    }
}
