import SwiftUI

/// Square cover art for a song: the saved artwork if there is one, otherwise the album cover found
/// by TrackArtworkService, otherwise the video thumbnail or a music-note placeholder.
public struct TrackArtworkView: View {
    let track: MediaTrack
    var size: CGFloat = 44
    var cornerRadius: CGFloat = 6
    
    @State private var coverURL: URL?
    
    public var body: some View {
        Group {
            if let url = coverURL ?? savedURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: track.id) {
            guard track.sourceType != .local || track.thumbnailURL == nil else { return }
            if let cached = await TrackArtworkService.shared.cachedCover(for: track) {
                coverURL = cached
            } else {
                coverURL = await TrackArtworkService.shared.cover(for: track)
            }
        }
    }
    
    /// Artwork stored with the song (for songs added from YouTube) as a fallback
    private var savedURL: URL? {
        track.thumbnailURL.flatMap { URL(string: $0) }
    }
    
    private var placeholder: some View {
        Image(systemName: track.mediaType == .video ? "film" : "music.note")
            .font(.system(size: size * 0.32))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.purple.opacity(0.15))
    }
}
