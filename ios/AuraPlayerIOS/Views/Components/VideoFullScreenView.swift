import SwiftUI

/// Video filling the whole iPhone screen: the screen turns to landscape while it's open
/// (the rest of the app stays portrait).
public struct VideoFullScreenView: View {
    @ObservedObject var playback: PlaybackManager
    @Environment(\.dismiss) private var dismiss
    @State private var landscape = true
    @State private var showControls = true
    /// Fill crops the video to cover the whole screen (no black bars); Fit shows all of it
    @AppStorage("fullScreenVideoFill") private var fill = false
    /// Bumped on every interaction so the controls hide 3 s after the last one
    @State private var hideToken = 0
    
    public init(playback: PlaybackManager) {
        self.playback = playback
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            GeometryReader { geo in
                YouTubeWebPlayerView(playback: playback, hostID: "fullscreen")
                    .aspectRatio(16 / 9, contentMode: fill ? .fill : .fit)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()
            
            // Catches taps/pinches above the web page (which would otherwise swallow them)
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }; poke() }
                .gesture(MagnifyGesture().onEnded { value in
                    withAnimation(.easeInOut(duration: 0.25)) { fill = value.magnification > 1 }
                    poke()
                })
            
            if showControls {
                controls
                    .transition(.opacity)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task(id: hideToken) {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, playback.isPlaying else { return }
            withAnimation(.easeInOut(duration: 0.3)) { showControls = false }
        }
        .onChange(of: playback.isPlaying) { _, playing in
            if !playing { withAnimation { showControls = true } }
            poke()
        }
        // Turn the screen sideways while watching; everything else stays portrait
        .onAppear { OrientationLock.set(.allButUpsideDown, rotateTo: .landscapeRight) }
        .onDisappear { OrientationLock.set(.portrait, rotateTo: .portrait) }
    }
    
    /// Restart the auto-hide countdown
    private func poke() { hideToken += 1 }
    
    private func timeString(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
    
    private func toggleOrientation() {
        landscape.toggle()
        OrientationLock.set(.allButUpsideDown, rotateTo: landscape ? .landscapeRight : .portrait)
    }
    
    private var controls: some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { fill.toggle() }
                    poke()
                } label: {
                    Image(systemName: fill ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                Button {
                    toggleOrientation()
                    poke()
                } label: {
                    Image(systemName: landscape ? "rectangle.portrait.rotate" : "rectangle.landscape.rotate")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, landscape ? 20 : 54)
            Spacer()
            HStack(spacing: 10) {
                Text(timeString(playback.currentTime))
                Slider(
                    value: Binding(get: { playback.currentTime }, set: { playback.seek(to: $0); poke() }),
                    in: 0...max(playback.duration, 1)
                )
                .tint(.white)
                Text(timeString(playback.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, landscape ? 60 : 24)
            HStack(spacing: 36) {
                Button { playback.playPrevious(); poke() } label: { Image(systemName: "backward.fill") }
                Button { playback.togglePlayPause(); poke() } label: {
                    Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                }
                Button { playback.playNext(); poke() } label: { Image(systemName: "forward.fill") }
            }
            .font(.system(size: 24))
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, landscape ? 16 : 44)
        }
    }
}
