import SwiftUI

public struct LyricsView: View {
    @ObservedObject var playback: PlaybackManager
    /// Smaller text and tighter spacing, for the strip under the video
    private let compact: Bool
    @State private var showEditor = false
    
    public init(playback: PlaybackManager, compact: Bool = false) {
        self.playback = playback
        self.compact = compact
    }
    
    public var body: some View {
        content
            .sheet(isPresented: $showEditor) {
                if let track = playback.currentTrack { LyricsEditorSheet(track: track, playback: playback) }
            }
            .overlay(alignment: .topTrailing) {
                // Fix wrong lyrics or timing
                if !compact, playback.currentTrack != nil, let l = playback.lyrics, l.isSynced || !(l.plainLyrics ?? "").isEmpty {
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
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .center, spacing: compact ? 10 : 16) {
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
                                                .frame(width: compact ? 6 : 7, height: compact ? 6 : 7)
                                                .shadow(color: AuraTheme.primary, radius: 4)
                                                .transition(.scale.combined(with: .opacity))
                                        }
                                        
                                        Text(line.text)
                                            .font(
                                                .system(
                                                    size: compact ? (isActive ? 19 : 15) : (isActive ? 25 : 18),
                                                    weight: isActive ? .bold : .medium,
                                                    design: .rounded
                                                )
                                            )
                                            .foregroundColor(
                                                isActive
                                                    ? Color.white
                                                    : (isPast ? AuraTheme.textSecondary.opacity(0.60) : AuraTheme.textTertiary.opacity(0.75))
                                            )
                                            .multilineTextAlignment(.center)
                                            // long lines wrap inside the screen instead of widening the whole player
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.horizontal, compact ? 16 : 22)
                                    .padding(.vertical, compact ? 8 : 12)
                                    .frame(maxWidth: .infinity)
                                    .background {
                                        if isActive {
                                            RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [
                                                            Color.white.opacity(0.18),
                                                            AuraTheme.primary.opacity(0.14),
                                                            Color.white.opacity(0.06)
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous)
                                                        .stroke(
                                                            LinearGradient(
                                                                colors: [
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
                                                .shadow(color: AuraTheme.primary.opacity(0.35), radius: 14, x: 0, y: 4)
                                                .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 2)
                                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                        }
                                    }
                                    .scaleEffect(isActive ? 1.03 : 0.96)
                                    .blur(radius: isActive ? 0 : (isPast ? 0.2 : 0.45))
                                    .animation(.spring(response: 0.35, dampingFraction: 0.72), value: isActive)
                                }
                                .buttonStyle(.plain)
                                .id(line.id)
                            }
                        }
                        .padding(.horizontal, compact ? 14 : 20)
                        .padding(.vertical, compact ? 16 : 40)
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
                        if i >= 0, i < lyrics.syncedLines.count { proxy.scrollTo(lyrics.syncedLines[i].id, anchor: .center) }
                    }
                    .onChange(of: playback.currentLyricIndex) { newIndex in
                        if newIndex >= 0 && newIndex < lyrics.syncedLines.count {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                                proxy.scrollTo(lyrics.syncedLines[newIndex].id, anchor: .center)
                            }
                        }
                    }
                }
            } else if let plain = playback.lyrics?.plainLyrics, !plain.isEmpty {
                ScrollView(showsIndicators: false) {
                    Text(plain)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(AuraTheme.textSecondary)
                        .lineSpacing(10)
                        .multilineTextAlignment(.center)
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .center)
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
