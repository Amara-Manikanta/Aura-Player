package com.antigravity.auraplayer.ui.components

import android.annotation.SuppressLint
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import com.antigravity.auraplayer.service.PlaybackManager
import com.antigravity.auraplayer.service.VideoCommand
import com.antigravity.auraplayer.ui.theme.BackgroundDark

/**
 * YouTube video player. While it is on screen it owns playback (the audio player pauses);
 * when it leaves the screen, playback continues in the audio player from the same position.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun VideoPlayerView(
    playbackManager: PlaybackManager,
    modifier: Modifier = Modifier
) {
    var webView by remember { mutableStateOf<WebView?>(null) }

    // Hand playback to the video while visible, back to audio when gone
    DisposableEffect(Unit) {
        onDispose { playbackManager.onVideoHidden() }
    }

    // Initial load once the WebView exists, then follow manager commands
    LaunchedEffect(webView) {
        val view = webView ?: return@LaunchedEffect
        playbackManager.onVideoShown()?.let { view.loadPlayer(it) }
        playbackManager.videoCommands.collect { cmd ->
            when (cmd) {
                is VideoCommand.Load -> view.loadPlayer(cmd)
                VideoCommand.Play -> view.evaluateJavascript("play()", null)
                VideoCommand.Pause -> view.evaluateJavascript("pause()", null)
                is VideoCommand.Seek -> view.evaluateJavascript("seek(${cmd.positionMs / 1000.0})", null)
            }
        }
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(BackgroundDark)
    ) {
        AndroidView(
            modifier = Modifier.fillMaxSize(),
            factory = { context ->
                WebView(context).apply {
                    layoutParams = ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.MATCH_PARENT
                    )
                    setBackgroundColor(Color.BLACK)
                    settings.apply {
                        javaScriptEnabled = true
                        domStorageEnabled = true
                        mediaPlaybackRequiresUserGesture = false
                        cacheMode = WebSettings.LOAD_DEFAULT
                    }
                    webViewClient = WebViewClient()
                    webChromeClient = WebChromeClient()
                    addJavascriptInterface(PlayerBridge(playbackManager), "AuraBridge")
                    webView = this
                }
            },
            onRelease = { view ->
                view.removeJavascriptInterface("AuraBridge")
                view.loadUrl("about:blank")
                view.destroy()
            }
        )
    }
}

/** Receives YouTube player events from JavaScript (called on a WebView thread). */
private class PlayerBridge(private val manager: PlaybackManager) {
    private val main = Handler(Looper.getMainLooper())

    @JavascriptInterface
    fun onState(state: Int) = main.post { manager.onVideoState(state) }.let { }

    @JavascriptInterface
    fun onTime(seconds: Double, duration: Double) = main.post { manager.onVideoTime(seconds, duration) }.let { }

    @JavascriptInterface
    fun onError(code: Int) = main.post { manager.onVideoError(code) }.let { }
}

private fun WebView.loadPlayer(cmd: VideoCommand.Load) {
    val startSec = (cmd.startMs / 1000).toInt()
    val autoplay = if (cmd.autoplay) 1 else 0
    val html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>
          html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: #000; overflow: hidden; }
          #player { position: fixed; top: 0; left: 0; right: 0; bottom: 0; width: 100% !important; height: 100% !important; border: none; }
        </style>
        <script src="https://www.youtube.com/iframe_api"></script>
        </head>
        <body>
        <div id="player"></div>
        <script>
          var player, timer;
          function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
              videoId: '${cmd.videoId}',
              playerVars: { autoplay: $autoplay, start: $startSec, playsinline: 1, rel: 0, modestbranding: 1, controls: 0, disablekb: 1, fs: 0,
                            iv_load_policy: 3, enablejsapi: 1, origin: 'https://com.auraplayer.app' },
              events: {
                onReady: function(e) { if ($autoplay) e.target.playVideo(); },
                onStateChange: function(e) {
                  AuraBridge.onState(e.data);
                  clearInterval(timer);
                  if (e.data === 1) timer = setInterval(function() {
                    AuraBridge.onTime(player.getCurrentTime(), player.getDuration());
                  }, 100);
                },
                onError: function(e) { AuraBridge.onError(e.data); }
              }
            });
          }
          function play() { if (player && player.playVideo) player.playVideo(); }
          function pause() { if (player && player.pauseVideo) player.pauseVideo(); }
          function seek(t) { if (player && player.seekTo) player.seekTo(t, true); }
        </script>
        </body>
        </html>
    """.trimIndent()
    loadDataWithBaseURL("https://com.auraplayer.app", html, "text/html", "UTF-8", null)
}
