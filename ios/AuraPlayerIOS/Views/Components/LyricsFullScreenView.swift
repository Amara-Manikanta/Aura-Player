import SwiftUI

/// Full-screen immersive lyrics display that seamlessly adapts to both vertical (portrait)
/// and horizontal (landscape) orientations, with auto-hiding playback controls, synchronized
/// auto-scrolling, and the exact same signature Aura liquid-glass background as the normal player.
public struct LyricsFullScreenView: View {
    @ObservedObject var playback: PlaybackManager
    @ObservedObject var playlistStore: PlaylistStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var landscape: Bool = false
    @State private var showControls: Bool = true
    @State private var hideToken: Int = 0
    @State private var isDraggingSlider: Bool = false
    @State private var sliderValue: Double = 0
    @State private var showLyricsEditor: Bool = false
    
    public init(playback: PlaybackManager, playlistStore: PlaylistStore) {
        self.playback = playback
        self.playlistStore = playlistStore
    }
    
    public var body: some View {
        guard let track = playback.currentTrack else {
            return AnyView(
                ZStack {
                    AuraBackground()
                    Text("No track playing")
                        .foregroundColor(.white)
                }
            )
        }
        
        return AnyView(
            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height
                
                ZStack {
                    // 1. Same signature Aura violet liquid-glass backdrop as the normal player
                    AuraBackground()
                    
                    // 2. Main Lyrics Display (fills entire screen and scrolls freely)
                    if isLandscape {
                        landscapeBody(geo: geo, track: track)
                    } else {
                        portraitBody(geo: geo, track: track)
                    }
                    
                    // 3. Floating Overlay Header (anchored to top only, doesn't block lyrics touch)
                    if showControls {
                        overlayHeader(isLandscape: isLandscape, track: track)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // 4. Floating Overlay Bottom Bar (anchored to bottom only, doesn't block lyrics touch)
                    if showControls && !isLandscape {
                        overlayBottomControls(track: track)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .statusBarHidden(!showControls)
                .persistentSystemOverlays(showControls ? .visible : .hidden)
                .task(id: hideToken) {
                    try? await Task.sleep(for: .seconds(3.5))
                    guard !Task.isCancelled, playback.isPlaying, !isDraggingSlider else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showControls = false
                    }
                }
                .onChange(of: playback.isPlaying) { _, playing in
                    if !playing {
                        withAnimation { showControls = true }
                    }
                    poke()
                }
                .sheet(isPresented: $showLyricsEditor) {
                    LyricsEditorSheet(track: track, playback: playback)
                }
                .onAppear {
                    OrientationLock.set(.allButUpsideDown)
                }
                .onDisappear {
                    OrientationLock.set(.allButUpsideDown)
                }
            }
            .ignoresSafeArea()
        )
    }
    
    // MARK: - Auto-Hide Activity Reset
    private func poke() {
        hideToken += 1
    }
    
    private func toggleOrientation(currentIsLandscape: Bool) {
        let target = !currentIsLandscape
        landscape = target
        OrientationLock.set(.allButUpsideDown, rotateTo: target ? .landscapeRight : .portrait)
        poke()
    }
    
    // MARK: - Portrait Layout
    private func portraitBody(geo: GeometryProxy, track: MediaTrack) -> some View {
        LyricsView(playback: playback, compact: false, isFullScreen: true)
            .padding(.top, showControls ? 64 : 24)
            .padding(.bottom, showControls ? 135 : 24)
            .animation(.easeInOut(duration: 0.25), value: showControls)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Landscape Layout
    private func landscapeBody(geo: GeometryProxy, track: MediaTrack) -> some View {
        HStack(spacing: 0) {
            // Left Column: Album Art + Song Details + Playback Controls
            if showControls {
                VStack(spacing: 12) {
                    Spacer(minLength: 32)
                    
                    // Artwork Card
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(AuraTheme.surfaceElevated)
                            .shadow(color: AuraTheme.primary.opacity(playback.isPlaying ? 0.35 : 0.1), radius: 18, x: 0, y: 8)
                        
                        if let artStr = playback.activeArtworkURL ?? track.effectiveThumbnailURL,
                           let url = URL(string: artStr) {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image {
                                    img.resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: min(geo.size.height * 0.34, 140), height: min(geo.size.height * 0.34, 140))
                                        .clipShape(RoundedRectangle(cornerRadius: 18))
                                } else {
                                    Image(systemName: "music.note")
                                        .font(.system(size: 34))
                                        .foregroundColor(AuraTheme.textTertiary)
                                }
                            }
                        }
                    }
                    .frame(width: min(geo.size.height * 0.34, 140), height: min(geo.size.height * 0.34, 140))
                    
                    // Track Title & Artist
                    VStack(spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(track.artist)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AuraTheme.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 220)
                    
                    // Compact Scrubber
                    compactScrubber
                        .frame(maxWidth: 220)
                    
                    // Compact Media Controls
                    compactControls(track: track)
                        .frame(maxWidth: 240)
                    
                    Spacer(minLength: 16)
                }
                .frame(width: min(geo.size.width * 0.34, 260))
                .padding(.leading, 20)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
            
            // Right Column: Lyrics View
            LyricsView(playback: playback, compact: false, isFullScreen: true)
                .padding(.top, showControls ? 36 : 16)
                .padding(.bottom, showControls ? 16 : 16)
                .padding(.trailing, 20)
                .padding(.leading, showControls ? 8 : 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - Overlay Header
    private func overlayHeader(isLandscape: Bool, track: MediaTrack) -> some View {
        HStack(spacing: 12) {
            // Exit Full Screen
            Button {
                Haptics.light()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }
            
            if !isLandscape {
                // Song info in portrait header
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AuraTheme.textSecondary)
                        .lineLimit(1)
                }
                .padding(.leading, 4)
            }
            
            Spacer()
            
            // Toggle Controls Visibility Button
            Button {
                Haptics.light()
                withAnimation(.easeInOut(duration: 0.25)) {
                    showControls.toggle()
                }
            } label: {
                Image(systemName: showControls ? "eye.slash" : "eye")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }
            
            // Manual Orientation Toggle Button (Vertical <-> Horizontal)
            Button {
                Haptics.light()
                toggleOrientation(currentIsLandscape: isLandscape)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isLandscape ? "iphone.portrait" : "iphone.landscape")
                        .font(.system(size: 14, weight: .semibold))
                    Text(isLandscape ? "Portrait" : "Rotate")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            }
            
            // Edit Lyrics Button
            Button {
                Haptics.light()
                showLyricsEditor = true
                poke()
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, isLandscape ? 12 : 50)
    }
    
    // MARK: - Overlay Bottom Controls (Portrait)
    private func overlayBottomControls(track: MediaTrack) -> some View {
        VStack(spacing: 10) {
            // Scrubber Bar
            ClockObserver(playback.clock) { time in
                VStack(spacing: 4) {
                    Slider(
                        value: Binding(
                            get: { currentProgress(at: time) },
                            set: { val in
                                isDraggingSlider = true
                                sliderValue = val
                                poke()
                            }
                        ),
                        in: 0...1,
                        onEditingChanged: { editing in
                            if !editing {
                                let targetSec = sliderValue * playback.duration
                                playback.seek(to: targetSec)
                                isDraggingSlider = false
                                poke()
                            }
                        }
                    )
                    .tint(AuraTheme.primary)
                    
                    HStack {
                        Text(timeString(isDraggingSlider ? sliderValue * playback.duration : time))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(AuraTheme.textTertiary)
                        Spacer()
                        Text("-" + timeString(max(0, playback.duration - (isDraggingSlider ? sliderValue * playback.duration : time))))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(AuraTheme.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 8)
            
            // Media Buttons
            HStack(spacing: 24) {
                // Shuffle
                Button {
                    Haptics.light()
                    playback.toggleShuffle()
                    poke()
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(playback.isShuffled ? AuraTheme.primary : AuraTheme.textTertiary)
                        .frame(width: 36, height: 36)
                }
                
                // Previous
                Button {
                    Haptics.light()
                    playback.playPrevious()
                    poke()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                }
                
                // Play / Pause Circle
                Button {
                    Haptics.medium()
                    playback.togglePlayPause()
                    poke()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.92))
                            .frame(width: 54, height: 54)
                            .shadow(color: AuraTheme.primary.opacity(0.4), radius: 12, y: 4)
                        
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(Color(hex: 0x7B6BE0))
                            .offset(x: playback.isPlaying ? 0 : 2)
                    }
                }
                
                // Next
                Button {
                    Haptics.light()
                    playback.playNext()
                    poke()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                }
                
                // Favorite Heart
                Button {
                    Haptics.light()
                    playlistStore.toggleFavorite(track: track)
                    poke()
                } label: {
                    Image(systemName: playlistStore.isTrackFavorite(track) ? "heart.fill" : "heart")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(playlistStore.isTrackFavorite(track) ? AuraTheme.primary : AuraTheme.textTertiary)
                        .frame(width: 36, height: 36)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.35), radius: 20, y: 10)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
    }
    
    // MARK: - Compact Scrubber (Landscape)
    private var compactScrubber: some View {
        ClockObserver(playback.clock) { time in
            VStack(spacing: 2) {
                Slider(
                    value: Binding(
                        get: { currentProgress(at: time) },
                        set: { val in
                            isDraggingSlider = true
                            sliderValue = val
                            poke()
                        }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        if !editing {
                            let targetSec = sliderValue * playback.duration
                            playback.seek(to: targetSec)
                            isDraggingSlider = false
                            poke()
                        }
                    }
                )
                .tint(AuraTheme.primary)
                
                HStack {
                    Text(timeString(isDraggingSlider ? sliderValue * playback.duration : time))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(AuraTheme.textTertiary)
                    Spacer()
                    Text("-" + timeString(max(0, playback.duration - (isDraggingSlider ? sliderValue * playback.duration : time))))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(AuraTheme.textTertiary)
                }
            }
        }
    }
    
    // MARK: - Compact Controls (Landscape)
    private func compactControls(track: MediaTrack) -> some View {
        HStack(spacing: 12) {
            Button {
                Haptics.light()
                playback.toggleShuffle()
                poke()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(playback.isShuffled ? AuraTheme.primary : AuraTheme.textTertiary)
            }
            
            Spacer()
            
            Button {
                Haptics.light()
                playback.playPrevious()
                poke()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            Button {
                Haptics.medium()
                playback.togglePlayPause()
                poke()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 44, height: 44)
                        .shadow(color: AuraTheme.primary.opacity(0.3), radius: 8, y: 3)
                    
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(hex: 0x7B6BE0))
                        .offset(x: playback.isPlaying ? 0 : 1.5)
                }
            }
            
            Spacer()
            
            Button {
                Haptics.light()
                playback.playNext()
                poke()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            Button {
                Haptics.light()
                playlistStore.toggleFavorite(track: track)
                poke()
            } label: {
                Image(systemName: playlistStore.isTrackFavorite(track) ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(playlistStore.isTrackFavorite(track) ? AuraTheme.primary : AuraTheme.textTertiary)
            }
        }
        .padding(.horizontal, 10)
    }
    
    // MARK: - Utilities
    private func currentProgress(at time: TimeInterval) -> Double {
        guard !isDraggingSlider else { return sliderValue }
        guard playback.duration > 0 else { return 0 }
        return min(max(time / playback.duration, 0), 1)
    }
    
    private func timeString(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
