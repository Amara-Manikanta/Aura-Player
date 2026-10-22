import Foundation
import os

/// Lightweight logging to both the unified log (Console.app, subsystem "com.auraplayer")
/// and a plain file at ~/Library/Logs/AuraPlayer/playback.log for easy bug reports.
public enum AppLog {
    private static let queue = DispatchQueue(label: "com.auraplayer.log")
    
    public static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/AuraPlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("playback.log")
        // Keep the file small: start fresh once it passes 2 MB
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 2_000_000 {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }()
    
    public static func log(_ category: String, _ message: String) {
        Logger(subsystem: "com.auraplayer", category: category).info("\(message, privacy: .public)")
        let line = "\(Date.now.formatted(.iso8601.time(includingFractionalSeconds: true))) [\(category)] \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: fileURL)
            }
        }
    }
}
