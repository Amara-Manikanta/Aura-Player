import Foundation

/// What was playing when the app was closed: the song, its queue, where it was, and the player settings.
/// Written to a small file in the background and read back at launch.
struct PlaybackMemory: Codable {
    var track: MediaTrack
    /// Queue as library song ids; `queueTracks` is used instead when some songs aren't in the library
    /// (e.g. a list from Discover)
    var queueIds: [UUID]?
    var queueTracks: [MediaTrack]?
    var position: Double
    var contextPlaylistId: UUID?
    var shuffled: Bool
    var repeatMode: Int
    var displayMode: String
    
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("last_played.json")
    }()
    
    static func load() -> PlaybackMemory? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PlaybackMemory.self, from: data)
    }
    
    /// Writes off the main thread
    func save() {
        let copy = self
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(copy) { try? data.write(to: Self.url, options: .atomic) }
        }
    }
}
