import SwiftUI
import WebKit

public struct YouTubeWebPlayerView: UIViewRepresentable {
    @ObservedObject var playback: PlaybackManager
    
    public init(playback: PlaybackManager) {
        self.playback = playback
    }
    
    public func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.clipsToBounds = true
        
        let wv = playback.webView!
        wv.translatesAutoresizingMaskIntoConstraints = false
        if wv.superview != nil {
            wv.removeFromSuperview()
        }
        container.addSubview(wv)
        
        NSLayoutConstraint.activate([
            wv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            wv.topAnchor.constraint(equalTo: container.topAnchor),
            wv.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        return container
    }
    
    public func updateUIView(_ uiView: UIView, context: Context) {
        let wv = playback.webView!
        if wv.superview != uiView {
            wv.removeFromSuperview()
            wv.translatesAutoresizingMaskIntoConstraints = false
            uiView.addSubview(wv)
            NSLayoutConstraint.activate([
                wv.leadingAnchor.constraint(equalTo: uiView.leadingAnchor),
                wv.trailingAnchor.constraint(equalTo: uiView.trailingAnchor),
                wv.topAnchor.constraint(equalTo: uiView.topAnchor),
                wv.bottomAnchor.constraint(equalTo: uiView.bottomAnchor)
            ])
            if playback.isPlaying {
                wv.evaluateJavaScript("playVideo();", completionHandler: nil)
            }
        }
    }
}
