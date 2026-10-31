import Foundation
import Network
import Observation
import AppKit

/// Lets the iPhone app sync with this Mac over the home Wi-Fi.
/// The Mac announces itself (Bonjour), the iPhone connects, merges the two libraries and sends the result back.
/// Each request must carry the pairing code (see `SyncWire`).
@MainActor
@Observable
public final class SyncServer {
    public static let shared = SyncServer()
    
    public var isRunning = false
    public var status = "Starting…"
    public var lastSync: Date?
    public var lastDevice: String?
    public private(set) var code: String
    
    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private weak var store: PlaylistStore?
    
    private static let codeKey = "syncPairingCode"
    private static let lastSyncKey = "lastPhoneSync"
    
    private let appDir: URL
    private var lyricsURL: URL { appDir.appendingPathComponent("custom_lyrics.json") }
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appDir = appSupport.appendingPathComponent("AuraPlayer", isDirectory: true)
        if let saved = UserDefaults.standard.string(forKey: Self.codeKey), saved.count == 6 {
            code = saved
        } else {
            code = Self.makeCode()
            UserDefaults.standard.set(code, forKey: Self.codeKey)
        }
        let t = UserDefaults.standard.double(forKey: Self.lastSyncKey)
        if t > 0 { lastSync = Date(timeIntervalSince1970: t) }
    }
    
    private static func makeCode() -> String { String(format: "%06d", Int.random(in: 0...999_999)) }
    
    /// A new code: phones paired with the old one have to enter the new one
    public func renewCode() {
        code = Self.makeCode()
        UserDefaults.standard.set(code, forKey: Self.codeKey)
    }
    
    // MARK: - Listening
    
    public func start(store: PlaylistStore) {
        self.store = store
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(name: Host.current().localizedName ?? "Mac", type: SyncWire.serviceType)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.listenerChanged(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            status = "Couldn't start: \(error.localizedDescription)"
        }
    }
    
    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready: isRunning = true; status = "Ready: your iPhone can sync now"
        case .failed(let error):
            isRunning = false
            status = "Stopped: \(error.localizedDescription)"
            listener?.cancel()
            listener = nil
        case .cancelled: isRunning = false
        default: break
        }
    }
    
    private func accept(_ connection: NWConnection) {
        let channel = SyncChannel(connection)
        Task { await serve(channel) }
    }
    
    private func serve(_ channel: SyncChannel) async {
        do {
            try await channel.start()
            while true {
                let (header, body) = try await channel.receive()
                let (reply, replyBody) = handle(header, body)
                try await channel.send(reply, body: replyBody)
            }
        } catch {
            // the phone hung up (or sent rubbish): done
        }
        channel.close()
    }
    
    // MARK: - Requests
    
    private func reply(_ op: String, ok: Bool = true, error: String? = nil, revision: String? = nil) -> SyncWire.Header {
        SyncWire.Header(op: op, auth: "", revision: revision, ok: ok, error: error, device: Host.current().localizedName)
    }
    
    private func handle(_ header: SyncWire.Header, _ body: Data) -> (SyncWire.Header, Data) {
        guard SyncWire.isAuthorized(header, code: code) else {
            return (reply(header.op, ok: false, error: "Wrong pairing code"), Data())
        }
        guard let store else { return (reply(header.op, ok: false, error: "The Mac app isn't ready"), Data()) }
        
        switch header.op {
        case "hello":
            return (reply("hello", revision: libraryRevision(store)), Data())
            
        case "get":
            guard let data = try? JSONEncoder().encode(store.playlists) else {
                return (reply("get", ok: false, error: "Couldn't read the library"), Data())
            }
            return (reply("get", revision: SyncWire.revision(of: data)), data)
            
        case "put":
            // Refuse if the Mac changed since the iPhone read it: it will read again and merge again
            guard header.revision == libraryRevision(store) else {
                return (reply("put", ok: false, error: "changed"), Data())
            }
            guard let incoming = try? JSONDecoder().decode([Playlist].self, from: body), !incoming.isEmpty else {
                return (reply("put", ok: false, error: "Unreadable library"), Data())
            }
            backUpLibrary()
            store.adoptSyncedLibrary(incoming)
            markSynced(device: header.device)
            return (reply("put", revision: libraryRevision(store)), Data())
            
        case "getLyrics":
            let data = (try? Data(contentsOf: lyricsURL)) ?? Data("{}".utf8)
            return (reply("getLyrics", revision: SyncWire.revision(of: data)), data)
            
        case "putLyrics":
            guard (try? JSONSerialization.jsonObject(with: body)) is [String: Any] else {
                return (reply("putLyrics", ok: false, error: "Unreadable lyrics"), Data())
            }
            try? body.write(to: lyricsURL, options: .atomic)
            return (reply("putLyrics"), Data())
            
        default:
            return (reply(header.op, ok: false, error: "Unknown request"), Data())
        }
    }
    
    private func libraryRevision(_ store: PlaylistStore) -> String {
        SyncWire.revision(of: (try? JSONEncoder().encode(store.playlists)) ?? Data())
    }
    
    private func markSynced(device: String?) {
        lastSync = Date()
        lastDevice = device
        UserDefaults.standard.set(lastSync!.timeIntervalSince1970, forKey: Self.lastSyncKey)
    }
    
    /// The library as it was before a sync changed it (the 5 newest copies are kept)
    private func backUpLibrary() {
        let fm = FileManager.default
        let source = appDir.appendingPathComponent("playlists.json")
        guard fm.fileExists(atPath: source.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try? fm.copyItem(at: source, to: appDir.appendingPathComponent("playlists.backup-\(stamp).json"))
        let backups = ((try? fm.contentsOfDirectory(at: appDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("playlists.backup-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in backups.dropFirst(5) { try? fm.removeItem(at: old) }
    }
}
