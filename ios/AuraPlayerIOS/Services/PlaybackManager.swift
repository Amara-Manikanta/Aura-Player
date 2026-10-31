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
    /// Position in the song. Not published here: see `PlaybackClock`
    public let clock = PlaybackClock()
    public var currentTime: TimeInterval {
        get { clock.time }
        set { clock.time = newValue }
    }
    @Published public var duration: TimeInterval = 0
    @Published public var isShuffled: Bool = false
    @Published public var repeatMode: Int = 0 // 0: off, 1: all, 2: one
    
    // Display Mode: Audio (Album Art), Video (YouTube), Lyrics (Karaoke)
    @Published public var displayMode: PlaybackDisplayMode = .audio
    
    // Lyrics state
    @Published public var lyrics: SongLyrics?
    @Published public var currentLyricIndex: Int = 0
    @Published public var isLyricsLoading: Bool = false
    
    /// Shown to the user when a song can't be played (e.g. no video found)
    @Published public var errorMessage: String?
    
    /// Where playback started from; decides which language version of a song to play
    public enum PlayContext { case unchanged, playlist(UUID), none }
    public private(set) var contextPlaylistId: UUID?
    /// Videos that failed (blocked from embedding / removed) per song, so fallbacks never retry them
    private var failedVideoIds: [UUID: Set<String>] = [:]
    
    // Active high-res artwork URL
    @Published public var activeArtworkURL: String?
    
    // Queue & History
    @Published public var queue: [MediaTrack] = []
    @Published public var originalQueue: [MediaTrack] = []
    @Published public var currentIndex: Int = 0
    
    // Global Persistent WKWebView Engine
    public var webView: WKWebView!
    
    /// Screens currently able to show the video, most recent last; the last one holds the player
    @Published public private(set) var videoHosts: [String] = []
    public var activeVideoHost: String? { videoHosts.last }
    
    public func registerVideoHost(_ id: String) {
        videoHosts.removeAll { $0 == id }
        videoHosts.append(id)
    }
    
    public func unregisterVideoHost(_ id: String) {
        videoHosts.removeAll { $0 == id }
    }
    private var isPlayerReady: Bool = false
    private var currentLoadedVideoId: String?
    /// The song passed its custom end time; "next" must fire only once
    private var trimEndHandled = false
    /// A play is counted after 10 s of listening, not on tap
    private var playCounted = false
    private var appInBackground = false
    
    public override init() {
        super.init()
        setupAudioSession()
        setupRemoteCommands()
        setupWebPlayer()
        setupLifecycleObservers()
        
        // Pick up where the app was closed
        if let memory = PlaybackMemory.load() {
            restore(memory)
            return
        }
        
        // Nothing remembered yet: the first song of Favorites
        if let first = PlaylistStore.shared.favoritesPlaylist?.tracks.first ?? PlaylistStore.shared.playlists.first(where: { !$0.tracks.isEmpty })?.tracks.first {
            self.currentTrack = first
            self.duration = first.duration
            self.activeArtworkURL = first.thumbnailURL
            self.originalQueue = [first]
            self.queue = [first]
            self.currentIndex = 0
            loadLyrics(for: first)
            if let vid = first.youtubeId, !vid.isEmpty {
                loadVideo(id: vid, autoPlay: false, startAt: first.startTime ?? 0)
            }
        }
    }
    
    // MARK: - Audio Session & Background Audio
    
    // MARK: - Remember what was playing
    
    private var lastMemorySave = Date.distantPast
    
    /// Saves the song, queue and position (the position at most every 5 s while playing)
    private func rememberPlayback(force: Bool = true) {
        guard let track = currentTrack else { return }
        if !force && Date().timeIntervalSince(lastMemorySave) < 5 { return }
        lastMemorySave = Date()
        let store = PlaylistStore.shared
        let inLibrary = Set(store.allUniqueTracks.map(\.id))
        let allInLibrary = queue.allSatisfy { inLibrary.contains($0.id) }
        PlaybackMemory(
            track: track,
            queueIds: allInLibrary ? queue.map(\.id) : nil,
            queueTracks: allInLibrary ? nil : Array(queue.prefix(100)),
            position: currentTime,
            contextPlaylistId: contextPlaylistId,
            shuffled: isShuffled,
            repeatMode: repeatMode,
            displayMode: displayMode.rawValue
        ).save()
    }
    
    private func restore(_ memory: PlaybackMemory) {
        let store = PlaylistStore.shared
        // The library's copy has any later edits (start/end time, changed video link)
        var track = store.savedTrack(id: memory.track.id) ?? memory.track
        // Songs saved by name only had their video found while playing: keep that one
        if (track.youtubeId ?? "").isEmpty { track.youtubeId = memory.track.youtubeId }
        var queue = memory.queueTracks ?? []
        if let ids = memory.queueIds {
            let byId = Dictionary(store.allUniqueTracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            queue = ids.compactMap { byId[$0] }
        }
        if !queue.contains(where: { $0.id == track.id }) { queue = [track] }
        
        contextPlaylistId = memory.contextPlaylistId
        isShuffled = memory.shuffled
        repeatMode = memory.repeatMode
        displayMode = PlaybackDisplayMode(rawValue: memory.displayMode) ?? .audio
        currentTrack = track
        self.queue = queue
        originalQueue = queue
        currentIndex = queue.firstIndex { $0.id == track.id } ?? 0
        duration = track.duration
        activeArtworkURL = track.effectiveThumbnailURL
        Task {
            if let cover = await TrackArtworkService.shared.cover(for: track), self.currentTrack?.id == track.id {
                self.activeArtworkURL = cover.absoluteString
            }
        }
        // Near the very end: start the song again instead
        let end = track.endTime ?? track.duration
        let position = (end > 0 && memory.position > end - 5) ? (track.startTime ?? 0) : max(memory.position, track.startTime ?? 0)
        currentTime = position
        loadLyrics(for: track)
        if let vid = track.youtubeId, !vid.isEmpty {
            loadVideo(id: vid, autoPlay: false, startAt: position)
        }
    }
    
    /// Repeat / display mode changed from a view
    public func rememberSettings() { rememberPlayback() }
    
    private func setupAudioSession() {
        BackgroundAudioKeepAlive.activateSession()   // off the main thread
    }
    
    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { n in
            AppLog.log("route change reason=\(n.userInfo?[AVAudioSessionRouteChangeReasonKey] ?? "?")")
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { _ in
            AppLog.log("media services reset")
        }
        // A call, alarm or Siri pauses the audio; pick it back up when iOS says it's over
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
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
        AppLog.log("app -> background playing=\(isPlaying) session=\(AVAudioSession.sharedInstance().category.rawValue) otherAudio=\(AVAudioSession.sharedInstance().isOtherAudioPlaying)")
        appInBackground = true
        rememberPlayback()
        webView.evaluateJavaScript("window.appInBackground = true;", completionHandler: nil)
        if isPlaying {
            BackgroundAudioKeepAlive.shared.start()
            webView.evaluateJavaScript("if (window.userWantsPlaying && player && player.playVideo) { player.playVideo(); }", completionHandler: nil)
            updateNowPlayingInfo()
        }
    }
    
    private var wasPlayingBeforeInterruption = false
    /// Counts the user's pauses, so a resume scheduled before one never undoes it
    private var pauseEpoch = 0
    
    @objc private func handleAudioInterruption(_ note: Notification) {
        AppLog.log("audio interruption \(note.userInfo ?? [:])")
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began {
            wasPlayingBeforeInterruption = isPlaying
        } else if wasPlayingBeforeInterruption {
            wasPlayingBeforeInterruption = false
            let epoch = pauseEpoch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, self.pauseEpoch == epoch else { return }
                self.isPlaying = true
                if self.appInBackground { BackgroundAudioKeepAlive.shared.start() }
                self.webView.evaluateJavaScript("playVideo();", completionHandler: nil)
                self.updateNowPlayingInfo()
            }
        }
    }
    
    @objc private func handleAppWillEnterForeground() {
        AppLog.log("app -> foreground playing=\(isPlaying)")
        appInBackground = false
        BackgroundAudioKeepAlive.shared.stop()
        webView.evaluateJavaScript("window.appInBackground = false;", completionHandler: nil)
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
        // YouTube's own full-screen button (does nothing unless element full screen is enabled)
        config.preferences.isElementFullscreenEnabled = true
        
        // YouTube's player lives in a cross-origin iframe, which the page's own script can't reach:
        // inside it, "page hidden" made YouTube pause itself right after the app went to the background.
        // A user script runs in every frame, so it can make them all report "visible".
        let visible = WKUserScript(source: """
            (function() {
              try {
                Object.defineProperty(document, 'hidden', { get: function() { return false; }, configurable: true });
                Object.defineProperty(document, 'visibilityState', { get: function() { return 'visible'; }, configurable: true });
                Object.defineProperty(document, 'webkitHidden', { get: function() { return false; }, configurable: true });
                Object.defineProperty(document, 'webkitVisibilityState', { get: function() { return 'visible'; }, configurable: true });
                var stop = function(e) { e.stopImmediatePropagation(); };
                document.addEventListener('visibilitychange', stop, true);
                document.addEventListener('webkitvisibilitychange', stop, true);
                window.addEventListener('pagehide', stop, true);
                window.addEventListener('blur', stop, true);
              } catch (e) {}
            })();
            """, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(visible)
        config.userContentController.add(self, name: "playerState")
        config.userContentController.add(self, name: "timeUpdate")
        config.userContentController.add(self, name: "playerError")
        config.userContentController.add(self, name: "playerReady")
        config.userContentController.add(self, name: "debugLog")
        
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 180), configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.isScrollEnabled = false
        // Taps on the video would pause it behind the app's back; the app has its own controls
        wv.isUserInteractionEnabled = false
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
        self.webView = wv
    }
    
    /// `startAt` defaults to the current position (e.g. resuming the same song)
    /// Where a song that was only cued (not playing yet) should begin: YouTube ignores its start
    /// setting until the video has played, so the app seeks there itself.
    private var pendingResume: Double?
    
    public func loadVideo(id: String, autoPlay: Bool = true, startAt: Double? = nil) {
        pendingResume = autoPlay ? nil : startAt.flatMap { $0 > 1 ? $0 : nil }
        self.currentLoadedVideoId = id
        self.isPlayerReady = false
        let startSec = Int(startAt ?? currentTime)
        
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
            window.appInBackground = \(appInBackground ? "true" : "false");

            function onYouTubeIframeAPIReady() {
              player = new YT.Player('player', {
                videoId: '\(id)',
                playerVars: {
                  'autoplay': \(autoPlay ? 1 : 0),
                  'playsinline': 1,
                  'controls': 0,
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

            // iOS pauses web video on its own whenever the player view moves (player sheet, full
            // screen, theme switch) or the app goes to the background, and resumes it on its own
            // later. The app's buttons are the only source of truth: undo anything else.
            var autoResumes = 0, lastAutoResume = 0;

            // The next song is being looked up: the old video must stay quiet until it's replaced
            function stopForSwitch() {
              window.switching = true;
              window.userWantsPlaying = false;
              stopTimeTracker();
              try { player.pauseVideo(); } catch(e){}
            }

            function onPlayerStateChange(event) {
              try { window.webkit.messageHandlers.debugLog.postMessage("js state=" + event.data + " wants=" + window.userWantsPlaying + " bg=" + window.appInBackground + " resumes=" + autoResumes); } catch(e){}
              if (window.switching) return;
              if ((event.data === 1 || event.data === 3) && !window.userWantsPlaying) {
                // Started by iOS, not the user: keep it paused
                try { player.pauseVideo(); } catch(e){}
                return;
              }
              if (event.data === 1) { // Playing
                window.userWantsPlaying = true;
                try { player.unMute(); } catch(e){}
                try { player.setVolume(100); } catch(e){}
                startTimeTracker();
                window.webkit.messageHandlers.playerState.postMessage(event.data);
              } else if (event.data === 2) { // Paused
                if (window.userWantsPlaying) {
                  // Paused by iOS, not the user: resume (but give up if iOS keeps pausing it)
                  var now = Date.now();
                  if (now - lastAutoResume > 8000) autoResumes = 0;
                  if (autoResumes < 3 || window.appInBackground) {
                    autoResumes++;
                    lastAutoResume = now;
                    setTimeout(function() {
                      if (window.userWantsPlaying && player && player.playVideo) player.playVideo();
                    }, 150);
                    return;
                  }
                }
                window.userWantsPlaying = false;
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
                if (window.switching) return;
                if (player && player.getCurrentTime && player.getDuration) {
                  var cur = player.getCurrentTime();
                  var dur = player.getDuration();
                  window.webkit.messageHandlers.timeUpdate.postMessage({ current: cur, duration: dur });
                }
              }, 100);
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
        if message.name == "debugLog" { AppLog.log("\(message.body)"); return }
        if message.name == "playerReady" {
            self.isPlayerReady = true
            if let p = pendingResume { webView.evaluateJavaScript("seekTo(\(p));", completionHandler: nil) }
            if self.isPlaying {
                self.webView.evaluateJavaScript("playVideo();", completionHandler: nil)
            }
        } else if message.name == "playerState", let state = message.body as? Int {
            AppLog.log("yt state=\(state) bg=\(appInBackground) wantedPlaying=\(isPlaying)")
            switch state {
            case 1: // Playing
                if let p = pendingResume {
                    // first play after a restore: make sure it's at the saved spot
                    pendingResume = nil
                    webView.evaluateJavaScript("if (player && player.getCurrentTime && player.getCurrentTime() < \(p) - 2) { player.seekTo(\(p), true); }", completionHandler: nil)
                }
                self.isPlaying = true
                if self.appInBackground { BackgroundAudioKeepAlive.shared.start() }
            case 2: // Paused
                self.isPlaying = false
                BackgroundAudioKeepAlive.shared.stop()
            case 0: // Ended
                handleTrackEnded()
            default:
                break
            }
            self.updateNowPlayingInfo()
        } else if message.name == "timeUpdate", let dict = message.body as? [String: Any],
                  let current = dict["current"] as? Double,
                  let dur = dict["duration"] as? Double {
            // A restored song waiting to be played reports "0" from its start: that isn't where we are
            if pendingResume != nil { return }
            self.currentTime = current
            if dur > 0 && dur != self.duration { self.duration = dur }
            rememberPlayback(force: false)   // @Published fires on every assignment
            
            if current >= 10, !playCounted, let track = currentTrack {
                playCounted = true
                PlaylistStore.shared.recordPlay(track: track)
            }
            
            // Custom end time: move on once (time updates keep arriving until the next song loads)
            if let end = currentTrack?.endTime, end > 0, current >= end, !trimEndHandled {
                trimEndHandled = true
                handleTrackEnded()
                return
            }
            
            self.updateCurrentLyricIndex()
        } else if message.name == "playerError", let code = message.body as? Int {
            print("YouTube Player Error code: \(code)")
            self.handlePlayerError(code)
        }
    }
    
    /// The video can't be played here (owner blocked embedding, or removed): switch to the next-best
    /// official video of the same song, never one that already failed. (Used to take the first result
    /// for "title artist audio", which was often a different song.)
    private func handlePlayerError(_ code: Int) {
        guard let track = currentTrack, let failedId = track.youtubeId else { return }
        print("YouTube embed error \(code) on \(failedId) for \(track.title)")
        failedVideoIds[track.id, default: []].insert(failedId)
        let excluded = failedVideoIds[track.id, default: []].union(track.rejectedVideoIds ?? [])
        let language = searchLanguage(for: track)
        Task {
            let alt = await YouTubeService.shared.resolveVideo(for: track, language: language, excluding: excluded)
            guard self.currentTrack?.id == track.id else { return }
            if let alt {
                self.currentTrack?.youtubeId = alt
                self.loadVideo(id: alt)
            } else {
                self.isPlaying = false
                self.errorMessage = "This song's videos can't be played inside the app. Use Change Video Link to pick one."
            }
        }
    }
    
    // MARK: - Video feedback (👍 / 👎)
    
    /// The playing video is the one saved for this song (👍 given, or added by link)
    public var isCurrentVideoConfirmed: Bool {
        guard let track = currentTrack, let vid = track.youtubeId,
              let saved = PlaylistStore.shared.savedTrack(id: track.id) else { return false }
        return saved.youtubeId == vid
    }
    
    /// 👍 Right video: always play it for this song
    public func confirmCurrentVideo() {
        guard let track = currentTrack, let vid = track.youtubeId else { return }
        PlaylistStore.shared.setVideo(trackId: track.id, videoId: vid)
        objectWillChange.send()
    }
    
    /// 👎 Wrong video: never pick it again for this song, switch to the next-best now
    public func rejectCurrentVideo() {
        guard let track = currentTrack, let vid = track.youtubeId else { return }
        PlaylistStore.shared.rejectVideo(trackId: track.id, videoId: vid)
        var excluded = Set(PlaylistStore.shared.savedTrack(id: track.id)?.rejectedVideoIds ?? [vid])
        excluded.insert(vid)
        excluded.formUnion(failedVideoIds[track.id] ?? [])
        let language = searchLanguage(for: track)
        let resumeAt = currentTime
        Task {
            let alt = await YouTubeService.shared.resolveVideo(for: track, language: language, excluding: excluded)
            guard self.currentTrack?.id == track.id else { return }
            if let alt {
                self.currentTrack?.youtubeId = alt
                self.currentTrack?.rejectedVideoIds = Array(excluded)
                self.currentTime = resumeAt > 10 ? resumeAt : (track.startTime ?? 0)
                self.isPlaying = true
                self.loadVideo(id: alt, startAt: self.currentTime)
            } else {
                self.errorMessage = "No other official video found. Use Change Video Link to paste the right one."
            }
        }
    }
    
    // MARK: - Language (same rules as the Mac app)
    
    /// "Telugu Music" → "telugu"; "" for non-Indian language playlists (play the original); nil if the name says nothing
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
    
    /// Which language version to play: the playlist it's played from ("Hindi Music" → Hindi), else the
    /// playlists it belongs to (if they agree), else the Preferred Song Language setting (Indian songs).
    public func searchLanguage(for track: MediaTrack) -> String? {
        let playlists = PlaylistStore.shared.playlists
        if let pid = contextPlaylistId,
           let pl = playlists.first(where: { $0.id == pid }),
           pl.tracks.contains(where: { $0.id == track.id }),
           let lang = Self.playlistLanguage(pl.name) {
            return lang.isEmpty ? nil : lang
        }
        let containing = playlists.filter { pl in pl.tracks.contains { $0.id == track.id } }
        let langs = Set(containing.compactMap { Self.playlistLanguage($0.name) })
        if langs.count == 1, let lang = langs.first { return lang.isEmpty ? nil : lang }
        return track.searchLanguage
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
    
    public func playTrack(_ track: MediaTrack, inQueue tracks: [MediaTrack] = [], context: PlayContext = .unchanged) {
        switch context {
        case .unchanged: break
        case .playlist(let id): contextPlaylistId = id
        case .none: contextPlaylistId = nil
        }
        errorMessage = nil
        // Silence the old song now: while the next one's video is looked up it would keep playing
        // and keep moving the position, and the new song would start from there
        webView.evaluateJavaScript("stopForSwitch();", completionHandler: nil)
        let startAt = track.startTime ?? 0
        self.currentTrack = track
        self.currentTime = startAt
        self.duration = track.duration
        self.isPlaying = true
        self.trimEndHandled = false
        self.playCounted = false
        
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
        
        // Auto-resolve high-res artwork
        self.activeArtworkURL = track.thumbnailURL
        Task {
            if let cover = await TrackArtworkService.shared.cover(for: track), self.currentTrack?.id == track.id {
                self.activeArtworkURL = cover.absoluteString
                self.updateNowPlayingInfo()
            }
        }
        
        // Load lyrics
        loadLyrics(for: track)
        rememberPlayback()
        
        // Load and play video: the saved one, or the best official video (same ranking as the Mac app,
        // in the playlist's language, skipping videos marked 👎)
        if let vid = track.youtubeId, !vid.isEmpty {
            loadVideo(id: vid, startAt: startAt)
        } else {
            let language = searchLanguage(for: track)
            let excluded = Set(track.rejectedVideoIds ?? [])
            Task {
                let vid = await YouTubeService.shared.resolveVideo(for: track, language: language, excluding: excluded)
                guard self.currentTrack?.id == track.id else { return }
                if let vid {
                    self.currentTrack?.youtubeId = vid
                    self.loadVideo(id: vid, startAt: startAt)
                } else {
                    self.isPlaying = false
                    self.errorMessage = "Couldn't find \"\(track.title)\" on YouTube."
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
        if appInBackground { BackgroundAudioKeepAlive.shared.start() }
        if currentLoadedVideoId == nil, let track = currentTrack {
            if let vid = track.youtubeId, !vid.isEmpty {
                loadVideo(id: vid, autoPlay: true)
            } else {
                // e.g. the song shown at launch: find its video, then play
                playTrack(track, inQueue: queue)
                return
            }
        } else {
            webView.evaluateJavaScript("playVideo();", completionHandler: nil)
        }
        updateNowPlayingInfo()
    }
    
    public func pause() {
        pauseEpoch += 1
        wasPlayingBeforeInterruption = false
        AppLog.log("pause() called bg=\(appInBackground) from: \(Thread.callStackSymbols.dropFirst().prefix(3).joined(separator: " | "))")
        isPlaying = false
        rememberPlayback()
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
        let start = currentTrack?.startTime ?? 0
        if currentTime > start + 3.0 {
            seek(to: start)
            return
        }
        guard !queue.isEmpty else { return }
        if currentIndex > 0 {
            currentIndex -= 1
            playTrack(queue[currentIndex], inQueue: queue)
        } else {
            seek(to: currentTrack?.startTime ?? 0)
        }
    }
    
    /// Song finished (or reached its end time): Repeat One restarts it, otherwise next.
    /// While lyrics are being synced the song must not move on (the lyrics would end up on the next song)
    public var holdForLyricsEditor = false
    
    private func handleTrackEnded() {
        if holdForLyricsEditor { pause(); return }
        if repeatMode == 2, let track = currentTrack {
            trimEndHandled = false
            seek(to: track.startTime ?? 0)
            resume()
            return
        }
        isPlaying = false
        BackgroundAudioKeepAlive.shared.stop()
        playNext()
    }
    
    public func toggleShuffle() {
        isShuffled.toggle()
        defer { rememberPlayback() }
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
    
    /// Lyrics were edited: show the new ones now
    public func reloadLyrics() {
        guard let track = currentTrack else { return }
        loadLyrics(for: track)
        updateCurrentLyricIndex()
    }
    
    private func loadLyrics(for track: MediaTrack) {
        self.lyrics = nil
        self.currentLyricIndex = 0
        // Lyrics you wrote come first
        if let custom = CustomLyricsStore.shared.lyrics(for: track) {
            self.lyrics = custom
            self.isLyricsLoading = false
            updateCurrentLyricIndex()
            return
        }
        self.isLyricsLoading = true
        
        Task {
            let fetched = await LyricsService.shared.fetchLyrics(
                artist: track.artist,
                title: track.title,
                duration: track.duration
            )
            // Gone to another song, or you saved your own lyrics meanwhile: this result isn't wanted
            guard self.currentTrack?.id == track.id, !CustomLyricsStore.shared.hasLyrics(for: track) else { return }
            self.lyrics = fetched
            self.isLyricsLoading = false
        }
    }
    
    private func updateCurrentLyricIndex() {
        guard let lines = lyrics?.syncedLines, !lines.isEmpty else { return }
        
        // 0.32s vocal anticipation lead time: synchronizes visual highlighting
        // right as the artist starts vocalizing, eliminating perceived latency.
        let leadTime: Double = 0.32
        let effectiveTime = currentTime + leadTime
        
        // If the track is still playing an intro before the first line
        if effectiveTime < (lines.first?.time ?? 0) {
            if currentLyricIndex != -1 {
                currentLyricIndex = -1
            }
            return
        }
        
        var bestIndex = 0
        for (i, line) in lines.enumerated() {
            if effectiveTime >= line.time {
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
