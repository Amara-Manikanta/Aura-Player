import SwiftUI

public struct AudioPlayerView: View {
    @Bindable var playback: PlaybackManager
    @State private var showLyrics: Bool = false
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
                            showLyrics.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showLyrics ? "music.note" : "quote.bubble.fill")
                                .font(.system(size: 12))
                            Text(showLyrics ? "Cover Art" : "Lyrics")
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
                
                if showLyrics {
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
                            LazyVStack(alignment: .leading, spacing: 18) {
                                ForEach(lyrics.syncedLines) { line in
                                    let isCurrent = isCurrentLine(line, in: lyrics.syncedLines)
                                    
                                    Button {
                                        playback.seek(to: line.time)
                                    } label: {
                                        Text(line.text)
                                            .font(.system(size: isCurrent ? 24 : 19, weight: isCurrent ? .bold : .medium, design: .rounded))
                                            .foregroundStyle(isCurrent ? Color.white : Color.white.opacity(0.35))
                                            .multilineTextAlignment(.leading)
                                            .padding(.vertical, 4)
                                            .padding(.horizontal, 10)
                                            .background(
                                                isCurrent ? RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)) : nil
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .id(line.id)
                                }
                            }
                            .padding(.horizontal, 40)
                            .padding(.vertical, 20)
                        }
                        .onChange(of: playback.currentTime) { _, newTime in
                            if let active = activeLine(at: newTime, in: lyrics.syncedLines) {
                                withAnimation(.easeInOut(duration: 0.3)) {
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
            Spacer()
        }
    }
    
    private func activeLine(at time: TimeInterval, in lines: [LyricLine]) -> LyricLine? {
        var current: LyricLine? = nil
        for line in lines {
            if line.time <= time + 0.3 {
                current = line
            } else {
                break
            }
        }
        return current
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
