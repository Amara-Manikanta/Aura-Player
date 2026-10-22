import Foundation
import AVFoundation
import UIKit

public actor ArtworkService {
    public static let shared = ArtworkService()
    
    private var cache: [String: String] = [:]
    private let cacheDirectory: URL
    
    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("AuraPlayer/Artworks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.cacheDirectory = dir
    }
    
    public func resolveHighResArtwork(title: String, artist: String, localFilePath: String? = nil) async -> String? {
        let key = "\(title)-\(artist)".lowercased()
        if let cached = cache[key] {
            return cached
        }
        
        // 1. Check offline bundled track artwork cache from macOS library
        let cacheKey = await MainActor.run {
            PlaylistStore.shared.trackArtworkCache["\(title.lowercased())|\(artist.lowercased())"] ??
            PlaylistStore.shared.trackArtworkCache[title.lowercased()]
        }
        if let found = cacheKey, !found.isEmpty {
            cache[key] = found
            return found
        }
        
        // 2. Try extracting embedded artwork from local file if available
        if let path = localFilePath, FileManager.default.fileExists(atPath: path) {
            if let localArt = await extractLocalEmbeddedArtwork(path: path, key: key) {
                cache[key] = localArt
                return localArt
            }
        }
        
        // 3. Fetch high-res 1000x1000 official artwork via iTunes Search API
        if let itunesArt = await fetchItunesArtwork(title: title, artist: artist) {
            cache[key] = itunesArt
            return itunesArt
        }
        
        return nil
    }
    
    private func fetchItunesArtwork(title: String, artist: String) async -> String? {
        let cleaned = MetadataCleaner.clean(title: title, artist: artist)
        let searchTerm = "\(cleaned.cleanTitle) \(cleaned.primaryArtist)"
        
        guard var components = URLComponents(string: "https://itunes.apple.com/search") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "term", value: searchTerm),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1")
        ]
        
        guard let url = components.query != nil ? components.url : nil else { return nil }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 6
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first,
                  let rawArtwork = first["artworkUrl100"] as? String else { return nil }
            
            // Convert 100x100 to 1000x1000 ultra high-resolution
            let highRes = rawArtwork
                .replacingOccurrences(of: "100x100bb.jpg", with: "1000x1000bb.jpg")
                .replacingOccurrences(of: "100x100bb.png", with: "1000x1000bb.png")
            return highRes
        } catch {
            return nil
        }
    }
    
    private func extractLocalEmbeddedArtwork(path: String, key: String) async -> String? {
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        
        guard let metadata = try? await asset.load(.metadata) else { return nil }
        for item in metadata {
            if item.commonKey == .commonKeyArtwork,
               let data = try? await item.load(.dataValue) {
                let fileHash = abs(key.hashValue)
                let targetURL = cacheDirectory.appendingPathComponent("art_\(fileHash).jpg")
                if (try? data.write(to: targetURL)) != nil {
                    return targetURL.absoluteString
                }
            }
        }
        return nil
    }
}
