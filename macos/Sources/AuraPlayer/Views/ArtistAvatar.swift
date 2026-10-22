import SwiftUI

/// Round artist photo with a gradient + initial while loading or when no photo exists.
public struct ArtistAvatar: View {
    let name: String
    let size: CGFloat
    /// Used only if no artist photo can be found
    var fallbackArtworkURL: String? = nil
    
    @State private var photoURL: URL?
    @State private var lookupDone = false
    
    public var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color.purple.opacity(0.85), Color.indigo.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
            
            Text(initial)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(.white)
            
            if let url = photoURL ?? (lookupDone ? fallbackURL : nil) {
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
        .shadow(color: Color.purple.opacity(0.3), radius: size / 12, x: 0, y: size / 24)
        .task(id: name) {
            lookupDone = false
            photoURL = await ArtistPhotoService.shared.photoURL(for: name)
            lookupDone = true
        }
    }
    
    private var initial: String {
        String(name.prefix(1)).uppercased()
    }
    
    private var fallbackURL: URL? {
        fallbackArtworkURL.flatMap { URL(string: $0) }
    }
}
