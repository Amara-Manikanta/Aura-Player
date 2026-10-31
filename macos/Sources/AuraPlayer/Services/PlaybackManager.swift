import Foundation
import AVFoundation
import MediaPlayer
import Observation

public enum RepeatMode: String, CaseIterable, Sendable {
    case off
    case all
    case one
    
    public var iconName: String {
        switch self {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

public enum PlaybackQuality: String, CaseIterable, Sendable {
    case auto = "Auto (Best)"
    case p1080 = "1080p Full HD"
    case p720 = "720p HD"
    case audioOnly = "Audio Only"
}

public enum WebPlayerAction: Sendable {
    case play
    case pause
    case seek(TimeInterval)
    case setVolume(Float)
}

@MainActor
@Observable
public final class PlaybackManager {
    public static let shared = PlaybackManager()
    
    public var currentTrack: MediaTrack?
    public var isPlaying: Bool = false
    public var currentTime: TimeInterval = 0
    public var duration: TimeInterval = 0
    public var volume: Float = 0.8 {
        didSet {
            player.volume = volume
            if isVideoViewActive {
                onWebPlayerAction?(.setVolume(isMuted ? 0 : volume))
            }
        }
    }
    public var isMuted: Bool = false {
        didSet {
            player.isMuted = isMuted
            if isVideoViewActive {
                onWebPlayerAction?(.setVolume(isMuted ? 0 : volume))
            }
        }
    }
    public var isAudioOnly: Bool = false
    public var quality: PlaybackQuality = .auto
    public var queue: [MediaTrack] = []
    public var currentIndex: Int = 0
    public var isShuffle: Bool = false
    public var repeatMode: RepeatMode = .off
    public var isLoading: Bool = false
    public var errorMessage: String?
    
    // Display Mode: Music (Album Artwork), Video (YouTube), Lyrics (Karaoke)
    public enum PlaybackDisplayMode: String, CaseIterable, Sendable {
        case audio = "Music"
        case video = "Video"
        case lyrics = "Lyrics"
    }
    public var displayMode: PlaybackDisplayMode = .lyrics {
        didSet {
            setVideoViewActive(displayMode == .video)
        }
    }
    
    // Video view mode & Web Player synchronization bridge
    public var isVideoViewActive: Bool = false
    /// The mini player is showing the video, so the main window must not show a second copy
    public var videoInMiniPlayer: Bool = false
    /// The current video can't be shown in the app (embedding disabled), so its audio plays instead
    public private(set) var audioFallbackActive: Bool = false
    /// True while the YouTube web player (not the audio player) is producing sound
    private var webPlayerOwnsPlayback: Bool {
        isVideoViewActive && currentTrack?.sourceType == .youtube && !audioFallbackActive
    }
    public var onWebPlayerAction: ((WebPlayerAction) -> Void)?
    /// Which web player currently owns `onWebPlayerAction` (main window or mini player)
    public var webPlayerOwner: ObjectIdentifier?
    /// When the web player last started loading a video; the old video's "paused" right after is ignored
    public var webVideoLoadStartedAt = Date.distantPast
    
    // Lyrics & Artwork
    public var lyrics: SongLyrics?
    public var isFetchingLyrics: Bool = false
    public var currentArtworkURL: String?
    
    // Play count & Store reference
    public weak var playlistStore: PlaylistStore?
    public var playCountRecordedForCurrentTrack: Bool = false
    
    // Smart Shuffle State (Fisher-Yates with history)
    private var historyStack: [MediaTrack] = []
    /// Set once the current song passes its end time, so "next" fires only once
    private var trimEndReached = false
    /// Video IDs that failed to play (e.g. embedding disabled), per track, so fallbacks never retry them.
    private var failedVideoIds: [UUID: Set<String>] = [:]
    private var shuffledIndices: [Int] = []
    private var shufflePointer: Int = 0
    
    // Internal player
    public let player: AVPlayer = AVPlayer()
    private var timeObserverToken: Any?
    private var itemEndObserver: Any?
    
    public init() {
        setupRemoteCommands()
        setupAudioSession()
        setupTimeObserver()
    }
    
    isolated deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        if let observer = itemEndObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func setupAudioSession() {
        player.automaticallyWaitsToMinimizeStalling = true
    }
    
    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.currentTime = time.seconds
                
                if let currentItem = self.player.currentItem {
                    let itemDuration = currentItem.duration.seconds
                    if !itemDuration.isNaN && itemDuration > 0 {
                        // Some YouTube m4a files are read by AVFoundation as double their real length;
                        // when the known length is about half, trust the known length
                        let known = self.currentTrack?.duration ?? 0
                        let ratio = known > 0 ? itemDuration / known : 1
                        self.duration = (ratio > 1.8 && ratio < 2.2) ? known : itemDuration
                    }
                }
                
                // Track play count once past 10 seconds of listening
                if self.currentTime >= 10.0 && !self.playCountRecordedForCurrentTrack {
                    self.playCountRecordedForCurrentTrack = true
                    if let current = self.currentTrack {
                        self.playlistStore?.recordPlay(for: current)
                    }
                }
                
                self.checkTrimEnd()
                self.updateNowPlayingInfo()
            }
        }
        
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTrackEnded()
            }
        }
    }
    
    /// Moves on when the song reaches its custom end time (audio or video mode).
    private func checkTrimEnd() {
        guard let end = currentTrack?.endTime, end > 0, currentTime >= end, !trimEndReached else { return }
        trimEndReached = true
        AppLog.log("playback", "reached end time \(Int(end))s for \"\(currentTrack?.title ?? "-")\"")
        handleTrackEnded()
    }
    
    /// Applies new start/end times to the song that's playing now.
    public func applyRename(to trackId: UUID, title: String, artist: String) {
        guard currentTrack?.id == trackId else { return }
        currentTrack?.title = title
        currentTrack?.artist = artist
        updateNowPlayingInfo()
    }
    
    public func applyTrim(to trackId: UUID, start: Double?, end: Double?) {
        guard currentTrack?.id == trackId else { return }
        currentTrack?.startTime = (start ?? 0) > 0 ? start : nil
        currentTrack?.endTime = end
        trimEndReached = false
        if let start, start > 0, currentTime < start { seek(to: start) }
    }
    
    /// While lyrics are being synced the song must not move on (the lyrics would end up on the next song)
    public var holdForLyricsEditor = false
    
    private func handleTrackEnded() {
        if holdForLyricsEditor { player.pause(); isPlaying = false; return }
        if !playCountRecordedForCurrentTrack, let current = currentTrack {
            playCountRecordedForCurrentTrack = true
            playlistStore?.recordPlay(for: current)
        }
        
        switch repeatMode {
        case .one:
            trimEndReached = false
            seek(to: currentTrack?.startTime ?? 0)
            player.play()
            isPlaying = true
        case .all:
            next()
        case .off:
            if isShuffle {
                if shufflePointer + 1 < shuffledIndices.count {
                    next()
                } else {
                    isPlaying = false
                    currentTime = 0
                }
            } else {
                if currentIndex + 1 < queue.count {
                    next()
                } else {
                    isPlaying = false
                    currentTime = 0
                }
            }
        }
    }
    
    // MARK: - Smart Fisher-Yates Shuffle Algorithm
    private func generateSmartShuffle(startingWith track: MediaTrack) {
        guard !queue.isEmpty else { return }
        var indices = Array(0..<queue.count)
        
        if let currentIdx = queue.firstIndex(where: { $0.id == track.id }) {
            indices.removeAll { $0 == currentIdx }
            // Fisher-Yates shuffle: O(N) unbiased uniform distribution
            if indices.count > 1 {
                for i in stride(from: indices.count - 1, through: 1, by: -1) {
                    let j = Int.random(in: 0...i)
                    indices.swapAt(i, j)
                }
            }
            indices.insert(currentIdx, at: 0)
        }
        
        self.shuffledIndices = indices
        self.shufflePointer = 0
    }
    
    public func recordPlayCount() {
        guard !playCountRecordedForCurrentTrack, let current = currentTrack else { return }
        playCountRecordedForCurrentTrack = true
        playlistStore?.recordPlay(for: current)
    }
    
    public func setVideoViewActive(_ active: Bool) {
        guard isVideoViewActive != active else { return }
        isVideoViewActive = active
        AppLog.log("playback", "switched to \(active ? "VIDEO" : "MUSIC") view, track=\"\(currentTrack?.title ?? "-")\" youtubeId=\(currentTrack?.youtubeId ?? "nil")")
        
        if active {
            // Transitioning into Video View
            if currentTrack?.sourceType == .youtube && !audioFallbackActive {
                // Ensure AVPlayer is paused so only WKWebView outputs audio and video!
                player.pause()
                if isPlaying {
                    onWebPlayerAction?(.play)
                }
            }
        } else {
            // Transitioning into Music/Audio View
            if currentTrack?.sourceType == .youtube {
                // Pause WKWebView so it doesn't continue playing in background
                onWebPlayerAction?(.pause)
                if isPlaying {
                    let cmTime = CMTime(seconds: max(0, min(currentTime, duration)), preferredTimescale: 600)
                    player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
                    player.play()
                }
            }
        }
    }
    
    public func updateFromWebPlayer(time: TimeInterval, dur: TimeInterval) {
        guard webPlayerOwnsPlayback else { return }
        self.currentTime = time
        checkTrimEnd()
        if dur > 0 {
            self.duration = dur
        }
        if time >= 10.0 && !playCountRecordedForCurrentTrack {
            recordPlayCount()
        }
        updateNowPlayingInfo()
    }
    
    public func updateFromWebPlayer(state: Int) {
        // When not in Video mode, web player state events (like async pause upon switching to Music or Lyrics)
        // must never overwrite the playing state of the audio player!
        guard webPlayerOwnsPlayback else { return }
        let names = [-1: "unstarted", 0: "ended", 1: "playing", 2: "paused", 3: "buffering", 5: "cued"]
        AppLog.log("webplayer", "state \(names[state] ?? String(state)) video=\(currentTrack?.youtubeId ?? "nil")")
        // YT.PlayerState: UNSTARTED = -1, ENDED = 0, PLAYING = 1, PAUSED = 2, BUFFERING = 3, CUED = 5
        if state == 1 { // Playing
            self.isPlaying = true
            self.isLoading = false
            // Double check AVPlayer is paused to eliminate duplicate audio
            self.player.pause()
        } else if state == 2 { // Paused
            // Switching videos makes the previous one report "paused" just before the new one starts
            if Date().timeIntervalSince(webVideoLoadStartedAt) < 1.5 { return }
            self.isPlaying = false
        } else if state == 3 { // Buffering
            self.isLoading = true
        } else if state == 0 { // Ended
            self.handleTrackEnded()
        }
        updateNowPlayingInfo()
    }
    
    /// Plays the current video's audio through the audio player (used when the owner blocked embedding).
    private func startAudioFallback(for track: MediaTrack, videoId: String) {
        guard currentTrack?.id == track.id else { return }
        let resumeAt = max(currentTime, track.startTime ?? 0)
        audioFallbackActive = true
        isLoading = true
        errorMessage = "This video can't be shown in the app (the owner disabled embedding). Playing its audio instead."
        AppLog.log("webplayer", "embedding blocked for \(videoId): playing audio instead for \"\(track.title)\"")
        Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await YouTubeService.shared.resolveDirectStreamURL(for: "https://www.youtube.com/watch?v=\(videoId)", audioOnly: true)
                guard self.currentTrack?.id == track.id, self.audioFallbackActive else { return }
                let item = AVPlayerItem(url: url)
                await AudioLevelMeter.shared.attach(to: item)
                self.player.replaceCurrentItem(with: item)
                if resumeAt > 1 {
                    await self.player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                }
                self.player.play()
                self.isPlaying = true
                self.isLoading = false
                self.updateNowPlayingInfo()
            } catch {
                AppLog.log("webplayer", "audio fallback failed: \(error.localizedDescription)")
                self.isLoading = false
                self.errorMessage = "Couldn't play this video or its audio: \(error.localizedDescription)"
            }
        }
    }
    
    public func handleWebPlayerError(code: Int) {
        guard let current = currentTrack, let currentVid = current.youtubeId else {
            AppLog.log("webplayer", "error \(code) but no current video id")
            return
        }
        AppLog.log("webplayer", "error \(code) (\(Self.describeYouTubeError(code))) on \(currentVid) for \"\(current.title)\"")
        // 101 / 150 (and 152 / 153): the owner disabled embedding. The video is right, it just can't be
        // shown here, so keep it and play its audio rather than hopping to random alternatives.
        if [101, 150, 152, 153].contains(code), current.sourceType == .youtube {
            startAudioFallback(for: current, videoId: currentVid)
            return
        }
        failedVideoIds[current.id, default: []].insert(currentVid)
        let excluded = failedVideoIds[current.id] ?? []
        // Tracks added by link store the video URL; search by their title instead
        let addedByLink = current.originalURL.lowercased().hasPrefix("http")
        let query = current.videoSearchQuery
        Task { [weak self] in
            guard let self = self else { return }
            if let altVid = await YouTubeService.shared.resolveAlternativeVideoId(
                for: query,
                songTitle: addedByLink ? nil : current.title,
                artist: current.artist,
                movie: current.movieName,
                expectedDuration: current.duration,
                language: self.searchLanguage(for: current),
                excluding: excluded
            ), self.currentTrack?.id == current.id {
                self.currentTrack?.youtubeId = altVid
            } else if self.currentTrack?.id == current.id {
                self.errorMessage = "No playable official video found. Use \"Change Video\" to pick one."
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Video Feedback (👍 / 👎)
    
    /// True when the playing video is the one saved for this song (👍 given, or added by link).
    public var isCurrentVideoConfirmed: Bool {
        guard let current = currentTrack, let vid = current.youtubeId,
              let saved = playlistStore?.savedTrack(id: current.id) else { return false }
        return saved.youtubeId == vid
    }
    
    /// 👍 The right video: remember it so this song always plays it.
    public func confirmCurrentVideo() {
        guard let current = currentTrack, let vid = current.youtubeId else { return }
        playlistStore?.confirmVideo(trackId: current.id, videoId: vid)
        AppLog.log("feedback", "👍 \(vid) for \"\(current.title)\" by \(current.artist) language=\(searchLanguage(for: current) ?? "original")")
    }
    
    /// 👎 Wrong video: never pick it again for this song and switch to the next-best one now.
    public func rejectCurrentVideo() {
        guard let current = currentTrack, let vid = current.youtubeId, current.sourceType == .youtube else { return }
        playlistStore?.rejectVideo(trackId: current.id, videoId: vid)
        let rejected = Set((playlistStore?.savedTrack(id: current.id)?.rejectedVideoIds ?? []) + [vid])
            .union(failedVideoIds[current.id] ?? [])
        let language = searchLanguage(for: current)
        AppLog.log("feedback", "👎 \(vid) for \"\(current.title)\" by \(current.artist) language=\(language ?? "original") query=\"\(current.videoSearchQuery)\"")
        let addedByLink = current.originalURL.lowercased().hasPrefix("http")
        let resumeAt = currentTime
        isLoading = true
        Task { [weak self] in
            guard let self else { return }
            let alt = await YouTubeService.shared.resolveAlternativeVideoId(
                for: current.videoSearchQuery,
                songTitle: addedByLink ? nil : current.title,
                artist: current.artist,
                movie: current.movieName,
                expectedDuration: current.duration,
                language: language,
                excluding: rejected
            )
            guard self.currentTrack?.id == current.id else { return }
            guard let alt else {
                self.isLoading = false
                self.errorMessage = "No other official video found. Use \"Change Video\" to paste the right link."
                return
            }
            AppLog.log("feedback", "switching \"\(current.title)\" to \(alt)")
            var updated = current
            updated.youtubeId = alt
            updated.rejectedVideoIds = Array(rejected)
            self.playTrack(updated)
            // Keep listening from about the same spot
            if resumeAt > 10 {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if self.currentTrack?.id == current.id { self.seek(to: resumeAt) }
            }
        }
    }
    
    // MARK: - Language
    
    /// Language named by a playlist: "Telugu Music" → "telugu", "Bollywood Hits" → "hindi".
    /// Returns "" for non-Indian language playlists ("English Music": play the original) and
    /// nil when the name says nothing about language ("Music", "Favorites").
    static func playlistLanguage(_ name: String) -> String? {
        let n = name.lowercased()
        let indian: [(String, [String])] = [
            ("telugu", ["telugu", "tollywood"]), ("tamil", ["tamil", "kollywood"]),
            ("hindi", ["hindi", "bollywood"]), ("kannada", ["kannada", "sandalwood"]),
            ("malayalam", ["malayalam", "mollywood"]), ("marathi", ["marathi"]),
            ("punjabi", ["punjab"]), ("bengali", ["bengali", "bangla"])
        ]
        for (lang, words) in indian where words.contains(where: { n.contains($0) }) { return lang }
        let other = ["english", "spanish", "korean", "k-pop", "kpop", "japanese", "french", "arabic", "western"]
        if other.contains(where: { n.contains($0) }) { return "" }
        return nil
    }
    
    /// Which language version of `track` to play:
    /// 1. the language of the playlist it's being played from ("Hindi Music" → Hindi),
    /// 2. otherwise the language of the playlists it belongs to, when they agree,
    /// 3. otherwise the Preferred Song Language setting (Indian songs only).
    public func searchLanguage(for track: MediaTrack) -> String? {
        let playlists = playlistStore?.playlists ?? []
        if let pid = contextPlaylistId,
           let pl = playlists.first(where: { $0.id == pid }),
           pl.tracks.contains(where: { $0.id == track.id }),
           let lang = Self.playlistLanguage(pl.name) {
            return lang.isEmpty ? nil : lang
        }
        let containing = playlists.filter { pl in
            pl.tracks.contains { $0.id == track.id || (!$0.originalURL.isEmpty && $0.originalURL == track.originalURL) }
        }
        let langs = Set(containing.compactMap { Self.playlistLanguage($0.name) })
        if langs.count == 1, let lang = langs.first { return lang.isEmpty ? nil : lang }
        return track.searchLanguage
    }
    
    private static func describeYouTubeError(_ code: Int) -> String {
        switch code {
        case 2: return "invalid video id"
        case 5: return "HTML5 player error"
        case 100: return "video removed or private"
        case 101, 150: return "owner disabled embedding"
        case 152, 153: return "embed blocked / missing referrer"
        default: return "unknown"
        }
    }
    
    public func setVideoIdForTrack(trackId: UUID, newVideoId: String, newThumbnailURL: String? = nil) {
        playlistStore?.updateTrackVideo(trackId: trackId, newVideoId: newVideoId, newThumbnailURL: newThumbnailURL)
        if currentTrack?.id == trackId {
            currentTrack?.youtubeId = newVideoId
            currentTrack?.sourceType = .youtube
            currentTrack?.mediaType = .video
            if let thumb = newThumbnailURL {
                currentArtworkURL = thumb
            }
            if isVideoViewActive {
                onWebPlayerAction?(.play)
            }
        }
    }
    
    /// Where playback was started from; decides which language version of a song to play.
    public enum PlayContext {
        case unchanged            // next / previous / repeat: keep the current context
        case playlist(UUID)       // started from a playlist
        case none                 // Most Played, Singers, Search…
    }
    
    /// Playlist the current queue came from (its name may say which language to play in)
    public private(set) var contextPlaylistId: UUID?
    
    public func playTrack(_ track: MediaTrack, inQueue newQueue: [MediaTrack] = [], context: PlayContext = .unchanged) {
        switch context {
        case .unchanged: break
        case .playlist(let id): contextPlaylistId = id
        case .none: contextPlaylistId = nil
        }
        if !newQueue.isEmpty {
            self.queue = newQueue
            if let idx = newQueue.firstIndex(where: { $0.id == track.id }) {
                self.currentIndex = idx
            }
            if isShuffle {
                generateSmartShuffle(startingWith: track)
            }
        } else if !queue.contains(where: { $0.id == track.id }) {
            self.queue.append(track)
            self.currentIndex = self.queue.count - 1
            if isShuffle {
                generateSmartShuffle(startingWith: track)
            }
        }
        
        let language = searchLanguage(for: track)
        AppLog.log("playback", "language=\(language ?? "original") context=\(contextPlaylistId.flatMap { id in playlistStore?.playlists.first { $0.id == id }?.name } ?? "-")")
        AppLog.log("playback", "play \"\(track.title)\" by \(track.artist) source=\(track.sourceType.rawValue) youtubeId=\(track.youtubeId ?? "nil") movie=\(track.movieName ?? "-") query=\"\(track.videoSearchQuery)\" videoView=\(isVideoViewActive)")
        self.currentTrack = track
        self.currentArtworkURL = track.thumbnailURL
        self.lyrics = nil
        self.duration = track.duration
        // Web player reads currentTime as its start position, so begin at the trim start
        self.currentTime = track.startTime ?? 0
        self.trimEndReached = false
        self.audioFallbackActive = false
        self.errorMessage = nil
        self.isLoading = true
        self.isFetchingLyrics = true
        self.playCountRecordedForCurrentTrack = false
        
        // Immediately silence any previous AVPlayer audio
        self.player.pause()
        self.onWebPlayerAction?(.pause)
        
        // 1. Resolve official YouTube Video ID first (blazing fast ~250ms HTTP lookup with anti-lyric filter)
        Task { [weak self] in
            guard let self = self else { return }
            var resolvedVid = track.youtubeId
            if track.sourceType == .youtube && (resolvedVid == nil || resolvedVid?.isEmpty == true) {
                if let rejected = track.rejectedVideoIds, !rejected.isEmpty {
                    // Skip videos the user marked as wrong
                    resolvedVid = await YouTubeService.shared.resolveAlternativeVideoId(
                        for: track.videoSearchQuery,
                        songTitle: track.title,
                        artist: track.artist,
                        movie: track.movieName,
                        expectedDuration: track.duration,
                        language: language,
                        excluding: Set(rejected)
                    )
                } else {
                    resolvedVid = await YouTubeService.shared.fastResolveVideoId(
                        for: track.videoSearchQuery,
                        songTitle: track.title,
                        artist: track.artist,
                        movie: track.movieName,
                        expectedDuration: track.duration,
                        language: language
                    )
                }
                self.currentTrack?.youtubeId = resolvedVid
                AppLog.log("playback", "resolved video for \"\(track.title)\": \(resolvedVid ?? "nil")")
            }
            
            // 2. Fetch High-Res 1000x1000 Artwork in background
            Task { [weak self] in
                let localPath = track.sourceType == .local ? track.originalURL : nil
                if let highRes = await ArtworkService.shared.resolveHighResArtwork(
                    title: track.title,
                    artist: track.artist,
                    localFilePath: localPath
                ) {
                    self?.currentArtworkURL = highRes
                    self?.updateNowPlayingInfo()
                }
            }
            
            // 3. Fetch Synchronized Lyrics in background by default for every song
            Task { [weak self] in
                let fetched = await LyricsService.shared.fetchLyrics(
                    artist: track.artist,
                    title: track.title,
                    duration: track.duration
                )
                self?.lyrics = fetched
                self?.isFetchingLyrics = false
            }
            
            // 4. Start Playback based on current view mode
            if self.webPlayerOwnsPlayback {
                // If in Video Mode: WKWebView handles playback directly!
                // No need to wait for AVPlayer stream extraction!
                self.isPlaying = true
                self.isLoading = false
                self.updateNowPlayingInfo()
            } else {
                // In Audio Mode (or Local track): Resolve stream for AVPlayer
                do {
                    let resolvedURL: URL
                    if track.sourceType == .local {
                        resolvedURL = URL(fileURLWithPath: track.originalURL)
                    } else {
                        // Pass direct video URL using resolvedVid for 3x faster extraction
                        let streamTarget = (resolvedVid != nil && !resolvedVid!.isEmpty)
                            ? "https://www.youtube.com/watch?v=\(resolvedVid!)"
                            : track.originalURL
                        AppLog.log("playback", "audio stream target: \(streamTarget)")
                        resolvedURL = try await YouTubeService.shared.resolveDirectStreamURL(
                            for: streamTarget,
                            audioOnly: true
                        )
                    }
                    
                    let item = AVPlayerItem(url: resolvedURL)
                    await AudioLevelMeter.shared.attach(to: item)   // feeds the visualizer
                    self.player.replaceCurrentItem(with: item)
                    if let start = track.startTime, start > 0 {
                        await self.player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                    }
                    
                    // Only play AVPlayer if we are STILL in Audio mode
                    if !self.webPlayerOwnsPlayback {
                        self.player.play()
                        self.isPlaying = true
                    }
                    self.isLoading = false
                    self.updateNowPlayingInfo()
                } catch {
                    AppLog.log("playback", "audio stream failed: \(error.localizedDescription)")
                    self.errorMessage = "Failed to load stream: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    public func togglePlayPause() {
        // Video mode with a live web player: control it; the button follows its reported state.
        // (If no web player is connected, fall through to the audio player instead of only flipping the icon.)
        if webPlayerOwnsPlayback && onWebPlayerAction != nil {
            if isPlaying {
                isPlaying = false
                onWebPlayerAction?(.pause)
                player.pause()
            } else {
                isPlaying = true
                player.pause() // Ensure AVPlayer is NOT producing sound
                onWebPlayerAction?(.play)
            }
        } else {
            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                if player.currentItem == nil, let track = currentTrack {
                    playTrack(track)
                } else {
                    player.play()
                    isPlaying = true
                }
            }
        }
        updateNowPlayingInfo()
    }
    
    /// Lyrics were edited: look them up again for the playing song (yours come first)
    public func reloadLyrics() {
        guard let track = currentTrack else { return }
        Task { [weak self] in
            let fetched = await LyricsService.shared.fetchLyrics(artist: track.artist, title: track.title, duration: track.duration)
            guard self?.currentTrack?.id == track.id else { return }
            self?.lyrics = fetched
        }
    }
    
    public func seek(to seconds: TimeInterval) {
        currentTime = seconds
        if webPlayerOwnsPlayback {
            onWebPlayerAction?(.seek(seconds))
        } else {
            let cmTime = CMTime(seconds: max(0, min(seconds, duration)), preferredTimescale: 600)
            player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        updateNowPlayingInfo()
    }
    
    public func next() {
        guard !queue.isEmpty else { return }
        if let current = currentTrack {
            historyStack.append(current)
        }
        
        if isShuffle {
            if shuffledIndices.isEmpty || shuffledIndices.count != queue.count {
                if let current = currentTrack {
                    generateSmartShuffle(startingWith: current)
                }
            }
            
            shufflePointer += 1
            if shufflePointer >= shuffledIndices.count {
                if repeatMode == .all {
                    if let first = queue.first {
                        generateSmartShuffle(startingWith: first)
                    }
                    shufflePointer = 0
                } else {
                    isPlaying = false
                    currentTime = 0
                    return
                }
            }
            let nextIndex = shuffledIndices[shufflePointer]
            currentIndex = nextIndex
            playTrack(queue[nextIndex])
        } else {
            currentIndex = (currentIndex + 1) % queue.count
            playTrack(queue[currentIndex])
        }
    }
    
    public func previous() {
        guard !queue.isEmpty else { return }
        let start = currentTrack?.startTime ?? 0
        if currentTime > start + 3.0 {
            seek(to: start)
            return
        }
        
        if let prev = historyStack.popLast() {
            playTrack(prev)
            return
        }
        
        if currentIndex > 0 {
            currentIndex -= 1
        } else {
            currentIndex = queue.count - 1
        }
        playTrack(queue[currentIndex])
    }
    
    public func toggleShuffle() {
        isShuffle.toggle()
        if isShuffle, let current = currentTrack {
            generateSmartShuffle(startingWith: current)
        }
    }
    
    public func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }
    
    public func toggleMute() {
        isMuted.toggle()
    }
    
    public func toggleAudioOnly() {
        isAudioOnly.toggle()
        if let current = currentTrack, current.sourceType == .youtube {
            let savedTime = currentTime
            playTrack(current)
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                await MainActor.run {
                    self.seek(to: savedTime)
                }
            }
        }
    }
    
    // macOS Remote Commands & Now Playing
    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Go through togglePlayPause so video mode (web player) is handled too
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                AppLog.log("keys", "media key: play")
                if self?.isPlaying == false { self?.togglePlayPause() }
            }
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                AppLog.log("keys", "media key: pause")
                if self?.isPlaying == true { self?.togglePlayPause() }
            }
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                AppLog.log("keys", "media key: togglePlayPauseCommand")
                self?.togglePlayPause()
            }
            return .success
        }
        
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                AppLog.log("keys", "media key: nextTrackCommand")
                self?.next()
            }
            return .success
        }
        
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                AppLog.log("keys", "media key: previousTrackCommand")
                self?.previous()
            }
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let pos = positionEvent.positionTime
            Task { @MainActor in
                self?.seek(to: pos)
            }
            return .success
        }
    }
    
    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            return
        }
        
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        // macOS routes the keyboard's media keys only to apps that publish a playback state
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }
}
