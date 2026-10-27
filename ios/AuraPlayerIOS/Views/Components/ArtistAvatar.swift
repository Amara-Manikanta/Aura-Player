import SwiftUI

/// Round artist photo (Deezer, same lookup as the Mac app) with a gradient + initial while loading
/// or when no photo exists.
public struct ArtistAvatar: View {
    let name: String
    let size: CGFloat
    /// Used only if no artist photo can be found
    var fallbackArtworkURL: String? = nil
    
    @State private var photoURL: URL?
    @State private var lookupDone = false
    
    public init(name: String, size: CGFloat, fallbackArtworkURL: String? = nil) {
        self.name = name
        self.size = size
        self.fallbackArtworkURL = fallbackArtworkURL
    }
    
    public var body: some View {
        ZStack {
            Circle().fill(AuraTheme.primaryGradient)
            
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundColor(.white)
            
            if let url = photoURL ?? (lookupDone ? fallbackArtworkURL.flatMap { URL(string: $0) } : nil) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    }
                }
                .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: name) {
            lookupDone = false
            photoURL = await ArtistPhotoService.shared.photoURL(for: name)
            lookupDone = true
        }
    }
}
