import SwiftUI
import UIKit

/// A suggested / new song: video thumbnail, title, singer, why it's here, views and age,
/// with a ⋯ menu to add it to a playlist (or hide it).
struct DiscoverRow: View {
    let video: YouTubeSearchResult
    let track: MediaTrack
    var reason: String? = nil
    var views: Int = 0
    var uploadedAgo: String = ""
    let isCurrent: Bool
    let isPlaying: Bool
    let onPlay: () -> Void
    let onAdd: () -> Void
    var onNotInterested: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: URL(string: video.thumbnailURL ?? "")) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        AuraTheme.surfaceElevated
                    }
                }
                .frame(width: 128, height: 72)
                .clipped()

                if isCurrent {
                    Color.black.opacity(0.4)
                    Image(systemName: isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Text(video.formattedDuration)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.75))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(4)
            }
            .frame(width: 128, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isCurrent ? AuraTheme.primary : .clear, lineWidth: 2)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isCurrent ? AuraTheme.primary : AuraTheme.textPrimary)
                    .lineLimit(2)
                Text(track.artist)
                    .font(.system(size: 12))
                    .foregroundColor(AuraTheme.textSecondary)
                    .lineLimit(1)
                if let reason {
                    Label(reason, systemImage: "sparkles")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AuraTheme.primary)
                        .lineLimit(1)
                }
                let stats = [views > 0 ? NewReleasesView.formatViews(views) : "", uploadedAgo].filter { !$0.isEmpty }
                if !stats.isEmpty {
                    Text(stats.joined(separator: " • "))
                        .font(.system(size: 11))
                        .foregroundColor(AuraTheme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Menu {
                Button { onPlay() } label: { Label("Play", systemImage: "play.fill") }
                Button { onAdd() } label: { Label("Add to Playlist", systemImage: "text.badge.plus") }
                // e.g. to fix a song in a playlist that plays a fake video: copy here, paste in Change Video Link
                Button {
                    UIPasteboard.general.string = "https://www.youtube.com/watch?v=\(video.id)"
                    Haptics.light()
                } label: { Label("Copy YouTube Link", systemImage: "doc.on.doc") }
                if let onNotInterested {
                    Button(role: .destructive) { onNotInterested() } label: {
                        Label("Not Interested", systemImage: "hand.thumbsdown")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AuraTheme.textSecondary)
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.light()
            onPlay()
        }
    }

    /// A YouTube video as a song: its full video title and channel, like the Mac app
    /// (shortening them guessed wrong too often: "Darling - Neeve Video | Prabhas" → "Neeve Video")
    static func track(from v: YouTubeSearchResult) -> MediaTrack {
        MediaTrack(
            title: v.title,
            artist: v.channel,
            duration: v.duration,
            sourceType: .youtube,
            mediaType: .video,
            originalURL: v.url,
            thumbnailURL: v.thumbnailURL,
            youtubeId: v.id
        )
    }
}
