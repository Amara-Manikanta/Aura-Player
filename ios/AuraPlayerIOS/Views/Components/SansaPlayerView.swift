import SwiftUI
import MediaPlayer

public struct SansaPlayerView: View {
    @ObservedObject var playback: PlaybackManager
    @ObservedObject var playlistStore: PlaylistStore
    public let onDismiss: () -> Void
    public let onOpenSettings: () -> Void
    
    @State private var wheelMode: SansaWheelMode = .seek
    @State private var volumeLevel: Float = 0.8
    @State private var wheelFeedbackText: String?
    @State private var feedbackTimer: Timer?
    @State private var isEqActive: Bool = true
    
    // Sheets
    @State private var showAddToPlaylist: Bool = false
    @State private var showChangeVideo: Bool = false
    @State private var showTrimTimes: Bool = false
    
    public init(
        playback: PlaybackManager,
        playlistStore: PlaylistStore,
        onDismiss: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.playback = playback
        self.playlistStore = playlistStore
        self.onDismiss = onDismiss
        self.onOpenSettings = onOpenSettings
    }
    
    private var currentProgress: Double {
        guard playback.duration > 0 else { return 0 }
        return (playback.currentTime / playback.duration).clamped(to: 0...1)
    }
    
    public var body: some View {
        guard let track = playback.currentTrack else { return AnyView(EmptyView()) }
        
        return AnyView(
            ZStack {
                // Background & Physical Brushed Titanium Chassis
                SansaTheme.chassisGradient.ignoresSafeArea()
                
                // Subtle Hardware Chamfer Borders
                RoundedRectangle(cornerRadius: 32)
                    .stroke(
                        LinearGradient(
                            colors: [SansaTheme.metallicEdge, Color.black.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .ignoresSafeArea()
                
                VStack(spacing: 8) {
                    // Top Hardware Bar (Dismiss, SanDisk Branding, Menu/Settings)
                    HStack {
                        Button {
                            Haptics.light()
                            onDismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(SansaTheme.lcdTextSecondary)
                                .frame(width: 38, height: 38)
                                .background(SansaTheme.buttonSurface)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(SansaTheme.buttonBorder, lineWidth: 1))
                        }
                        
                        Spacer()
                        
                        // SanDisk Sansa Engraved Branding
                        VStack(spacing: 1) {
                            Text("SanDisk")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .tracking(2)
                            
                            HStack(spacing: 4) {
                                Text("sansa")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(SansaTheme.neonBlue)
                                Text("e260")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundColor(SansaTheme.lcdTextSecondary)
                            }
                        }
                        
                        Spacer()
                        
                        Menu {
                            Button {
                                onOpenSettings()
                            } label: {
                                Label("Player Settings & Themes", systemImage: "gearshape.fill")
                            }
                            
                            Divider()
                            
                            Button {
                                showAddToPlaylist = true
                            } label: {
                                Label("Add to Playlist", systemImage: "text.badge.plus")
                            }
                            
                            Button {
                                showChangeVideo = true
                            } label: {
                                Label("Change Video Link", systemImage: "link")
                            }
                            
                            Button {
                                showTrimTimes = true
                            } label: {
                                Label("Trim Audio", systemImage: "scissors")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(SansaTheme.lcdTextSecondary)
                                .frame(width: 38, height: 38)
                                .background(SansaTheme.buttonSurface)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(SansaTheme.buttonBorder, lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    
                    // ==========================================
                    // 1. THE RETRO TFT LCD COLOR SCREEN
                    // ==========================================
                    ZStack {
                        // Glossy Black Screen Bezel
                        RoundedRectangle(cornerRadius: 18)
                            .fill(SansaTheme.screenBezel)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(SansaTheme.metallicEdge.opacity(0.35), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.6), radius: 10, x: 0, y: 5)
                        
                        // Backlit LCD Inner Display
                        RoundedRectangle(cornerRadius: 14)
                            .fill(SansaTheme.lcdBacklight)
                            .padding(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color(hex: 0x1E3B5C).opacity(0.5), lineWidth: 1)
                                    .padding(8)
                            )
                        
                        // Screen Reflection
                        RoundedRectangle(cornerRadius: 14)
                            .fill(SansaTheme.lcdGlassReflection)
                            .padding(8)
                            .allowsHitTesting(false)
                        
                        // LCD Display Content
                        VStack(spacing: 6) {
                            // Status Bar
                            HStack {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(playback.isPlaying ? Color.green : Color.orange)
                                        .frame(width: 6, height: 6)
                                    Text(playback.isPlaying ? "PLAY" : "PAUSE")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(SansaTheme.lcdTextCyan)
                                }
                                
                                Spacer()
                                
                                // Wheel Mode Indicator
                                Text(wheelFeedbackText ?? (wheelMode == .seek ? "ROTATOR: SEEK" : "ROTATOR: VOL"))
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(wheelFeedbackText != nil ? SansaTheme.neonBlue : SansaTheme.lcdTextSecondary)
                                    .animation(.easeInOut(duration: 0.2), value: wheelFeedbackText)
                                
                                Spacer()
                                
                                // Battery Blocks
                                HStack(spacing: 1.5) {
                                    ForEach(0..<4) { _ in
                                        Rectangle()
                                            .fill(SansaTheme.lcdTextCyan)
                                            .frame(width: 4, height: 8)
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                            
                            // Center Screen Media Area
                            ZStack {
                                // Keep WebView mounted for audio & video
                                YouTubeWebPlayerView(playback: playback)
                                    .aspectRatio(16/9, contentMode: .fit)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: playback.displayMode == .video ? 188 : 1)
                                    .cornerRadius(8)
                                    .padding(.horizontal, 4)
                                    .opacity(playback.displayMode == .video ? 1.0 : 0.001)
                                    .allowsHitTesting(playback.displayMode == .video)
                                
                                if playback.displayMode == .audio {
                                    HStack(spacing: 12) {
                                        // Square Album Art
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color(hex: 0x101724))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(SansaTheme.neonBlue.opacity(0.3), lineWidth: 1)
                                                )
                                            
                                            if let artStr = playback.activeArtworkURL ?? track.effectiveThumbnailURL,
                                               let url = URL(string: artStr) {
                                                AsyncImage(url: url) { phase in
                                                    if let img = phase.image {
                                                        img.resizable()
                                                            .aspectRatio(contentMode: .fill)
                                                            .frame(width: 104, height: 104)
                                                            .clipped()
                                                            .cornerRadius(8)
                                                    } else {
                                                        Image(systemName: "music.note")
                                                            .font(.system(size: 32))
                                                            .foregroundColor(SansaTheme.lcdTextSecondary)
                                                    }
                                                }
                                            } else {
                                                Image(systemName: "music.note")
                                                    .font(.system(size: 32))
                                                    .foregroundColor(SansaTheme.lcdTextSecondary)
                                            }
                                        }
                                        .frame(width: 104, height: 104)
                                        .shadow(color: Color.black.opacity(0.5), radius: 6)
                                        
                                        // Retro Graphic Equalizer Bars
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("EQUALIZER")
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .foregroundColor(SansaTheme.lcdTextSecondary)
                                            
                                            HStack(alignment: .bottom, spacing: 4) {
                                                ForEach(0..<7) { idx in
                                                    RetroEqBar(isActive: playback.isPlaying, index: idx)
                                                }
                                            }
                                            .frame(height: 60)
                                            
                                            Text(track.genre ?? "POP / ROCK")
                                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                                .foregroundColor(SansaTheme.lcdTextCyan)
                                                .lineLimit(1)
                                        }
                                        .padding(.leading, 4)
                                    }
                                    .padding(.horizontal, 14)
                                } else if playback.displayMode == .lyrics {
                                    LyricsView(playback: playback)
                                        .frame(maxHeight: 140)
                                        .padding(.horizontal, 8)
                                }
                            }
                            .frame(height: playback.displayMode == .video ? 190 : 124)
                            
                            // Track Info
                            if playback.displayMode == .video {
                                HStack {
                                    Text(track.title)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(SansaTheme.lcdTextPrimary)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    Text(track.artist)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(SansaTheme.lcdTextCyan)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 14)
                                .padding(.top, 2)
                            } else {
                                VStack(spacing: 2) {
                                    Text(track.title)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(SansaTheme.lcdTextPrimary)
                                        .lineLimit(1)
                                    
                                    Text(track.artist)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(SansaTheme.lcdTextCyan)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 14)
                                .padding(.top, 2)
                            }
                            
                            // Retro LCD Scrubber Bar
                            VStack(spacing: 3) {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(SansaTheme.lcdProgressTrack)
                                            .frame(height: 5)
                                        
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color(hex: 0x66E5FF), SansaTheme.neonBlue],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(width: max(0, geo.size.width * currentProgress), height: 5)
                                            .shadow(color: SansaTheme.neonBlue.opacity(0.8), radius: 4)
                                    }
                                }
                                .frame(height: 5)
                                
                                HStack {
                                    Text(formatTime(playback.currentTime))
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(SansaTheme.lcdTextCyan)
                                    Spacer()
                                    Text(formatTime(playback.duration))
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(SansaTheme.lcdTextSecondary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)
                        }
                    }
                    .frame(height: playback.displayMode == .video ? 310 : 258)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: playback.displayMode)
                    .padding(.horizontal, 16)
                    
                    Spacer(minLength: 4)
                    
                    // ==========================================
                    // 2. HARDWARE CONTROLS AROUND THE ROTATOR WHEEL
                    // ==========================================
                    VStack(spacing: 8) {
                        // Top Row Around Rotator
                        HStack {
                            // Top-Left: VOL / SCRUB Wheel Mode
                            SansaHardwareButton(
                                icon: wheelMode == .seek ? "speaker.wave.2.fill" : "forward.fill",
                                label: wheelMode == .seek ? "VOL" : "SCRUB",
                                isActive: wheelMode == .volume,
                                width: 48
                            ) {
                                Haptics.light()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    wheelMode = (wheelMode == .seek) ? .volume : .seek
                                    showFeedback(text: wheelMode == .seek ? "MODE: SCRUB TIME" : "MODE: VOLUME CONTROL")
                                }
                            }
                            
                            Spacer()
                            
                            // Top-Center: Authentic Sansa MENU / MODE Button
                            SansaHardwareButton(
                                icon: playback.displayMode == .video ? "video.fill" : (playback.displayMode == .lyrics ? "quote.bubble.fill" : "text.justify"),
                                label: "MENU",
                                isActive: playback.displayMode != .audio,
                                width: 62
                            ) {
                                Haptics.light()
                                cycleDisplayMode()
                            }
                            
                            Spacer()
                            
                            // Top-Right: Favorite Heart
                            SansaHardwareButton(
                                icon: playlistStore.isTrackFavorite(track) ? "heart.fill" : "heart",
                                label: "FAV",
                                isActive: playlistStore.isTrackFavorite(track),
                                iconColor: playlistStore.isTrackFavorite(track) ? SansaTheme.neonBlue : .white,
                                width: 48
                            ) {
                                Haptics.light()
                                playlistStore.toggleFavorite(track: track)
                                showFeedback(text: playlistStore.isTrackFavorite(track) ? "FAVORITE: ADDED ♥" : "FAVORITE: REMOVED")
                            }
                        }
                        .padding(.horizontal, 32)
                        
                        // Middle Row: Left Button, Central Rotator Wheel, Right Button
                        HStack(spacing: 12) {
                            // Left: PREV |<<
                            SansaHardwareButton(
                                icon: "backward.fill",
                                label: "PREV",
                                width: 48,
                                height: 48
                            ) {
                                Haptics.light()
                                playback.playPrevious()
                                showFeedback(text: "TRACK: PREV")
                            }
                            
                            // The Iconic Virtual Rotator Wheel with Neon Ring
                            SansaRotatorWheel(
                                diameter: 172,
                                isCenterActive: playback.isPlaying,
                                onRotate: { step in
                                    handleWheelRotation(steps: step)
                                },
                                onCenterTap: {
                                    playback.togglePlayPause()
                                    showFeedback(text: playback.isPlaying ? "STATE: PAUSED" : "STATE: PLAYING")
                                }
                            )
                            
                            // Right: NEXT >>|
                            SansaHardwareButton(
                                icon: "forward.fill",
                                label: "NEXT",
                                width: 48,
                                height: 48
                            ) {
                                Haptics.light()
                                playback.playNext()
                                showFeedback(text: "TRACK: NEXT")
                            }
                        }
                        
                        // Bottom Row Around Rotator
                        HStack {
                            // Bottom-Left: SHUFFLE
                            SansaHardwareButton(
                                icon: "shuffle",
                                label: "SHUFFLE",
                                isActive: playback.isShuffled,
                                width: 48
                            ) {
                                Haptics.light()
                                playback.toggleShuffle()
                                showFeedback(text: playback.isShuffled ? "SHUFFLE: ON" : "SHUFFLE: OFF")
                            }
                            
                            Spacer()
                            
                            // Bottom-Center: PLAY / PAUSE (Prominent Accent Button)
                            SansaHardwareButton(
                                icon: playback.isPlaying ? "pause.fill" : "play.fill",
                                label: playback.isPlaying ? "PAUSE" : "PLAY",
                                isAccent: true,
                                width: 62
                            ) {
                                Haptics.medium()
                                playback.togglePlayPause()
                                showFeedback(text: playback.isPlaying ? "STATE: PAUSED" : "STATE: PLAYING")
                            }
                            
                            Spacer()
                            
                            // Bottom-Right: REPEAT
                            SansaHardwareButton(
                                icon: playback.repeatMode == 2 ? "repeat.1" : "repeat",
                                label: playback.repeatMode == 2 ? "REP 1" : (playback.repeatMode == 1 ? "REP ALL" : "REPEAT"),
                                isActive: playback.repeatMode > 0,
                                width: 48
                            ) {
                                Haptics.light()
                                playback.repeatMode = (playback.repeatMode + 1) % 3
                                let msg = playback.repeatMode == 2 ? "REPEAT: 1 TRACK" : (playback.repeatMode == 1 ? "REPEAT: ALL" : "REPEAT: OFF")
                                showFeedback(text: msg)
                            }
                        }
                        .padding(.horizontal, 32)
                    }
                    .padding(.bottom, 20)
                }
            }
            .sheet(isPresented: $showAddToPlaylist) {
                AddToPlaylistSheet(track: track, playlistStore: playlistStore)
            }
            .sheet(isPresented: $showChangeVideo) {
                ChangeVideoLinkSheet(track: track, store: playlistStore, playback: playback)
            }
            .sheet(isPresented: $showTrimTimes) {
                TrimTimesSheet(track: track, store: playlistStore, playback: playback)
            }
        )
    }
    
    // MARK: - Wheel Interaction
    
    private func handleWheelRotation(steps: Int) {
        switch wheelMode {
        case .seek:
            // Scrub by 4 seconds per tick
            let delta = Double(steps) * 4.0
            let targetTime = (playback.currentTime + delta).clamped(to: 0...max(playback.duration, 1))
            playback.seek(to: targetTime)
            showFeedback(text: "SEEK: \(formatTime(targetTime))")
            
        case .volume:
            // Adjust volume step
            let stepVal = Float(steps) * 0.05
            volumeLevel = max(0.0, min(1.0, volumeLevel + stepVal))
            showFeedback(text: "VOL: \(Int(volumeLevel * 100))%")
        }
    }
    
    private func cycleDisplayMode() {
        switch playback.displayMode {
        case .audio:
            playback.displayMode = .video
            showFeedback(text: "MODE: VIDEO (HD)")
        case .video:
            playback.displayMode = .lyrics
            showFeedback(text: "MODE: LYRICS")
        case .lyrics:
            playback.displayMode = .audio
            showFeedback(text: "MODE: AUDIO / ART")
        }
    }
    
    private func showFeedback(text: String) {
        wheelFeedbackText = text
        feedbackTimer?.invalidate()
        feedbackTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { _ in
            withAnimation {
                wheelFeedbackText = nil
            }
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds > 0 && !seconds.isNaN else { return "0:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Retro Hardware Button

private struct SansaHardwareButton: View {
    let icon: String
    let label: String
    var isAccent: Bool = false
    var isActive: Bool = false
    var iconColor: Color = .white
    var width: CGFloat = 48
    var height: CGFloat = 44
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(
                            LinearGradient(
                                colors: isAccent
                                    ? [Color(hex: 0x00A3FF), Color(hex: 0x0055D4)]
                                    : (isActive
                                        ? [Color(hex: 0x1E3A58), Color(hex: 0x102133)]
                                        : [Color(hex: 0x2A2E3D), Color(hex: 0x181A22)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: width, height: height)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(
                                    isAccent
                                        ? SansaTheme.neonBlue.opacity(0.85)
                                        : (isActive ? SansaTheme.neonBlue.opacity(0.65) : SansaTheme.buttonBorder),
                                    lineWidth: 1
                                )
                        )
                        .shadow(
                            color: isAccent
                                ? SansaTheme.neonBlue.opacity(0.55)
                                : (isActive ? SansaTheme.neonBlue.opacity(0.35) : Color.black.opacity(0.4)),
                            radius: isAccent ? 8 : (isActive ? 6 : 4),
                            x: 0,
                            y: 2
                        )
                    
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(isAccent ? .white : (isActive ? SansaTheme.neonBlue : iconColor))
                }
                
                Text(label)
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundColor(isActive ? SansaTheme.neonBlue : SansaTheme.lcdTextSecondary)
                    .tracking(0.5)
            }
        }
        .buttonStyle(HardwarePressStyle())
    }
}

private struct HardwarePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// MARK: - Retro Animated Equalizer Bar

private struct RetroEqBar: View {
    let isActive: Bool
    let index: Int
    @State private var heightMultiplier: CGFloat = 0.5
    
    var body: some View {
        VStack(spacing: 1.5) {
            ForEach(0..<8) { barIdx in
                Rectangle()
                    .fill(
                        barIdx < 2
                            ? Color.red
                            : (barIdx < 4 ? Color.yellow : SansaTheme.lcdTextCyan)
                    )
                    .frame(width: 6, height: 5)
                    .opacity(7 - barIdx < Int(heightMultiplier * 8) ? 1.0 : 0.15)
            }
        }
        .onAppear {
            if isActive { animate() }
        }
        .onChange(of: isActive) { _, active in
            if active { animate() }
        }
    }
    
    private func animate() {
        let delay = Double(index) * 0.08
        Timer.scheduledTimer(withTimeInterval: 0.15 + delay, repeats: true) { timer in
            guard isActive else {
                timer.invalidate()
                heightMultiplier = 0.2
                return
            }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                heightMultiplier = CGFloat.random(in: 0.2...0.95)
            }
        }
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
