import Foundation
import SwiftUI
import Combine
import AVFoundation
import MediaPlayer
import WebKit

public enum PlaybackDisplayMode: String, CaseIterable, Sendable {
    case audio = "Audio"
    case video = "Video"
    case lyrics = "Lyrics"
}

@MainActor
public class PlaybackManager: NSObject, ObservableObject, WKScriptMessageHandler {
    public static let shared = PlaybackManager()
    
    // Playback state
    @Published public var currentTrack: MediaTrack?
    @Published public var isPlaying: Bool = false
    @Published public var currentTime: TimeInterval = 0
    @Published public var duration: TimeInterval = 0
    @Published public var isShuffled: Bool = false
    @Published public var repeatMode: Int = 0 // 0: off, 1: all, 2: one
    
    // Display Mode: Audio (Album Art), Video (YouTube), Lyrics (Karaoke)
    @Published public var displayMode: PlaybackDisplayMode = .audio
    
    // Lyrics state
    @Published public var lyrics: SongLyrics?
    @Published public var currentLyricIndex: Int = 0
    @Published public var isLyricsLoading: Bool = false
    
    // Active high-res artwork URL
    @Published public var activeArtworkURL: String?
    
    // Queue & History
    @Published public var queue: [MediaTrack] = []
    @Published public var originalQueue: [MediaTrack] = []
    @Published public var currentIndex: Int = 0
    
    // Global Persistent WKWebView Engine
    public var webView: WKWebView!
    private var isPlayerReady: Bool = false
    private var currentLoadedVideoId: String?
    
    public override init() {
        super.init()
        setupAudioSession()
        setupAudioSession()
        setupRemoteCommands()
        setupWebPlayer()
        setupLifecycleObservers()
        
        // Initial track readiness
        if let first = PlaylistStore.shared.favoritesPlaylist?.tracks.first ?? PlaylistStore.shared.playlists.first(where: { !$0.tracks.isEmpty })?.tracks.first {
            self.currentTrack = first
            self.duration = first.duration
            self.activeArtworkURL = first.thumbnailURL
            self.originalQueue = [first]
            self.queue = [first]
            self.currentIndex = 0
            loadLyrics(for: first)
            if let vid = first.youtubeId, !vid.isEmpty {
                loadVideo(id: vid, autoPlay: false)
            }
        }
    }
    
    // MARK: - Audio Session & Background Audio
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay])
            try session.setActive(true)
        } catch {
            print("Failed to activate AVAudioSession: \(error)")
        }
    }
    
    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func handleAppDidEnterBackground() {
        if isPlaying {
            BackgroundAudioKeepAlive.shared.start()
            webView.evaluateJavaScript("if (window.userWantsPlaying && player && player.playVideo) { player.playVideo(); }", completionHandler: nil)
            updateNowPlayingInfo()
        }
    }
    
    @objc private func handleAppWillEnterForeground() {
        if isPlaying {
            webView.evaluateJavaScript("if (window.userWantsPlaying && player && player.playVideo) { player.playVideo(); }", completionHandler: nil)
            updateNowPlayingInfo()
        }
    }
    
    // MARK: - Global Web Player Engine
    
    private func setupWebPlayer() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        config.userContentController.add(self, name: "playerState")
        config.userContentController.add(self, name: "timeUpdate")
        config.userContentController.add(self, name: "playerError")
        config.userContentController.add(self, name: "playerReady")
        
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 180), configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.isScrollEnabled = false
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
        self.webView = wv
    }
    
    public func loadVideo(id: String, autoPlay: Bool = true) {
        self.currentLoadedVideoId = id
        self.isPlayerReady = false
        let startSec = Int(currentTrack?.startTime ?? currentTime)
        
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>
          html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: #000; overflow: hidden; }
          #player { position: absolute; top: 0; left: 0; width: 100%; height: 100%; border: none; }
        </style>
        <script src="https://www.youtube.com/iframe_api"></script>
        </head>
        <body>
          <div id="player"></div>
          <script>
            // Neutralize Page Visibility API so YouTube never auto-pauses on screen lock or backgrounding
            try {
              Object.defineProperty(document, 'hidden', { get: function() { return false; }, configurable: true });
              Object.defineProperty(document, 'visibilityState', { get: function() { return 'visible'; }, configurable: true });
              Object.defineProperty(document, 'webkitVisibilityState', { get: function() { return 'visible'; }, configurable: true });
              window.addEventListener('visibilitychange', function(e) { e.stopImmediatePropagation(); }, true);
              window.addEventListener('webkitvisibilitychange', function(e) { e.stopImmediatePropagation(); }, true);
              window.addEventListener('blur', function(e) { e.stopImmediatePropagation(); }, true);
              window.addEventListener('pagehide', function(e) { e.stopImmediatePropagation(); }, true);
            } catch(e) {}

            var player;
            var isReady = false;
            var timeInterval = null;
            window.userWantsPlaying = \(autoPlay ? "true" : "false");

            function onYouTubeIframeAPIReady() {
              player = new YT.Player('player', {
                videoId: '\(id)',
                playerVars: {
                  'autoplay': \(autoPlay ? 1 : 0),
                  'playsinline': 1,
                  'controls': 1,
                  'rel': 0,
                  'modestbranding': 1,
                  'enablejsapi': 1,
                  'fs': 1,
                  'origin': 'https://auraplayer.app',
                  'widget_referrer': 'https://auraplayer.app',
                  'start': \(startSec)
                },
                events: {
                  'onReady': onPlayerReady,
                  'onStateChange': onPlayerStateChange,
                  'onError': onPlayerError
                }
              });
            }

            function onPlayerReady(event) {
              isReady = true;
              window.webkit.messageHandlers.playerReady.postMessage("ready");
              try { event.target.unMute(); } catch(e){}
              try { event.target.setVolume(100); } catch(e){}
              if (\(autoPlay)) {
                window.userWantsPlaying = true;
                event.target.playVideo();
              }
              startTimeTracker();
            }

            function onPlayerStateChange(event) {
              if (event.data === 1) { // Playing
                window.userWantsPlaying = true;
                try { player.unMute(); } catch(e){}
                try { player.setVolume(100); } catch(e){}
                startTimeTracker();
                window.webkit.messageHandlers.playerState.postMessage(event.data);
              } else if (event.data === 2) { // Paused
                if (window.userWantsPlaying) {
                  // Prevent unwanted background auto-pausing by WebKit / YouTube
                  setTimeout(function() {
                    if (window.userWantsPlaying && player && player.playVideo) {
                      player.playVideo();
                    }
                  }, 100);
                  return;
                }
                stopTimeTracker();
                window.webkit.messageHandlers.playerState.postMessage(event.data);
              } else if (event.data === 0) { // Ended
                stopTimeTracker();
                window.webkit.messageHandlers.playerState.postMessage(event.data);
              }
            }

            function onPlayerError(event) {
              window.webkit.messageHandlers.playerError.postMessage(event.data);
            }

            function startTimeTracker() {
              if (timeInterval) clearInterval(timeInterval);
              timeInterval = setInterval(function() {
                if (player && player.getCurrentTime && player.getDuration) {
                  var cur = player.getCurrentTime();
                  var dur = player.getDuration();
                  window.webkit.messageHandlers.timeUpdate.postMessage({ current: cur, duration: dur });
                }
              }, 250);
            }

            function stopTimeTracker() {
              if (timeInterval) {
                clearInterval(timeInterval);
                timeInterval = null;
              }
            }

            function playVideo() {
              window.userWantsPlaying = true;
              if (player && player.playVideo) {
                try { player.unMute(); } catch(e){}
                try { player.setVolume(100); } catch(e){}
                player.playVideo();
              }
            }

            function pauseVideo() {
              window.userWantsPlaying = false;
              if (player && player.pauseVideo) player.pauseVideo();
            }

            function seekTo(sec) {
              if (player && player.seekTo) player.seekTo(sec, true);
            }
          </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://auraplayer.app"))
    }
    
    // MARK: - WKScriptMessageHandler
    
    nonisolated public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor in
            self.handleScriptMessage(message)
        }
    }
    
    private func handleScriptMessage(_ message: WKScriptMessage) {
        if message.name == "playerReady" {
            self.isPlayerReady = true
            if self.isPlaying {
                self.webView.evaluateJavaScript("playVideo();", completionHandler: nil)
            }
        } else if message.name == "playerState", let state = message.body as? Int {
            switch state {
            case 1: // Playing
                self.isPlaying = true
                BackgroundAudioKeepAlive.shared.start()
            case 2: // Paused
                self.isPlaying = false
                BackgroundAudioKeepAlive.shared.stop()
            case 0: // Ended
                self.isPlaying = false
                BackgroundAudioKeepAlive.shared.stop()
                self.playNext()
            default:
                break
            }
            self.updateNowPlayingInfo()
        } else if message.name == "timeUpdate", let dict = message.body as? [String: Any],
                  let current = dict["current"] as? Double,
                  let dur = dict["duration"] as? Double {
            self.currentTime = current
            if dur > 0 { self.duration = dur }
            
            // Check trim end time
            if let end = currentTrack?.endTime, end > 0, current >= end {
                playNext()
                return
            }
            
            self.updateCurrentLyricIndex()
        } else if message.name == "playerError", let code = message.body as? Int {
            print("YouTube Player Error code: \(code)")
            self.handlePlayerError(code)
        }
    }
    
    private func handlePlayerError(_ code: Int) {
        guard let track = currentTrack else { return }
        print("YouTube embed error \(code) on track: \(track.title)")
        if [101, 150, 152, 153].contains(code) {
            // Video owner restricted embedding on this specific ID.
            // Automatically find an alternate lyric/audio upload:
            Task {
                let altQuery = "\(track.title) \(track.artist) audio"
                let results = await YouTubeService.shared.search(query: altQuery)
                if let alt = results.first(where: { $0.id != track.youtubeId }) {
                    print("Falling back to alternate playable video: \(alt.id)")
                    self.currentTrack?.youtubeId = alt.id
                    self.loadVideo(id: alt.id)
                }
            }
        }
    }
    
    // MARK: - Lock Screen & Control Center
    
    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.playNext()
            return .success
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.playPrevious()
            return .success
        }
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: posEvent.positionTime)
            return .success
        }
    }
    
    public func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime
        ]
        
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        
        if let artStr = activeArtworkURL ?? track.thumbnailURL, let artURL = URL(string: artStr) {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: artURL),
                   let image = UIImage(data: data) {
                    let mpArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    info[MPMediaItemPropertyArtwork] = mpArtwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
            }
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    // MARK: - Playback Control
    
    public func playTrack(_ track: MediaTrack, inQueue tracks: [MediaTrack] = []) {
        self.currentTrack = track
        self.currentTime = 0
        self.duration = track.duration
        self.isPlaying = true
        
        if !tracks.isEmpty {
            self.originalQueue = tracks
            self.queue = isShuffled ? tracks.shuffled() : tracks
            if let idx = self.queue.firstIndex(where: { $0.id == track.id }) {
                self.currentIndex = idx
            }
        } else if queue.isEmpty {
            self.originalQueue = [track]
            self.queue = [track]
            self.currentIndex = 0
        }
        
        PlaylistStore.shared.recordPlay(track: track)
        
        // Auto-resolve high-res artwork
        self.activeArtworkURL = track.thumbnailURL
        Task {
            if let highRes = await ArtworkService.shared.resolveHighResArtwork(title: track.title, artist: track.artist) {
                self.activeArtworkURL = highRes
                self.updateNowPlayingInfo()
            }
        }
        
        // Load lyrics
        loadLyrics(for: track)
        
        // Load and play video
        if let vid = track.youtubeId {
            loadVideo(id: vid)
        } else {
            Task {
                if let vid = await YouTubeService.shared.resolveVideoId(for: track.title, artist: track.artist) {
                    self.currentTrack?.youtubeId = vid
                    self.loadVideo(id: vid)
                }
            }
        }
        
        updateNowPlayingInfo()
    }
    
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }
    
    public func resume() {
        isPlaying = true
        BackgroundAudioKeepAlive.shared.start()
        if currentLoadedVideoId == nil, let track = currentTrack, let vid = track.youtubeId, !vid.isEmpty {
            loadVideo(id: vid, autoPlay: true)
        } else {
            webView.evaluateJavaScript("playVideo();", completionHandler: nil)
        }
        updateNowPlayingInfo()
    }
    
    public func pause() {
        isPlaying = false
        BackgroundAudioKeepAlive.shared.stop()
        webView.evaluateJavaScript("pauseVideo();", completionHandler: nil)
        updateNowPlayingInfo()
    }
    
    public func seek(to time: TimeInterval) {
        currentTime = time
        webView.evaluateJavaScript("seekTo(\(time));", completionHandler: nil)
        updateCurrentLyricIndex()
        updateNowPlayingInfo()
    }
    
    public func playNext() {
        guard !queue.isEmpty else { return }
        if currentIndex + 1 < queue.count {
            currentIndex += 1
            playTrack(queue[currentIndex], inQueue: queue)
        } else if repeatMode == 1 {
            currentIndex = 0
            playTrack(queue[0], inQueue: queue)
        }
    }
    
    public func playPrevious() {
        if currentTime > 3.0 {
            seek(to: 0)
            return
        }
        guard !queue.isEmpty else { return }
        if currentIndex > 0 {
            currentIndex -= 1
            playTrack(queue[currentIndex], inQueue: queue)
        } else {
            seek(to: 0)
        }
    }
    
    public func toggleShuffle() {
        isShuffled.toggle()
        guard let current = currentTrack else { return }
        if isShuffled {
            var shuffled = originalQueue.filter { $0.id != current.id }.shuffled()
            shuffled.insert(current, at: 0)
            queue = shuffled
            currentIndex = 0
        } else {
            queue = originalQueue
            if let idx = queue.firstIndex(where: { $0.id == current.id }) {
                currentIndex = idx
            }
        }
    }
    
    // MARK: - Lyrics Synchronization
    
    private func loadLyrics(for track: MediaTrack) {
        self.lyrics = nil
        self.currentLyricIndex = 0
        self.isLyricsLoading = true
        
        Task {
            let fetched = await LyricsService.shared.fetchLyrics(
                artist: track.artist,
                title: track.title,
                duration: track.duration
            )
            self.lyrics = fetched
            self.isLyricsLoading = false
        }
    }
    
    private func updateCurrentLyricIndex() {
        guard let lines = lyrics?.syncedLines, !lines.isEmpty else { return }
        var bestIndex = 0
        for (i, line) in lines.enumerated() {
            if currentTime >= line.time {
                bestIndex = i
            } else {
                break
            }
        }
        if bestIndex != currentLyricIndex {
            currentLyricIndex = bestIndex
        }
    }
}
