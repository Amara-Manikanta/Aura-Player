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
import com.antigravity.auraplayer.data.PlaylistRepository
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

/** Where a song was started from: decides which language version to play */
sealed class PlayContext {
    data object Unchanged : PlayContext()
    data class FromPlaylist(val playlistId: String) : PlayContext()
    data object None : PlayContext()
}

/** What the player screen shows */
enum class DisplayMode { AUDIO, VIDEO, LYRICS }

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
        const val PREFS = "aura_settings"
        const val KEY_PREFERRED_LANGUAGE = "preferredLanguage"

        @Volatile
        private var instance: PlaybackManager? = null

        fun getInstance(context: Context): PlaybackManager {
            return instance ?: synchronized(this) {
                instance ?: PlaybackManager(context.applicationContext).also { instance = it }
            }
        }

        /** "Hindi Music" → hindi, "English Music" → "" (no Indian language), anything else → null */
        fun playlistLanguage(name: String): String? {
            val n = name.lowercase()
            val indian = listOf(
                "telugu" to listOf("telugu", "tollywood"), "tamil" to listOf("tamil", "kollywood"),
                "hindi" to listOf("hindi", "bollywood"), "kannada" to listOf("kannada", "sandalwood"),
                "malayalam" to listOf("malayalam", "mollywood"), "marathi" to listOf("marathi"),
                "punjabi" to listOf("punjab"), "bengali" to listOf("bengali", "bangla")
            )
            for ((lang, words) in indian) if (words.any { n.contains(it) }) return lang
            val other = listOf("english", "spanish", "korean", "k-pop", "kpop", "japanese", "french", "arabic", "western")
            if (other.any { n.contains(it) }) return ""
            return null
        }
    }

    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private val repository = PlaylistRepository.getInstance(context)
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
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

    /** Audio (artwork), Video or Lyrics on the player screen */
    private val _displayMode = MutableStateFlow(DisplayMode.AUDIO)
    val displayMode: StateFlow<DisplayMode> = _displayMode.asStateFlow()

    /** True unless the video is shown (kept for the picture-in-picture logic) */
    private val _isAudioOnly = MutableStateFlow(true)
    val isAudioOnly: StateFlow<Boolean> = _isAudioOnly.asStateFlow()

    private val _queue = MutableStateFlow<List<MediaTrack>>(emptyList())
    val queue: StateFlow<List<MediaTrack>> = _queue.asStateFlow()

    private val _isShuffled = MutableStateFlow(false)
    val isShuffled: StateFlow<Boolean> = _isShuffled.asStateFlow()

    /** 0 off, 1 repeat all, 2 repeat one */
    private val _repeatMode = MutableStateFlow(0)
    val repeatMode: StateFlow<Int> = _repeatMode.asStateFlow()

    // Lyrics
    private val _syncedLyrics = MutableStateFlow<List<LyricLine>?>(null)
    val syncedLyrics: StateFlow<List<LyricLine>?> = _syncedLyrics.asStateFlow()

    private val _plainLyrics = MutableStateFlow<String?>(null)
    val plainLyrics: StateFlow<String?> = _plainLyrics.asStateFlow()

    private val _currentLyricIndex = MutableStateFlow(-1)
    val currentLyricIndex: StateFlow<Int> = _currentLyricIndex.asStateFlow()

    /** While lyrics are being synced in the editor the song must not move to the next track */
    var holdForLyricsEditor = false

    /** Album cover found for the playing song (iTunes), shown instead of the video thumbnail */
    private val _artworkUrl = MutableStateFlow<String?>(null)
    val artworkUrl: StateFlow<String?> = _artworkUrl.asStateFlow()

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

    /** Playlist the current queue came from (its language picks the song's version) */
    var contextPlaylistId: String? = null
        private set

    private var playCounted = false
    private var trimEndHandled = false

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
                    Player.STATE_ENDED -> handleTrackEnded()
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                Log.w(TAG, "ExoPlayer error: ${error.errorCodeName}", error)
                _isLoading.value = false
                _errorMessage.value = "Couldn't play audio (${error.errorCodeName})"
            }
        })
    }

    // region Language

    var preferredLanguage: String?
        get() = prefs.getString(KEY_PREFERRED_LANGUAGE, null)?.takeIf { it.isNotEmpty() && it != "none" }
        set(value) { prefs.edit().putString(KEY_PREFERRED_LANGUAGE, value ?: "none").apply() }

    /**
     * Which language version to play: the playlist it's played from ("Hindi Music" → Hindi), else the
     * playlists it belongs to (if they agree), else the Preferred Song Language setting (Indian songs).
     */
    fun searchLanguage(track: MediaTrack): String? {
        val playlists = repository.playlists.value
        contextPlaylistId?.let { pid ->
            val pl = playlists.firstOrNull { it.id == pid }
            if (pl != null && pl.tracks.any { it.id == track.id }) {
                playlistLanguage(pl.name)?.let { return it.ifEmpty { null } }
            }
        }
        val langs = playlists.filter { pl -> pl.tracks.any { it.id == track.id } }.mapNotNull { playlistLanguage(it.name) }.toSet()
        if (langs.size == 1) return langs.first().ifEmpty { null }
        return if (track.isIndianRelease) preferredLanguage?.lowercase() else null
    }

    // endregion

    /** `startAtMs` overrides the song's own start time (e.g. resuming after switching video) */
    fun playTrack(
        track: MediaTrack,
        inQueue: List<MediaTrack> = emptyList(),
        playContext: PlayContext = PlayContext.Unchanged,
        startAtMs: Long? = null
    ) {
        Log.i(TAG, "play \"${track.title}\" by ${track.artist} youtubeId=${track.youtubeId} videoActive=$isVideoActive")
        when (playContext) {
            is PlayContext.FromPlaylist -> contextPlaylistId = playContext.playlistId
            PlayContext.None -> contextPlaylistId = null
            PlayContext.Unchanged -> {}
        }
        val startMs = startAtMs ?: ((track.startTime ?: 0.0) * 1000).toLong()
        _currentTrack.value = track
        if (inQueue.isNotEmpty()) _queue.value = inQueue else if (_queue.value.none { it.id == track.id }) _queue.value = listOf(track)
        _errorMessage.value = null
        _currentPosition.value = startMs
        _duration.value = (track.duration * 1000).toLong()
        playCounted = false
        trimEndHandled = false
        if (track.sourceType == TrackSourceType.LOCAL && track.mediaType == MediaType.AUDIO) {
            _displayMode.value = DisplayMode.AUDIO
            _isAudioOnly.value = true
        }

        // Album cover (same careful lookup as the Mac app), the video thumbnail meanwhile
        _artworkUrl.value = TrackArtworkService.cachedCover(track) ?: track.effectiveThumbnailURL
        scope.launch {
            val cover = TrackArtworkService.cover(track)
            if (cover != null && _currentTrack.value?.id == track.id) _artworkUrl.value = cover
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
        // Silence the old video at once: while the next song's video is looked up it would keep playing
        if (isVideoActive) _videoCommands.tryEmit(VideoCommand.Pause)
        _isLoading.value = true
        playJob = scope.launch {
            var t = track
            // Songs saved by name only: find the official video first (in the right language, skipping 👎 videos)
            if (t.sourceType == TrackSourceType.YOUTUBE && t.youtubeId.isNullOrEmpty()) {
                val id = YouTubeService.resolveVideo(t, searchLanguage(t), (t.rejectedVideoIds ?: emptyList()).toSet())
                if (id == null) {
                    fail("Couldn't find \"${t.title}\" on YouTube")
                    return@launch
                }
                if (_currentTrack.value?.id != track.id) return@launch
                t = t.copy(youtubeId = id)
                _currentTrack.value = t
            }

            if (isVideoActive && t.youtubeId != null) {
                // Video is on screen: the YouTube player plays it; prepare audio for later hand-over
                videoPositionMs = startMs
                _videoCommands.tryEmit(VideoCommand.Load(t.youtubeId!!, startMs, autoplay = true))
                prepareAudio(t, startMs, playWhenReady = false)
            } else {
                prepareAudio(t, startMs, playWhenReady = true)
            }
        }
    }

    private suspend fun prepareAudio(track: MediaTrack, startMs: Long, playWhenReady: Boolean) {
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
                    .setArtworkUri((_artworkUrl.value ?: track.thumbnailURL)?.let { Uri.parse(it) })
                    .build()
            )
            .build()
        controller?.setMediaItem(mediaItem, startMs)
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
            videoPositionMs = positionMs
            _videoCommands.tryEmit(VideoCommand.Seek(positionMs))
        } else {
            controller?.seekTo(positionMs)
        }
    }

    fun setDisplayMode(mode: DisplayMode) {
        _displayMode.value = mode
        _isAudioOnly.value = mode != DisplayMode.VIDEO
    }

    fun toggleAudioOnly() = setDisplayMode(if (_displayMode.value == DisplayMode.VIDEO) DisplayMode.AUDIO else DisplayMode.VIDEO)

    fun toggleShuffle() {
        _isShuffled.value = !_isShuffled.value
        if (_isShuffled.value) {
            val current = _currentTrack.value
            _queue.value = listOfNotNull(current) + _queue.value.filter { it.id != current?.id }.shuffled()
        }
    }

    /** Off → Repeat All → Repeat One → Off */
    fun toggleRepeat() {
        _repeatMode.value = (_repeatMode.value + 1) % 3
    }

    fun playNext() {
        val q = _queue.value
        if (q.isEmpty()) return
        val currentIdx = q.indexOfFirst { it.id == _currentTrack.value?.id }
        when {
            currentIdx in q.indices && currentIdx + 1 < q.size -> playTrack(q[currentIdx + 1], q)
            _repeatMode.value == 1 || currentIdx !in q.indices -> playTrack(q.first(), q)
            else -> { // end of the list
                controller?.pause()
                if (isVideoActive) _videoCommands.tryEmit(VideoCommand.Pause)
            }
        }
    }

    /** Back to the start of this song (or its start time) unless it just began, then the previous song */
    fun playPrevious() {
        val startMs = ((_currentTrack.value?.startTime ?: 0.0) * 1000).toLong()
        if (_currentPosition.value > startMs + 3000) {
            seekTo(startMs)
            return
        }
        val q = _queue.value
        if (q.isEmpty()) return
        val currentIdx = q.indexOfFirst { it.id == _currentTrack.value?.id }
        if (currentIdx in q.indices && currentIdx - 1 >= 0) playTrack(q[currentIdx - 1], q) else seekTo(startMs)
    }

    /** Song finished (or reached its end time): Repeat One restarts it, otherwise the next song. */
    private fun handleTrackEnded() {
        if (holdForLyricsEditor) {
            if (isVideoActive) _videoCommands.tryEmit(VideoCommand.Pause) else controller?.pause()
            return
        }
        val track = _currentTrack.value ?: return
        if (_repeatMode.value == 2) {
            trimEndHandled = false
            seekTo(((track.startTime ?: 0.0) * 1000).toLong())
            if (isVideoActive) _videoCommands.tryEmit(VideoCommand.Play) else controller?.play()
            return
        }
        playNext()
    }

    /** Called every tick with the position: counts the play, applies the end time */
    private fun onPosition(posMs: Long) {
        val track = _currentTrack.value ?: return
        if (!playCounted && posMs >= 10_000) {
            playCounted = true
            repository.recordPlay(track)
        }
        val end = track.endTime
        if (end != null && end > 0 && posMs >= end * 1000 && !trimEndHandled) {
            trimEndHandled = true
            handleTrackEnded()
        }
    }

    // region Start / end time and video feedback

    /** Saves a start / end time for the playing song and applies it now */
    fun setTrim(start: Double?, end: Double?) {
        val track = _currentTrack.value ?: return
        repository.setTrimTimes(track, start, end)
        _currentTrack.value = track.copy(startTime = start?.takeIf { it > 0 }, endTime = end)
        trimEndHandled = false
    }

    /** The playing video is the one saved for this song (👍 given, or added by link) */
    fun isCurrentVideoConfirmed(): Boolean {
        val track = _currentTrack.value ?: return false
        val saved = repository.savedTrack(track.id) ?: return false
        return track.youtubeId != null && saved.youtubeId == track.youtubeId
    }

    /** 👍 Right video: always play it for this song */
    fun confirmCurrentVideo() {
        val track = _currentTrack.value ?: return
        val vid = track.youtubeId ?: return
        repository.setVideo(track.id, vid)
        _currentTrack.value = track.copy(youtubeId = vid)   // re-emit so the 👍 lights up
    }

    /** 👎 Wrong video: never pick it again for this song, switch to the next-best now */
    fun rejectCurrentVideo() {
        val track = _currentTrack.value ?: return
        val vid = track.youtubeId ?: return
        repository.rejectVideo(track.id, vid)
        val excluded = ((track.rejectedVideoIds ?: emptyList()) + vid + (failedVideoIds[track.id] ?: emptySet())).toSet()
        val resumeAt = _currentPosition.value
        scope.launch {
            val alt = YouTubeService.resolveVideo(track, searchLanguage(track), excluded)
            if (_currentTrack.value?.id != track.id) return@launch
            if (alt == null) {
                _errorMessage.value = "No other official video found. Use Change Video Link to paste the right one."
                return@launch
            }
            // carry on from where the user was, with the new video
            playTrack(track.copy(youtubeId = alt, rejectedVideoIds = excluded.toList()), _queue.value,
                startAtMs = resumeAt.takeIf { it > 10_000 })
        }
    }

    // endregion

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
        onPosition(videoPositionMs)
    }

    /** YT.PlayerState: -1 unstarted, 0 ended, 1 playing, 2 paused, 3 buffering, 5 cued. */
    fun onVideoState(state: Int) {
        if (!isVideoActive) return
        Log.i(TAG, "video state $state")
        when (state) {
            1 -> { videoPlaying = true; _isPlaying.value = true; _isLoading.value = false }
            2 -> { videoPlaying = false; _isPlaying.value = false }
            3 -> _isLoading.value = true
            0 -> { videoPlaying = false; handleTrackEnded() }
        }
    }

    /** The video can't be embedded (or was removed): try the next-best official video. */
    fun onVideoError(code: Int) {
        val track = _currentTrack.value ?: return
        val failedId = track.youtubeId ?: return
        Log.w(TAG, "video error $code on $failedId for \"${track.title}\"")
        val failed = failedVideoIds.getOrPut(track.id) { mutableSetOf() }.apply { add(failedId) }
        scope.launch {
            val alt = YouTubeService.resolveVideo(track, searchLanguage(track), failed + (track.rejectedVideoIds ?: emptyList()))
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

    /** Applies title and artist rename to the playing track */
    fun applyRename(trackId: String, newTitle: String, newArtist: String) {
        val curr = _currentTrack.value ?: return
        if (curr.id == trackId) {
            _currentTrack.value = curr.copy(
                title = newTitle.trim(),
                artist = newArtist.trim().ifEmpty { "Unknown Artist" }
            )
        }
    }

    /** Reloads lyrics from custom store or network for the current song */
    fun reloadLyrics() {
        val track = _currentTrack.value ?: return
        scope.launch {
            val (synced, plain) = LyricsService.fetchLyrics(track.title, track.artist, track.duration)
            if (_currentTrack.value?.id == track.id) {
                _syncedLyrics.value = synced
                _plainLyrics.value = plain
                updateCurrentLyric(_currentPosition.value)
            }
        }
    }

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
                    onPosition(pos)
                }
                delay(100)
            }
        }
    }

    private fun stopProgressTicker() {
        progressJob?.cancel()
    }

    private fun updateCurrentLyric(posMs: Long) {
        val lyrics = _syncedLyrics.value ?: return
        if (lyrics.isEmpty()) {
            _currentLyricIndex.value = -1
            return
        }
        // 320ms vocal anticipation lead time & intro protection, matching iOS & macOS
        val anticipated = posMs + 320L
        if (anticipated < lyrics[0].timeMs) {
            _currentLyricIndex.value = -1
            return
        }
        var activeIdx = -1
        for (i in lyrics.indices) {
            if (anticipated >= lyrics[i].timeMs) activeIdx = i else break
        }
        _currentLyricIndex.value = activeIdx
    }
}
