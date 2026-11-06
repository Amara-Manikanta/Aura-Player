import SwiftUI

public struct FullPlayerSheet: View {
    @ObservedObject var playback: PlaybackManager
    @ObservedObject var playlistStore: PlaylistStore
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("playerTheme") private var playerTheme: PlayerTheme = .modern
    @State private var showSettings: Bool = false
    
    @State private var isDraggingSlider: Bool = false
    @State private var sliderValue: Double = 0
    @State private var showAddToPlaylist: Bool = false
    @State private var showChangeVideo: Bool = false
    @State private var showTrimTimes: Bool = false
    @State private var showLyricsEditor: Bool = false
    @State private var showFullScreenVideo: Bool = false
    @State private var showFullScreenLyrics: Bool = false
    
    public init(playback: PlaybackManager, playlistStore: PlaylistStore) {
        self.playback = playback
        self.playlistStore = playlistStore
    }
    
    /// Synced or plain lyrics were found for the playing song
    private var hasLyrics: Bool {
        guard let lyrics = playback.lyrics else { return false }
        return lyrics.isSynced || !(lyrics.plainLyrics ?? "").isEmpty
    }
    
    private func currentProgress(at time: TimeInterval) -> Double {
        if isDraggingSlider { return sliderValue }
        guard playback.duration > 0 else { return 0 }
        return (time / playback.duration).clamped(to: 0...1)
    }
    
    private var artworkDimension: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        // Adapt gracefully between small and large iPhones
        if screenHeight < 700 {
            return min(screenWidth - 80, 220)
        } else if screenHeight < 800 {
            return min(screenWidth - 70, 260)
        } else {
            return min(screenWidth - 64, 300)
        }
    }
    
    public var body: some View {
        guard let track = playback.currentTrack else { return AnyView(EmptyView()) }
        
        return AnyView(
            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height
                
                ZStack {
                    if playerTheme == .sansa {
                        SansaPlayerView(
                            playback: playback,
                            playlistStore: playlistStore,
                            onDismiss: { dismiss() },
                            onOpenSettings: { showSettings = true }
                        )
                    } else {
                        // Violet glass backdrop
                        AuraBackground()
                        
                        if isLandscape {
                            landscapeContent(geo: geo, track: track)
                        } else {
                            portraitContent(track: track)
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showFullScreenVideo) {
                VideoFullScreenView(playback: playback)
            }
            .fullScreenCover(isPresented: $showFullScreenLyrics) {
                LyricsFullScreenView(playback: playback, playlistStore: playlistStore)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(playlistStore: playlistStore)
            }
            .sheet(isPresented: $showAddToPlaylist) {
                AddToPlaylistSheet(track: track, playlistStore: playlistStore)
            }
            .sheet(isPresented: $showChangeVideo) {
                ChangeVideoLinkSheet(track: track, store: playlistStore, playback: playback)
            }
            .sheet(isPresented: $showLyricsEditor) {
                if let current = playback.currentTrack { LyricsEditorSheet(track: current, playback: playback) }
            }
            .sheet(isPresented: $showTrimTimes) {
                TrimTimesSheet(track: track, store: playlistStore, playback: playback)
            }
        )
    }
    
    // MARK: - Portrait Layout
    private func portraitContent(track: MediaTrack) -> some View {
        VStack(spacing: 0) {
            topBar(track: track)
                .padding(.horizontal, 16)
                .padding(.top, 10)
            
            Spacer(minLength: 8)
            
            if playback.displayMode == .lyrics {
                mediaCenter(track: track, size: artworkDimension)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                mediaCenter(track: track, size: artworkDimension)
                    .frame(height: playback.displayMode == .video
                           ? UIScreen.main.bounds.width * 9 / 16
                           : artworkDimension + 20)
                
                // Video tab: the lyrics fill the space under the video, when there are any
                if playback.displayMode == .video && hasLyrics {
                    LyricsView(playback: playback, compact: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 6)
                        .mask(
                            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                                   .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                } else {
                    Spacer(minLength: 12)
                }
            }
            
            if let error = playback.errorMessage {
                Text(error)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.75), in: Capsule())
                    .padding(.horizontal, 20)
                    .multilineTextAlignment(.center)
            }
            
            trackInfo(track: track)
                .padding(.horizontal, 28)
            
            scrubber
                .padding(.horizontal, 28)
                .padding(.top, 4)
            
            mediaControls
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 28)
        }
    }
    
    // MARK: - Landscape Layout (Side-by-Side)
    private func landscapeContent(geo: GeometryProxy, track: MediaTrack) -> some View {
        VStack(spacing: 6) {
            topBar(track: track)
                .padding(.horizontal, 24)
                .padding(.top, 6)
            
            if playback.displayMode == .lyrics {
                HStack(spacing: 20) {
                    // Left Column: Info + Scrubber + Controls
                    VStack(spacing: 8) {
                        Spacer(minLength: 0)
                        trackInfo(track: track)
                        scrubber
                        mediaControls
                        Spacer(minLength: 0)
                    }
                    .frame(width: min(geo.size.width * 0.40, 320))
                    .padding(.leading, 24)
                    
                    // Right Column: Expansive Lyrics
                    mediaCenter(track: track, size: geo.size.height - 80)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.trailing, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 24) {
                    // Left Column: Artwork / Video / Lyrics
                    let mediaSize = max(140, min(geo.size.height - 80, geo.size.width * 0.44))
                    mediaCenter(track: track, size: mediaSize)
                        .frame(width: playback.displayMode == .video ? mediaSize * 16 / 9 : mediaSize,
                               height: mediaSize)
                        .padding(.leading, 24)
                    
                    // Right Column: Info + Scrubber + Controls
                    VStack(spacing: 8) {
                        Spacer(minLength: 0)
                        trackInfo(track: track)
                        scrubber
                        mediaControls
                        Spacer(minLength: 0)
                    }
                    .padding(.trailing, 24)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Top Bar
    private func topBar(track: MediaTrack) -> some View {
        HStack {
            Button {
                Haptics.light()
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AuraTheme.textSecondary)
                    .frame(width: 44, height: 44)
            }
            
            Spacer()
            
            // Audio / Video / Lyrics Segmented Pill
            HStack(spacing: 2) {
                ForEach(PlaybackDisplayMode.allCases, id: \.self) { mode in
                    Button {
                        Haptics.light()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            playback.displayMode = mode
                        }
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(playback.displayMode == mode ? .white : AuraTheme.textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                playback.displayMode == mode ? AuraTheme.primary : Color.clear
                            )
                            .cornerRadius(14)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .padding(3)
            .background(AuraTheme.surfaceElevated.opacity(0.95))
            .cornerRadius(17)
            
            Spacer()
            
            optionsMenu(track: track)
        }
    }
    
    // MARK: - Center Media Area
    private func mediaCenter(track: MediaTrack, size: CGFloat) -> some View {
        ZStack {
            ZStack(alignment: .bottomTrailing) {
                if playback.displayMode == .video {
                    YouTubeWebPlayerView(playback: playback, hostID: "player-sheet")
                        .aspectRatio(16/9, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                    Button {
                        Haptics.light()
                        showFullScreenVideo = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(10)
                }
            }
            .opacity(playback.displayMode == .video ? 1.0 : 0.001)
            .allowsHitTesting(playback.displayMode == .video)
            
            if playback.displayMode == .audio {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(AuraTheme.surfaceElevated)
                        .shadow(color: AuraTheme.primary.opacity(playback.isPlaying ? 0.35 : 0.08), radius: 24, x: 0, y: 12)
                    
                    if let artStr = playback.activeArtworkURL ?? track.effectiveThumbnailURL,
                       let url = URL(string: artStr) {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img.resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: size, height: size)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 24))
                            } else {
                                Image(systemName: "music.note")
                                    .font(.system(size: 54))
                                    .foregroundColor(AuraTheme.textTertiary)
                            }
                        }
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 54))
                            .foregroundColor(AuraTheme.textTertiary)
                    }
                }
                .frame(width: size, height: size)
                .scaleEffect(playback.isPlaying ? 1.0 : 0.88)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: playback.isPlaying)
            } else if playback.displayMode == .lyrics {
                ZStack(alignment: .bottomTrailing) {
                    LyricsView(playback: playback)
                    
                    Button {
                        Haptics.light()
                        showFullScreenLyrics = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(10)
                }
            }
        }
    }
    
    // MARK: - Track Info
    private func trackInfo(track: MediaTrack) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(AuraTheme.textPrimary)
                    .lineLimit(1)
                
                Text(track.artist)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AuraTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            
            if track.sourceType == .youtube {
                Button {
                    Haptics.light()
                    playback.confirmCurrentVideo()
                } label: {
                    Image(systemName: playback.isCurrentVideoConfirmed ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.system(size: 19))
                        .foregroundColor(playback.isCurrentVideoConfirmed ? .green : AuraTheme.textSecondary)
                        .frame(width: 40, height: 44)
                }
                Button {
                    Haptics.medium()
                    playback.rejectCurrentVideo()
                } label: {
                    Image(systemName: "hand.thumbsdown")
                        .font(.system(size: 19))
                        .foregroundColor(AuraTheme.textSecondary)
                        .frame(width: 40, height: 44)
                }
            }
            
            Button {
                Haptics.light()
                playlistStore.toggleFavorite(track: track)
            } label: {
                Image(systemName: playlistStore.isTrackFavorite(track) ? "heart.fill" : "heart")
                    .font(.system(size: 22))
                    .foregroundColor(playlistStore.isTrackFavorite(track) ? AuraTheme.primary : AuraTheme.textSecondary)
                    .frame(width: 44, height: 44)
            }
        }
    }
    
    // MARK: - Scrubber
    private var scrubber: some View {
        ClockObserver(playback.clock) { time in
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { currentProgress(at: time) },
                        set: { val in
                            isDraggingSlider = true
                            sliderValue = val
                        }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        if !editing {
                            let targetSec = sliderValue * playback.duration
                            playback.seek(to: targetSec)
                            isDraggingSlider = false
                        }
                    }
                )
                .tint(AuraTheme.primary)
                
                HStack {
                    Text(formatTime(isDraggingSlider ? sliderValue * playback.duration : time))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(AuraTheme.textTertiary)
                    Spacer()
                    Text(formatTime(playback.duration))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(AuraTheme.textTertiary)
                }
            }
        }
    }
    
    // MARK: - Media Controls
    private var mediaControls: some View {
        HStack {
            Spacer()
            
            // Shuffle
            Button {
                Haptics.light()
                playback.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(playback.isShuffled ? AuraTheme.primary : AuraTheme.textTertiary)
                    .frame(width: 44, height: 44)
            }
            
            Spacer()
            
            // Previous
            Button {
                Haptics.light()
                playback.playPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(AuraTheme.textPrimary)
                    .frame(width: 44, height: 44)
            }
            
            Spacer()
            
            // Play / Pause Large Glow Circle
            Button {
                Haptics.medium()
                playback.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.85))
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .frame(width: 66, height: 66)
                        .shadow(color: Color(hex: 0x3A2E9A).opacity(0.45), radius: 16, x: 0, y: 8)
                    
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(Color(hex: 0x7B6BE0))
                        .offset(x: playback.isPlaying ? 0 : 2)
                }
            }
            .frame(width: 66, height: 66)
            
            Spacer()
            
            // Next
            Button {
                Haptics.light()
                playback.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(AuraTheme.textPrimary)
                    .frame(width: 44, height: 44)
            }
            
            Spacer()
            
            // Repeat
            Button {
                Haptics.light()
                playback.repeatMode = (playback.repeatMode + 1) % 3
                playback.rememberSettings()
            } label: {
                Image(systemName: playback.repeatMode == 2 ? "repeat.1" : "repeat")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(playback.repeatMode > 0 ? AuraTheme.primary : AuraTheme.textTertiary)
                    .frame(width: 44, height: 44)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Options Menu
    private func optionsMenu(track: MediaTrack) -> some View {
        Menu {
            Button {
                UIPasteboard.general.string = CurrentSongMenu.nameToCopy(track)
                Haptics.light()
            } label: {
                Label("Copy Song Name", systemImage: "doc.on.doc")
            }

            Button {
                Haptics.light()
                let text = PlatformShareService.formatWhatsAppSongShare(track: track)
                let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootVC = windowScene.windows.first?.rootViewController {
                    rootVC.present(av, animated: true)
                }
            } label: {
                Label("Share Song (WhatsApp / Link)", systemImage: "square.and.arrow.up")
            }
            
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
            
            if hasLyrics {
                Button {
                    showFullScreenLyrics = true
                } label: {
                    Label("Full Screen Lyrics", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            }
            
            Button {
                showLyricsEditor = true
            } label: {
                Label(CustomLyricsStore.shared.hasLyrics(for: track) ? "Edit My Lyrics…" : "Add / Sync Lyrics…", systemImage: "text.quote")
            }
            
            Section("Start & End Time") {
                Button {
                    let now = playback.currentTime
                    let end = (track.endTime ?? 0) > now + 1 ? track.endTime : nil
                    playlistStore.setTrimTimes(for: track, start: now, end: end)
                    playback.currentTrack?.startTime = now
                    playback.currentTrack?.endTime = end
                } label: {
                    Label("Start From Current Position", systemImage: "arrow.right.to.line")
                }
                Button {
                    let now = playback.currentTime
                    let start = (track.startTime ?? 0) < now - 1 ? track.startTime : nil
                    playlistStore.setTrimTimes(for: track, start: start, end: now)
                    playback.currentTrack?.startTime = start
                    playback.currentTrack?.endTime = now
                } label: {
                    Label("End at Current Position", systemImage: "arrow.left.to.line")
                }
                Button {
                    showTrimTimes = true
                } label: {
                    Label("Set Start & End Time…", systemImage: "scissors")
                }
                if track.startTime != nil || track.endTime != nil {
                    Button(role: .destructive) {
                        playlistStore.setTrimTimes(for: track, start: nil, end: nil)
                        playback.currentTrack?.startTime = nil
                        playback.currentTrack?.endTime = nil
                    } label: {
                        Label("Clear Start & End Time", systemImage: "xmark.circle")
                    }
                }
            }
            
            Button {
                playlistStore.toggleFavorite(track: track)
            } label: {
                Label(playlistStore.isTrackFavorite(track) ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: playlistStore.isTrackFavorite(track) ? "heart.slash" : "heart")
            }
            
            Divider()
            
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    playerTheme = (playerTheme == .modern ? .sansa : .modern)
                }
            } label: {
                Label(
                    playerTheme == .modern ? "Switch to Sansa e260 Theme" : "Switch to Modern Glass",
                    systemImage: playerTheme == .modern ? "opticaldisc.fill" : "iphone"
                )
            }
            
            Button {
                showSettings = true
            } label: {
                Label("Player Settings...", systemImage: "gearshape.fill")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(AuraTheme.textSecondary)
                .frame(width: 44, height: 44)
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

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
