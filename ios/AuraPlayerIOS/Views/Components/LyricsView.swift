import SwiftUI

public struct LyricsView: View {
    @ObservedObject var playback: PlaybackManager
    /// Smaller text and tighter spacing, for the strip under the video
    private let compact: Bool
    /// Full-screen display mode with larger typography and breathing room
    private let isFullScreen: Bool
    /// Draw the devotional sparks and idol behind the lyrics. The player draws them behind the whole screen instead.
    private let showsEffects: Bool
    @State private var showEditor = false
    
    public init(playback: PlaybackManager, compact: Bool = false, isFullScreen: Bool = false, showsEffects: Bool = true) {
        self.playback = playback
        self.compact = compact
        self.isFullScreen = isFullScreen
        self.showsEffects = showsEffects
    }
    
    public var body: some View {
        ZStack {
            if showsEffects, !compact, let track = playback.currentTrack,
               let deity = DevotionalDeity.detect(track: track) {
                DevotionalGodEffectsView(deity: deity, isPlaying: playback.isPlaying)
                    .allowsHitTesting(false)
            }
            
            content
                .sheet(isPresented: $showEditor) {
                    if let track = playback.currentTrack { LyricsEditorSheet(track: track, playback: playback) }
                }
                .overlay(alignment: .topTrailing) {
                    // Fix wrong lyrics or timing (hidden in full-screen as full-screen has its own header button)
                    if !compact && !isFullScreen, playback.currentTrack != nil, let l = playback.lyrics, l.isSynced || !(l.plainLyrics ?? "").isEmpty {
                        Button {
                            Haptics.light()
                            showEditor = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AuraTheme.textPrimary)
                                .frame(width: 36, height: 36)
                                .liquidGlass(cornerRadius: 18)
                        }
                        .padding(.trailing, 12)
                    }
                }
        }
        // Whatever is inside (long lines, the idol, the sparks) must never make the player wider than the screen
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
    
    @ViewBuilder
    private var content: some View {
        Group {
            if playback.isLyricsLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(AuraTheme.primary)
                    Text("Fetching synchronized lyrics...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AuraTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let lyrics = playback.lyrics, lyrics.isSynced {
                let isDevotional = !compact && playback.currentTrack.flatMap(DevotionalDeity.detect) != nil
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        // a plain VStack: with lazy rows, scrolling to a line far down landed in the wrong place
                        VStack(alignment: isDevotional ? .leading : .center, spacing: compact ? 10 : (isFullScreen ? 20 : 16)) {
                            ForEach(Array(lyrics.syncedLines.enumerated()), id: \.element.id) { index, line in
                                let isActive = (index == playback.currentLyricIndex)
                                let isPast = (playback.currentLyricIndex >= 0 && index < playback.currentLyricIndex)
                                
                                Button {
                                    Haptics.light()
                                    playback.seek(to: line.time)
                                } label: {
                                    HStack(spacing: 8) {
                                        if isActive && playback.isPlaying {
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [AuraTheme.primary, Color.white],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: compact ? 6 : (isFullScreen ? 8 : 7), height: compact ? 6 : (isFullScreen ? 8 : 7))
                                                .shadow(color: AuraTheme.primary, radius: 4)
                                                .transition(.scale.combined(with: .opacity))
                                        }
                                        
                                        Text(line.text)
                                            .font(
                                                .system(
                                                    size: compact ? (isActive ? 18 : 15) : (isFullScreen ? (isActive ? 28 : 20) : (isActive ? 24 : 18)),
                                                    weight: isActive ? .bold : .medium,
                                                    design: .rounded
                                                )
                                            )
                                            .lineSpacing(compact ? 4 : (isFullScreen ? 8 : 6))
                                            .foregroundColor(
                                                isActive
                                                    ? Color.white
                                                    : (isPast ? AuraTheme.textSecondary.opacity(0.60) : AuraTheme.textTertiary.opacity(0.75))
                                            )
                                            .multilineTextAlignment(isDevotional ? .leading : .center)
                                            // long lines wrap inside the screen instead of widening the whole player
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.horizontal, compact ? 16 : (isFullScreen ? 26 : 20))
                                    .padding(.vertical, compact ? 8 : (isFullScreen ? 14 : 12))
                                    .frame(maxWidth: .infinity, alignment: isDevotional ? .leading : .center)
                                    .background {
                                        if isActive {
                                            let isDev = !compact && playback.currentTrack.flatMap(DevotionalDeity.detect) != nil
                                            RoundedRectangle(cornerRadius: compact ? 14 : (isFullScreen ? 20 : 18), style: .continuous)
                                                .fill(
                                                    LinearGradient(
                                                        colors: isDev ? [
                                                            Color(red: 1.0, green: 0.85, blue: 0.4).opacity(0.24),
                                                            Color(red: 1.0, green: 0.55, blue: 0.1).opacity(0.18),
                                                            Color.white.opacity(0.08)
                                                        ] : [
                                                            Color.white.opacity(0.18),
                                                            AuraTheme.primary.opacity(0.14),
                                                            Color.white.opacity(0.06)
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: compact ? 14 : (isFullScreen ? 20 : 18), style: .continuous)
                                                        .stroke(
                                                            LinearGradient(
                                                                colors: isDev ? [
                                                                    Color(red: 1.0, green: 0.88, blue: 0.5).opacity(0.65),
                                                                    Color(red: 1.0, green: 0.6, blue: 0.1).opacity(0.4),
                                                                    Color.white.opacity(0.12)
                                                                ] : [
                                                                    Color.white.opacity(0.55),
                                                                    AuraTheme.primary.opacity(0.35),
                                                                    Color.white.opacity(0.08)
                                                                ],
                                                                startPoint: .topLeading,
                                                                endPoint: .bottomTrailing
                                                            ),
                                                            lineWidth: 1.2
                                                        )
                                                )
                                                .shadow(color: (isDev ? Color.orange : AuraTheme.primary).opacity(0.35), radius: 14, x: 0, y: 4)
                                                .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 2)
                                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                        }
                                    }
                                    .scaleEffect(isActive ? 1.02 : 0.97, anchor: isDevotional ? .leading : .center)
                                    .blur(radius: isActive ? 0 : (isPast ? 0.2 : 0.45))
                                    .animation(.spring(response: 0.35, dampingFraction: 0.72), value: isActive)
                                }
                                .buttonStyle(AuraPlainButtonStyle())
                                .id(line.id)
                            }
                        }
                        .padding(.leading, isDevotional ? (isFullScreen ? 28 : 22) : (compact ? 16 : 22))
                        .padding(.trailing, isDevotional ? (isFullScreen ? 160 : 135) : (compact ? 16 : (isFullScreen ? 28 : 22)))
                        .padding(.vertical, compact ? 16 : (isFullScreen ? 48 : 40))
                        .frame(maxWidth: .infinity)
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
                    // Opening mid-song: start at the line being sung
                    .onAppear {
                        let i = playback.currentLyricIndex
                        if i >= 0, i < lyrics.syncedLines.count {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                                    proxy.scrollTo(lyrics.syncedLines[i].id, anchor: .center)
                                }
                            }
                        }
                    }
                    .onChange(of: playback.currentLyricIndex) { _, newIndex in
                        if newIndex >= 0 && newIndex < lyrics.syncedLines.count {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                                proxy.scrollTo(lyrics.syncedLines[newIndex].id, anchor: .center)
                            }
                        }
                    }
                }
            } else if let plain = playback.lyrics?.plainLyrics, !plain.isEmpty {
                let isDevotional = !compact && playback.currentTrack.flatMap(DevotionalDeity.detect) != nil
                ScrollView(showsIndicators: false) {
                    Text(plain)
                        .font(.system(size: isFullScreen ? 22 : 18, weight: .medium))
                        .foregroundColor(AuraTheme.textSecondary)
                        .lineSpacing(isFullScreen ? 14 : 10)
                        .multilineTextAlignment(isDevotional ? .leading : .center)
                        .padding(.leading, isDevotional ? (isFullScreen ? 28 : 22) : (compact ? 16 : (isFullScreen ? 32 : 24)))
                        .padding(.trailing, isDevotional ? (isFullScreen ? 160 : 135) : (compact ? 16 : (isFullScreen ? 32 : 24)))
                        .padding(.vertical, isFullScreen ? 36 : 24)
                        .frame(maxWidth: .infinity, alignment: isDevotional ? .leading : .center)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "music.mic")
                        .font(.system(size: 44))
                        .foregroundColor(AuraTheme.textTertiary)
                    Text("No Lyrics Available")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AuraTheme.textPrimary)
                    Text("Instrumental or lyrics haven't been added yet.")
                        .font(.system(size: 14))
                        .foregroundColor(AuraTheme.textTertiary)
                    if !compact, playback.currentTrack != nil {
                        Button {
                            Haptics.light()
                            showEditor = true
                        } label: {
                            Label("Add Lyrics", systemImage: "plus")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(AuraTheme.primaryGradient, in: Capsule())
                        }
                        .padding(.top, 6)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
