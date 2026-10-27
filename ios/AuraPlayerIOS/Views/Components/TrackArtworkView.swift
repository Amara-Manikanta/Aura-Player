import SwiftUI

/// Square cover art for a song: the album cover found by TrackArtworkService (same lookup as the Mac app),
/// otherwise the saved thumbnail, otherwise a music-note placeholder.
public struct TrackArtworkView: View {
    let track: MediaTrack
    var size: CGFloat = 52
    var cornerRadius: CGFloat = 10
    
    @State private var coverURL: URL?
    
    public init(track: MediaTrack, size: CGFloat = 52, cornerRadius: CGFloat = 10) {
        self.track = track
        self.size = size
        self.cornerRadius = cornerRadius
    }
    
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
            if let cached = await TrackArtworkService.shared.cachedCover(for: track) {
                coverURL = cached
            } else {
                coverURL = await TrackArtworkService.shared.cover(for: track)
            }
        }
    }
    
    /// Artwork stored with the song (the video thumbnail) as a fallback
    private var savedURL: URL? {
        track.effectiveThumbnailURL.flatMap { URL(string: $0) }
    }
    
    private var placeholder: some View {
        Image(systemName: "music.note")
            .font(.system(size: size * 0.34))
            .foregroundColor(AuraTheme.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AuraTheme.surfaceElevated)
    }
}
