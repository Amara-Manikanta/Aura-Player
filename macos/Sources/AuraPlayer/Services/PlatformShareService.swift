import Foundation
#if os(macOS)
import AppKit
#endif

public struct SharedTrackPayload: Codable, Sendable {
    public let title: String
    public let artist: String
    public let yt: String?
    public let d: Double
    public let art: String?
    
    public init(title: String, artist: String = "", yt: String? = nil, d: Double = 0, art: String? = nil) {
        self.title = title
        self.artist = artist
        self.yt = yt
        self.d = d
        self.art = art
    }
}

public struct SharedPlaylistPayload: Codable, Sendable {
    public let type: String
    public let name: String
    public let tracks: [SharedTrackPayload]
    
    public init(type: String = "playlist", name: String = "Shared Playlist", tracks: [SharedTrackPayload] = []) {
        self.type = type
        self.name = name
        self.tracks = tracks
    }
}

public enum PlatformShareService {
    public static func createShareUrl(name: String, tracks: [MediaTrack]) -> String {
        let exportTracks = Array(tracks.prefix(50))
        let payload = SharedPlaylistPayload(
            type: "playlist",
            name: name,
            tracks: exportTracks.map {
                SharedTrackPayload(
                    title: $0.title,
                    artist: $0.artist,
                    yt: $0.youtubeId,
                    d: round($0.duration),
                    art: $0.youtubeId == nil ? $0.thumbnailURL : nil
                )
            }
        )
        guard let data = try? JSONEncoder().encode(payload) else { return "" }
        let b64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "https://amara-manikanta.github.io/Aura-Player/share.html#data=\(b64)"
    }

    public static func createSongShareUrl(track: MediaTrack) -> String {
        let payload = SharedPlaylistPayload(
            type: "song",
            name: track.title,
            tracks: [
                SharedTrackPayload(
                    title: track.title,
                    artist: track.artist,
                    yt: track.youtubeId,
                    d: round(track.duration),
                    art: track.youtubeId == nil ? track.thumbnailURL : nil
                )
            ]
        )
        guard let data = try? JSONEncoder().encode(payload) else { return "" }
        let b64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "https://amara-manikanta.github.io/Aura-Player/share.html#data=\(b64)"
    }

    public static func formatWhatsAppPlaylistShare(name: String, tracks: [MediaTrack]) -> String {
        var str = "🎶 *\(name.trimmingCharacters(in: .whitespacesAndNewlines))* (\(tracks.count) songs)\n"
        str += "Shared via Aura Player\n\n"
        let count = min(tracks.count, 8)
        for i in 0..<count {
            let t = tracks[i]
            str += "\(i + 1). \(t.title) - \(t.artist)\n"
        }
        if tracks.count > 8 {
            str += "... and \(tracks.count - 8) more songs\n"
        }
        str += "\n📲 *Add to Aura Player in 1-Tap:*\n"
        str += createShareUrl(name: name, tracks: tracks)
        return str
    }

    public static func formatWhatsAppSongShare(track: MediaTrack) -> String {
        var str = "🎵 *\(track.title.trimmingCharacters(in: .whitespacesAndNewlines))* - \(track.artist.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        if let yt = track.youtubeId, !yt.isEmpty {
            str += "Listen on YouTube: https://youtu.be/\(yt)\n\n"
        } else {
            str += "\n"
        }
        str += "📲 *Open in Aura Player:*\n"
        str += createSongShareUrl(track: track)
        return str
    }

    public static func decodePayload(from input: String) -> (name: String, tracks: [MediaTrack])? {
        var b64: String? = nil
        let regex = try? NSRegularExpression(pattern: #"[#?&](?:data|song)=([A-Za-z0-9_-]+={0,2})"#)
        if let match = regex?.firstMatch(in: input, range: NSRange(location: 0, length: input.utf16.count)) {
            if let range = Range(match.range(at: 1), in: input) {
                b64 = String(input[range])
            }
        } else if input.count > 20 && input.range(of: #"^[A-Za-z0-9_-]+={0,2}$"#, options: .regularExpression) != nil {
            b64 = input
        }

        guard let rawB64 = b64 else { return nil }
        var normalized = rawB64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while normalized.count % 4 != 0 {
            normalized.append("=")
        }
        guard let data = Data(base64Encoded: normalized),
              let payload = try? JSONDecoder().decode(SharedPlaylistPayload.self, from: data) else {
            return nil
        }

        let tracks = payload.tracks.map { item in
            MediaTrack(
                title: item.title,
                artist: item.artist.isEmpty ? "Unknown Artist" : item.artist,
                duration: item.d,
                sourceType: .youtube,
                originalURL: item.yt != nil ? "https://www.youtube.com/watch?v=\(item.yt!)" : "",
                thumbnailURL: item.art ?? (item.yt != nil ? "https://i.ytimg.com/vi/\(item.yt!)/hqdefault.jpg" : nil),
                youtubeId: item.yt
            )
        }
        return (payload.name, tracks)
    }

#if os(macOS)
    @MainActor
    public static func share(text: String, view: NSView? = nil) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        
        let picker = NSSharingServicePicker(items: [text])
        if let v = view ?? NSApp.keyWindow?.contentView {
            picker.show(relativeTo: v.bounds, of: v, preferredEdge: .minY)
        }
    }
#endif
}
