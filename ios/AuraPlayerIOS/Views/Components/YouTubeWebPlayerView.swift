import SwiftUI
import WebKit

/// Shows the app's single shared YouTube web player.
///
/// The player can only be in one place at a time, so every screen that shows it registers as a
/// "host" and only the most recently shown host holds it (full screen › player sheet › background).
/// When that screen goes away, the player moves back to the previous host automatically.
public struct YouTubeWebPlayerView: View {
    @ObservedObject var playback: PlaybackManager
    let hostID: String
    
    public init(playback: PlaybackManager, hostID: String = "inline") {
        self.playback = playback
        self.hostID = hostID
    }
    
    public var body: some View {
        WebPlayerContainer(playback: playback, isActiveHost: playback.activeVideoHost == hostID)
            .onAppear { playback.registerVideoHost(hostID) }
            .onDisappear { playback.unregisterVideoHost(hostID) }
    }
}

private struct WebPlayerContainer: UIViewRepresentable {
    @ObservedObject var playback: PlaybackManager
    let isActiveHost: Bool
    
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.clipsToBounds = true
        if isActiveHost { attach(to: container) }
        return container
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        guard isActiveHost, playback.webView.superview !== uiView else { return }
        attach(to: uiView)
        if playback.isPlaying {
            playback.webView.evaluateJavaScript("playVideo();", completionHandler: nil)
        }
    }
    
    private func attach(to container: UIView) {
        let wv = playback.webView!
        wv.removeFromSuperview()
        wv.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            wv.topAnchor.constraint(equalTo: container.topAnchor),
            wv.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}
