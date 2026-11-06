import SwiftUI

/// Full-screen immersive lyrics display that seamlessly adapts to both vertical (portrait)
/// and horizontal (landscape) orientations, with auto-hiding playback controls, synchronized
/// auto-scrolling, devotional visual effects, and quick manual rotation toggle.
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
                    Color.black.ignoresSafeArea()
                    Text("No track playing")
                        .foregroundColor(.white)
                }
            )
        }
        
        return AnyView(
            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height
                
                ZStack {
                    // 1. Ambient Dynamic Backdrop
                    ambientBackdrop(track: track)
                    
                    // 2. Main Lyrics Display (fills entire screen)
                    if isLandscape {
                        landscapeBody(geo: geo, track: track)
                    } else {
                        portraitBody(geo: geo, track: track)
                    }
                    
                    // 3. Floating Overlay Controls (auto-hideable)
                    if showControls {
                        overlayHeader(isLandscape: isLandscape, track: track)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        
                        if !isLandscape {
                            overlayBottomControls(track: track)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                }
                .contentShape(Rectangle())
                // Tap on background toggles controls
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showControls.toggle()
                    }
                    poke()
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
                    // Unlock all orientations for free physical rotation
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
    
    // MARK: - Ambient Backdrop
    private func ambientBackdrop(track: MediaTrack) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Blurred Artwork Glow
            if let artStr = playback.activeArtworkURL ?? track.effectiveThumbnailURL,
               let url = URL(string: artStr) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 65)
                            .scaleEffect(1.25)
                            .opacity(0.38)
                    }
                }
                .ignoresSafeArea()
            }
            
            // Deep gradient overlay for high contrast text readability
            LinearGradient(
                colors: [
                    Color.black.opacity(0.72),
                    Color(hex: 0x120E24).opacity(0.85),
                    Color.black.opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
    
    // MARK: - Portrait Layout
    private func portraitBody(geo: GeometryProxy, track: MediaTrack) -> some View {
        VStack(spacing: 0) {
            // Space for top header overlay
            Spacer()
                .frame(height: showControls ? 80 : 44)
            
            // Center expansive lyrics
            LyricsView(playback: playback, compact: false, isFullScreen: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.08),
                            .init(color: .black, location: 0.88),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Space for bottom player overlay
            Spacer()
                .frame(height: showControls ? 140 : 36)
        }
    }
    
    // MARK: - Landscape Layout
    private func landscapeBody(geo: GeometryProxy, track: MediaTrack) -> some View {
        HStack(spacing: 0) {
            // Left Column: Album Art + Song Details + Playback Controls
            if showControls {
                VStack(spacing: 12) {
                    Spacer(minLength: 40)
                    
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
                                        .frame(width: min(geo.size.height * 0.34, 150), height: min(geo.size.height * 0.34, 150))
                                        .clipShape(RoundedRectangle(cornerRadius: 18))
                                } else {
                                    Image(systemName: "music.note")
                                        .font(.system(size: 36))
                                        .foregroundColor(AuraTheme.textTertiary)
                                }
                            }
                        }
                    }
                    .frame(width: min(geo.size.height * 0.34, 150), height: min(geo.size.height * 0.34, 150))
                    
                    // Track Title & Artist
                    VStack(spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(track.artist)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AuraTheme.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 240)
                    
                    // Compact Scrubber
                    compactScrubber
                        .frame(maxWidth: 240)
                    
                    // Compact Media Controls
                    compactControls(track: track)
                        .frame(maxWidth: 260)
                    
                    Spacer(minLength: 20)
                }
                .frame(width: min(geo.size.width * 0.36, 280))
                .padding(.leading, 24)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
            
            // Right Column: Full-width Karaoke Lyrics
            LyricsView(playback: playback, compact: false, isFullScreen: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, showControls ? 40 : 16)
                .padding(.bottom, showControls ? 20 : 16)
                .padding(.trailing, 24)
                .padding(.leading, showControls ? 8 : 36)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.07),
                            .init(color: .black, location: 0.93),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
    
    // MARK: - Overlay Header
    private func overlayHeader(isLandscape: Bool, track: MediaTrack) -> some View {
        VStack {
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
            
            Spacer()
        }
    }
    
    // MARK: - Overlay Bottom Controls (Portrait)
    private func overlayBottomControls(track: MediaTrack) -> some View {
        VStack {
            Spacer()
            
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
            .padding(.bottom, 24)
        }
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
