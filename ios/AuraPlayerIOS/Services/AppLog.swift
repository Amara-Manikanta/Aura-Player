import Foundation

/// Small log file (Files app > Aura Player > aura_log.txt) for working out why something stopped
enum AppLog {
    private static let queue = DispatchQueue(label: "aura.log", qos: .utility)
    private static let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("aura_log.txt")
    private static let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()
    
    static func log(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async {
            if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 400_000 {
                try? FileManager.default.removeItem(at: url)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
