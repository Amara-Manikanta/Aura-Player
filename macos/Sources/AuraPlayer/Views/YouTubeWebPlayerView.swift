import SwiftUI
import WebKit

public struct YouTubeWebPlayerView: NSViewRepresentable {
    public let videoId: String
    @Bindable var playback: PlaybackManager
    
    public init(videoId: String, playback: PlaybackManager) {
        self.videoId = videoId
        self.playback = playback
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // WKWebView disables HTML element fullscreen on macOS by default, which makes
        // YouTube's fullscreen button (and the "f" key) do nothing.
        config.preferences.isElementFullscreenEnabled = true
        
        // Add JS message handlers for playerState, timeUpdate, and playerError
        config.userContentController.add(context.coordinator, name: "playerState")
        config.userContentController.add(context.coordinator, name: "timeUpdate")
        config.userContentController.add(context.coordinator, name: "playerError")
        config.userContentController.add(context.coordinator, name: "mediaKey")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        context.coordinator.webView = webView
        context.coordinator.currentVideoId = videoId
        context.coordinator.setupActions(for: playback)
        
        loadVideo(videoId, in: webView)
        return webView
    }
    
    public func updateNSView(_ nsView: WKWebView, context: Context) {
        // Handle Video ID Change
        if context.coordinator.currentVideoId != videoId {
            context.coordinator.currentVideoId = videoId
            loadVideo(videoId, in: nsView)
            return
        }
    }
    
    public static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.cleanup()
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "playerState")
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "timeUpdate")
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "playerError")
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "mediaKey")
        nsView.stopLoading()
        nsView.loadHTMLString("", baseURL: nil)
    }
    
    private func loadVideo(_ id: String, in webView: WKWebView) {
        let startSec = Int(playback.currentTime)
        playback.webVideoLoadStartedAt = Date()
        AppLog.log("webplayer", "loading video \(id) at \(startSec)s for \"\(playback.currentTrack?.title ?? "-")\"")
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>
          html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: #000; overflow: hidden; }
          /* Pin the player to the viewport so it follows window resizes and fullscreen.
             (vw/vh units are not recomputed reliably when WebKit enters fullscreen.) */
          #ytplayer { position: fixed; top: 0; left: 0; right: 0; bottom: 0;
                      width: 100% !important; height: 100% !important; border: none; background: #000; }
          #ytplayer:fullscreen, #ytplayer:-webkit-full-screen {
                      width: 100% !important; height: 100% !important; }
        </style>
        <script src="https://www.youtube.com/iframe_api"></script>
        </head>
        <body>
          <div id="ytplayer"></div>
          <script>
            var player;
            var isReady = false;
            var timeInterval = null;

            function onYouTubeIframeAPIReady() {
              player = new YT.Player('ytplayer', {
                videoId: '\(id)',
                playerVars: {
                  'autoplay': 1,
                  'controls': 1,
                  'rel': 0,
                  'modestbranding': 1,
                  'iv_load_policy': 3,
                  'playsinline': 1,
                  'enablejsapi': 1,
                  'origin': 'https://com.auraplayer.app',
                  'widget_referrer': 'https://com.auraplayer.app',
                  'start': \(startSec),
                  'fs': 1
                },
                events: {
                  'onReady': onPlayerReady,
                  'onStateChange': onPlayerStateChange,
                  'onError': onPlayerError
                }
              });
            }

            function fitPlayer() {
              if (player && player.setSize) {
                player.setSize(window.innerWidth, window.innerHeight);
              }
            }
            window.addEventListener('resize', fitPlayer);
            document.addEventListener('fullscreenchange', function() { setTimeout(fitPlayer, 50); });
            document.addEventListener('webkitfullscreenchange', function() { setTimeout(fitPlayer, 50); });

            // While the video plays, macOS may send media keys (F7–F9) to this web page instead of
            // the app; hand them back so they go through the app's queue (next/previous songs).
            if ('mediaSession' in navigator) {
              ['play', 'pause', 'nexttrack', 'previoustrack'].forEach(function(action) {
                try {
                  navigator.mediaSession.setActionHandler(action, function() {
                    window.webkit.messageHandlers.mediaKey.postMessage(action);
                  });
                } catch (e) {}
              });
            }

            function onPlayerReady(event) {
              isReady = true;
              fitPlayer();
              event.target.playVideo();
              startTimeTracker();
            }

            function onPlayerStateChange(event) {
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerState) {
                window.webkit.messageHandlers.playerState.postMessage(event.data);
              }
              if (event.data === 1) { // PLAYING
                startTimeTracker();
              } else {
                stopTimeTracker();
              }
            }

            function onPlayerError(event) {
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerError) {
                window.webkit.messageHandlers.playerError.postMessage(event.data);
              }
            }

            function startTimeTracker() {
              if (timeInterval) clearInterval(timeInterval);
              timeInterval = setInterval(function() {
                if (player && player.getCurrentTime && player.getDuration) {
                  var cur = player.getCurrentTime();
                  var dur = player.getDuration();
                  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.timeUpdate) {
                    window.webkit.messageHandlers.timeUpdate.postMessage({ currentTime: cur, duration: dur });
                  }
                }
              }, 250);
            }

            function stopTimeTracker() {
              if (timeInterval) {
                clearInterval(timeInterval);
                timeInterval = null;
              }
            }

            function play() {
              if (player && player.playVideo) player.playVideo();
            }
            function pause() {
              if (player && player.pauseVideo) player.pauseVideo();
            }
            function seek(t) {
              if (player && player.seekTo) player.seekTo(t, true);
            }
            function setVolume(v) {
              if (player && player.setVolume) player.setVolume(v);
            }
          </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://com.auraplayer.app"))
    }
    
    public class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: YouTubeWebPlayerView
        weak var webView: WKWebView?
        var currentVideoId: String = ""
        
        init(_ parent: YouTubeWebPlayerView) {
            self.parent = parent
        }
        
        func setupActions(for playback: PlaybackManager) {
            playback.webPlayerOwner = ObjectIdentifier(self)
            playback.onWebPlayerAction = { [weak self] action in
                guard let self = self, let webView = self.webView else { return }
                switch action {
                case .play:
                    webView.evaluateJavaScript("play();")
                case .pause:
                    webView.evaluateJavaScript("pause();")
                case .seek(let time):
                    webView.evaluateJavaScript("seek(\(time));")
                case .setVolume(let vol):
                    let volumePercent = Int(vol * 100)
                    webView.evaluateJavaScript("setVolume(\(volumePercent));")
                }
            }
        }
        
        func cleanup() {
            // Only disconnect the controls if they're still ours: when the video moves between the main
            // window and the mini player, the new player connects before the old one goes away
            guard parent.playback.webPlayerOwner == ObjectIdentifier(self) else { return }
            parent.playback.onWebPlayerAction = nil
            parent.playback.webPlayerOwner = nil
        }
        
        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "playerState", let state = message.body as? Int {
                Task { @MainActor in
                    self.parent.playback.updateFromWebPlayer(state: state)
                }
            } else if message.name == "timeUpdate", let dict = message.body as? [String: Any],
                      let cur = dict["currentTime"] as? Double,
                      let dur = dict["duration"] as? Double {
                Task { @MainActor in
                    self.parent.playback.updateFromWebPlayer(time: cur, dur: dur)
                }
            } else if message.name == "mediaKey", let action = message.body as? String {
                Task { @MainActor in
                    AppLog.log("keys", "media key via web player: \(action)")
                    let playback = self.parent.playback
                    switch action {
                    case "play": if !playback.isPlaying { playback.togglePlayPause() }
                    case "pause": if playback.isPlaying { playback.togglePlayPause() }
                    case "nexttrack": playback.next()
                    case "previoustrack": playback.previous()
                    default: break
                    }
                }
            } else if message.name == "playerError", let code = message.body as? Int {
                Task { @MainActor in
                    self.parent.playback.handleWebPlayerError(code: code)
                }
            }
        }
    }
}
