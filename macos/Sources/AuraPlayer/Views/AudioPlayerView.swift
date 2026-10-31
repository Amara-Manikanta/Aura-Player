import SwiftUI

public struct AudioPlayerView: View {
    @Bindable var playback: PlaybackManager
    @State private var showLyricsEditor: Bool = false
    @State private var waveAnimation: Bool = false
    @AppStorage("showVisualizer") private var showVisualizer = true
    
    public init(playback: PlaybackManager) {
        self.playback = playback
    }
    
    public var body: some View {
        ZStack {
            // Ambient glowing gradient background
            LinearGradient(
                colors: [
                    Color.purple.opacity(0.25),
                    Color.blue.opacity(0.18),
                    Color.black.opacity(0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Lights and spectrum that move with the music (Playback ▸ Show Visualizer)
            if showVisualizer {
                MusicVisualizer(isPlaying: playback.isPlaying)
            }
            
            VStack(spacing: 0) {
                // Top mode switcher (Artwork vs Lyrics) and song options
                HStack {
                    Spacer()
                    CurrentSongMenu(playback: playback, iconColor: .white.opacity(0.85), iconSize: 18)
                        .padding(.top, 16)
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            playback.displayMode = (playback.displayMode == .lyrics) ? .audio : .lyrics
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: playback.displayMode == .lyrics ? "music.note" : "quote.bubble.fill")
                                .font(.system(size: 12))
                            Text(playback.displayMode == .lyrics ? "Cover Art" : "Lyrics")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                    .padding(.trailing, 24)
                }
                
                if playback.displayMode == .lyrics {
                    // Synchronized & Plain Lyrics View
                    lyricsContentView
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    // Album Artwork & Visualizer View
                    artworkContentView
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
    }
    
    // MARK: - Album Artwork View
    private var artworkContentView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Album Artwork with Ambient Shadow
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.purple.opacity(0.35))
                    .blur(radius: 45)
                    .frame(width: 290, height: 290)
                
                if let thumb = playback.currentArtworkURL ?? playback.currentTrack?.thumbnailURL,
                   let url = URL(string: thumb) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 290, height: 290)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.6), radius: 30, x: 0, y: 15)
                        default:
                            fallbackArtwork
                        }
                    }
                } else {
                    fallbackArtwork
                }
            }
            .scaleEffect(playback.isPlaying ? 1.02 : 0.98)
            .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: playback.isPlaying)
            
            // Track Info & Badges
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    if let track = playback.currentTrack {
                        if track.sourceType == .youtube {
                            Label("YouTube Stream", systemImage: "play.rectangle.fill")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.red.opacity(0.85)))
                            
                            Label("Ad-Free Stream", systemImage: "sparkles")
                                .font(.caption2.bold())
                                .foregroundStyle(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.green.opacity(0.18)))
                        } else {
                            Label("Local Lossless", systemImage: "folder.fill")
                                .font(.caption2.bold())
                                .foregroundStyle(.cyan)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.cyan.opacity(0.18)))
                        }
                    }
                }
                
                Text(playback.currentTrack?.title ?? "No Track Playing")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Text(playback.currentTrack?.artist ?? "Select a track to start listening")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            
            // Animated Audio Visualizer Waves
            HStack(spacing: 5) {
                ForEach(0..<20, id: \.self) { index in
                    VisualizerBar(
                        isPlaying: playback.isPlaying,
                        delay: Double(index) * 0.07
                    )
                }
            }
            .frame(height: 38)
            .padding(.top, 4)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Lyrics View (Apple Music Style Karaoke)
    private var lyricsContentView: some View {
        ZStack {
            if let track = playback.currentTrack,
               let deity = DevotionalDeity.detect(track: track) {
                DevotionalGodEffectsView(deity: deity, isPlaying: playback.isPlaying)
                    .allowsHitTesting(false)
            }
            
            VStack(spacing: 16) {
            // Track Header
            HStack(spacing: 12) {
                if let thumb = playback.currentArtworkURL ?? playback.currentTrack?.thumbnailURL,
                   let url = URL(string: thumb) {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.purple.opacity(0.3)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(playback.currentTrack?.title ?? "")
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                    Text(playback.currentTrack?.artist ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if let lyrics = playback.lyrics, lyrics.isSynced || !(lyrics.plainLyrics ?? "").isEmpty {
                    // Fix wrong lyrics or timing
                    Button {
                        showLyricsEditor = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .help("Edit or re-sync these lyrics")
                }
                
                if let lyrics = playback.lyrics, lyrics.isSynced {
                    Label("Time-Synced", systemImage: "clock.arrow.circlepath")
                        .font(.caption2.bold())
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.purple.opacity(0.2)))
                }
            }
            .padding(.horizontal, 40)
            .sheet(isPresented: $showLyricsEditor) {
                if let track = playback.currentTrack { LyricsEditorSheet(track: track, playback: playback) }
            }
            
            Divider().padding(.horizontal, 40)
            
            if playback.isFetchingLyrics {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                    Text("Searching lyrics...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if let lyrics = playback.lyrics {
                if lyrics.isSynced {
                    // Time-Synced Karaoke Lyrics
                    ScrollViewReader { proxy in
                        ScrollView {
                            let activeIdx = activeLineIndex(at: playback.currentTime, in: lyrics.syncedLines)
                            
                            LazyVStack(alignment: .leading, spacing: 18) {
                                ForEach(Array(lyrics.syncedLines.enumerated()), id: \.element.id) { index, line in
                                    let isCurrent = (index == activeIdx)
                                    let isPast = (activeIdx != nil && index < activeIdx!)
                                    
                                    Button {
                                        playback.seek(to: line.time)
                                    } label: {
                                        HStack(alignment: .center, spacing: 12) {
                                            if isCurrent && playback.isPlaying {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "music.note")
                                                        .font(.system(size: 14, weight: .bold))
                                                    Circle().frame(width: 5, height: 5)
                                                }
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: DevotionalDeity.detect(track: playback.currentTrack) != nil ? [.white, Color.orange] : [.white, Color.purple],
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    )
                                                )
                                                .transition(.scale.combined(with: .opacity))
                                            }
                                            
                                            Text(line.text)
                                                .font(.system(size: isCurrent ? 25 : 19, weight: isCurrent ? .bold : .medium, design: .rounded))
                                                .foregroundStyle(isCurrent ? Color.white : (isPast ? Color.white.opacity(0.60) : Color.white.opacity(0.35)))
                                                .multilineTextAlignment(.leading)
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 16)
                                        .background {
                                            if isCurrent {
                                                let isDevotional = playback.currentTrack.flatMap(DevotionalDeity.detect) != nil
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                    .fill(
                                                        LinearGradient(
                                                            colors: isDevotional ? [
                                                                Color(red: 1.0, green: 0.85, blue: 0.4).opacity(0.24),
                                                                Color(red: 1.0, green: 0.55, blue: 0.1).opacity(0.18),
                                                                Color.white.opacity(0.08)
                                                            ] : [
                                                                Color.white.opacity(0.18),
                                                                Color.purple.opacity(0.15),
                                                                Color.white.opacity(0.06)
                                                            ],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        )
                                                    )
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                            .stroke(
                                                                LinearGradient(
                                                                    colors: isDevotional ? [
                                                                        Color(red: 1.0, green: 0.88, blue: 0.5).opacity(0.65),
                                                                        Color(red: 1.0, green: 0.6, blue: 0.1).opacity(0.4),
                                                                        Color.white.opacity(0.12)
                                                                    ] : [
                                                                        Color.white.opacity(0.55),
                                                                        Color.purple.opacity(0.35),
                                                                        Color.white.opacity(0.08)
                                                                    ],
                                                                    startPoint: .topLeading,
                                                                    endPoint: .bottomTrailing
                                                                ),
                                                                lineWidth: 1.2
                                                            )
                                                    )
                                                    .shadow(color: (isDevotional ? Color.orange : Color.purple).opacity(0.35), radius: 14, x: 0, y: 4)
                                                    .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 2)
                                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                            }
                                        }
                                        .scaleEffect(isCurrent ? 1.02 : 0.97)
                                        .blur(radius: isCurrent ? 0 : (isPast ? 0.2 : 0.45))
                                        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: isCurrent)
                                    }
                                    .buttonStyle(.plain)
                                    .id(line.id)
                                }
                            }
                            .padding(.horizontal, 40)
                            .padding(.vertical, 24)
                        }
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: 0.08),
                                    .init(color: .black, location: 0.92),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .onAppear {
                            if let active = activeLine(at: playback.currentTime, in: lyrics.syncedLines) {
                                proxy.scrollTo(active.id, anchor: .center)
                            }
                        }
                        .onChange(of: playback.currentTime) { _, newTime in
                            if let active = activeLine(at: newTime, in: lyrics.syncedLines) {
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                                    proxy.scrollTo(active.id, anchor: .center)
                                }
                            }
                        }
                    }
                } else if let plain = lyrics.plainLyrics, !plain.isEmpty {
                    // Static Plain Lyrics
                    ScrollView {
                        Text(plain)
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .lineSpacing(8)
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 48)
                            .padding(.vertical, 20)
                    }
                } else {
                    noLyricsPlaceholder
                }
            } else {
                noLyricsPlaceholder
            }
        }
    }
    }
    
    private var noLyricsPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "music.mic")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No Lyrics Available")
                .font(.headline)
            Text("Lyrics could not be found for this track or it may be instrumental.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                showLyricsEditor = true
            } label: {
                Label("Add Lyrics", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .padding(.top, 4)
            Spacer()
        }
    }
    
    private func activeLine(at time: TimeInterval, in lines: [LyricLine]) -> LyricLine? {
        if let idx = activeLineIndex(at: time, in: lines) {
            return lines[idx]
        }
        return nil
    }
    
    private func activeLineIndex(at time: TimeInterval, in lines: [LyricLine]) -> Int? {
        guard !lines.isEmpty else { return nil }
        // Before first lyric or during intro, keep the upcoming first line active
        if let first = lines.first, time < first.time {
            return 0
        }
        var index: Int = 0
        for (i, line) in lines.enumerated() {
            if line.time <= time + 0.32 {
                index = i
            } else {
                break
            }
        }
        return index
    }
    
    private func isCurrentLine(_ line: LyricLine, in lines: [LyricLine]) -> Bool {
        guard let active = activeLine(at: playback.currentTime, in: lines) else { return false }
        return active.id == line.id
    }
    
    private var fallbackArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.indigo.opacity(0.8), Color.purple.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 290, height: 290)
                .shadow(color: .black.opacity(0.5), radius: 25, x: 0, y: 12)
            
            Image(systemName: "music.note")
                .font(.system(size: 85, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

public struct VisualizerBar: View {
    public let isPlaying: Bool
    public let delay: Double
    @State private var barHeight: CGFloat = 8
    
    public init(isPlaying: Bool, delay: Double) {
        self.isPlaying = isPlaying
        self.delay = delay
    }
    
    public var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(
                LinearGradient(
                    colors: [Color.cyan, Color.purple],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 4, height: isPlaying ? barHeight : 6)
            .onAppear {
                if isPlaying {
                    startAnimating()
                }
            }
            .onChange(of: isPlaying) { _, playing in
                if playing {
                    startAnimating()
                } else {
                    withAnimation(.easeOut(duration: 0.3)) {
                        barHeight = 6
                    }
                }
            }
    }
    
    private func startAnimating() {
        withAnimation(
            .easeInOut(duration: Double.random(in: 0.3...0.7))
            .repeatForever(autoreverses: true)
            .delay(delay)
        ) {
            barHeight = CGFloat.random(in: 12...36)
        }
    }
}
