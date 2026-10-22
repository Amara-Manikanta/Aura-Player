import Foundation

public struct Playlist: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var iconName: String
    public var tracks: [MediaTrack]
    public var isBuiltIn: Bool
    
    public init(
        id: UUID = UUID(),
        name: String,
        iconName: String = "music.note.list",
        tracks: [MediaTrack] = [],
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.tracks = tracks
        self.isBuiltIn = isBuiltIn
    }
}
