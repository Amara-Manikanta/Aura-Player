import SwiftUI

public struct LyricsView: View {
    @ObservedObject var playback: PlaybackManager
    
    public init(playback: PlaybackManager) {
        self.playback = playback
    }
    
    public var body: some View {
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
                        LazyVStack(alignment: .leading, spacing: 22) {
                            ForEach(Array(lyrics.syncedLines.enumerated()), id: \.element.id) { index, line in
                                let isActive = (index == playback.currentLyricIndex)
                                let isPast = (index < playback.currentLyricIndex)
                                
                                Button {
                                    Haptics.light()
                                    playback.seek(to: line.time)
                                } label: {
                                    Text(line.text)
                                        .font(.system(size: isActive ? 24 : 19, weight: isActive ? .bold : .medium))
                                        .foregroundColor(isActive ? AuraTheme.primary : (isPast ? AuraTheme.textSecondary.opacity(0.6) : AuraTheme.textTertiary))
                                        .scaleEffect(isActive ? 1.05 : 0.98, anchor: .leading)
                                        .multilineTextAlignment(.leading)
                                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isActive)
                                }
                                .buttonStyle(.plain)
                                .id(line.id)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 40)
                    }
                    .onChange(of: playback.currentLyricIndex) { newIndex in
                        if newIndex < lyrics.syncedLines.count {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
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
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
