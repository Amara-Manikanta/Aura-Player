import Foundation
import Network
import UIKit

/// Syncs this iPhone's library with the Mac app over the home Wi-Fi.
/// Finds the Mac (Bonjour), reads its library, merges it with this one (`LibraryMerge`) and sends the result back,
/// so both end up the same. Needs the pairing code shown in the Mac app's Sync ▸ iPhone Sync window.
@MainActor
public final class MacSyncClient: ObservableObject {
    public static let shared = MacSyncClient()
    
    @Published public private(set) var isSyncing = false
    @Published public private(set) var lastResult: String?
    @Published public private(set) var lastSync: Date?
    @Published public private(set) var isPaired: Bool
    @Published public private(set) var macIP: String?
    
    private static let codeKey = "macSyncCode"
    private static let lastKey = "macLastSync"
    private static let ipKey = "macSyncIP"
    private var code: String? {
        didSet { isPaired = code != nil }
    }
    private var lastAttempt = Date.distantPast
    
    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.codeKey)
        code = saved
        isPaired = saved != nil
        macIP = UserDefaults.standard.string(forKey: Self.ipKey)
        let t = UserDefaults.standard.double(forKey: Self.lastKey)
        if t > 0 { lastSync = Date(timeIntervalSince1970: t) }
    }
    
    private enum SyncError: LocalizedError {
        case notFound, wrongCode, other(String)
        var errorDescription: String? {
            switch self {
            case .notFound: return "Couldn't find your Mac. Check that Aura Player is open on your Mac, both devices are on the same Wi-Fi, and Local Network permission is enabled."
            case .wrongCode: return "That code isn't right. Check the code in the Mac app (Sync ▸ iPhone Sync)."
            case .other(let m): return m
            }
        }
    }
    
    // MARK: - Public
    
    private static func parseEndpoint(from raw: String) -> NWEndpoint? {
        var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.lowercased().hasPrefix("http://") {
            clean = String(clean.dropFirst(7))
        } else if clean.lowercased().hasPrefix("https://") {
            clean = String(clean.dropFirst(8))
        }
        clean = clean.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !clean.isEmpty else { return nil }
        
        let parts = clean.split(separator: ":")
        let hostStr = String(parts[0]).trimmingCharacters(in: .whitespaces)
        guard !hostStr.isEmpty else { return nil }
        
        let portNum: UInt16
        if parts.count > 1, let p = UInt16(parts[1]) {
            portNum = p
        } else {
            portNum = SyncWire.defaultPort.rawValue
        }
        guard let port = NWEndpoint.Port(rawValue: portNum) else { return nil }
        return NWEndpoint.hostPort(host: NWEndpoint.Host(hostStr), port: port)
    }
    
    /// First time: remembers the code and optional IP, then syncs
    @discardableResult
    public func pair(code: String, ip: String? = nil) async -> String {
        let trimmed = code.filter(\.isNumber)
        guard trimmed.count == 6 else { return "The code is 6 digits." }
        if let ip = ip?.trimmingCharacters(in: .whitespacesAndNewlines), !ip.isEmpty {
            var clean = ip
            if clean.lowercased().hasPrefix("http://") { clean = String(clean.dropFirst(7)) }
            if clean.lowercased().hasPrefix("https://") { clean = String(clean.dropFirst(8)) }
            clean = clean.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            UserDefaults.standard.set(clean, forKey: Self.ipKey)
            self.macIP = clean
        }
        let previous = self.code
        self.code = trimmed
        let result = await syncNow()
        if lastResult == SyncError.wrongCode.errorDescription {
            self.code = previous
        } else {
            UserDefaults.standard.set(trimmed, forKey: Self.codeKey)
        }
        return result
    }
    
    public func forget() {
        code = nil
        macIP = nil
        UserDefaults.standard.removeObject(forKey: Self.codeKey)
        UserDefaults.standard.removeObject(forKey: Self.ipKey)
        lastResult = nil
    }
    
    /// When the app opens: quietly syncs if paired and the Mac is around (at most every 2 minutes)
    public func autoSync() async {
        guard isPaired, !isSyncing, Date().timeIntervalSince(lastAttempt) > 120 else { return }
        await syncNow(quiet: true)
    }
    
    @discardableResult
    public func syncNow(quiet: Bool = false) async -> String {
        guard let code, !isSyncing else { return lastResult ?? "" }
        isSyncing = true
        lastAttempt = Date()
        defer { isSyncing = false }
        
        let message: String
        do {
            let endpoints = await findMacs()
            guard !endpoints.isEmpty else { throw SyncError.notFound }
            var wrongCode = false
            var summary: String?
            var failure: Error?
            for endpoint in endpoints {
                do {
                    summary = try await sync(with: endpoint, code: code)
                    // If connection succeeded via hostPort, remember it
                    if case .hostPort(let host, _) = endpoint {
                        let h = "\(host)"
                        if h != "127.0.0.1" && h != "localhost" {
                            UserDefaults.standard.set(h, forKey: Self.ipKey)
                            self.macIP = h
                        }
                    }
                    break
                }
                catch SyncError.wrongCode { wrongCode = true }
                catch { failure = error }
            }
            if let summary { message = summary }
            else if wrongCode { throw SyncError.wrongCode }
            else { throw failure ?? SyncError.notFound }
        } catch {
            // Not finding the Mac at app start is normal (away from home): say nothing then
            if quiet, case SyncError.notFound = error { return lastResult ?? "" }
            lastResult = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return lastResult ?? ""
        }
        lastResult = message
        return message
    }
    
    // MARK: - Finding the Mac
    
    private func findMacs(timeout: TimeInterval = 3) async -> [NWEndpoint] {
        var endpoints: [NWEndpoint] = []
        
        // 1. Direct IP if specified or saved from previous sync
        if let savedIP = UserDefaults.standard.string(forKey: Self.ipKey),
           let ep = Self.parseEndpoint(from: savedIP) {
            endpoints.append(ep)
        }
        
        // 2. In iOS Simulator, probe loopback to reach host Mac directly
        #if targetEnvironment(simulator)
        endpoints.append(NWEndpoint.hostPort(host: "127.0.0.1", port: SyncWire.defaultPort))
        #endif
        
        // 3. Discover via Bonjour
        let bonjourEndpoints = await withCheckedContinuation { (cont: CheckedContinuation<[NWEndpoint], Never>) in
            final class State: @unchecked Sendable { var done = false; var found: [NWEndpoint] = [] }
            let state = State()
            let browser = NWBrowser(for: .bonjour(type: SyncWire.serviceType, domain: nil), using: .tcp)
            let queue = DispatchQueue(label: "aura.sync.browse")
            
            func finish() {
                guard !state.done else { return }
                state.done = true
                browser.cancel()
                cont.resume(returning: state.found)
            }
            browser.browseResultsChangedHandler = { results, _ in
                state.found = results.map(\.endpoint)
                if !results.isEmpty { queue.asyncAfter(deadline: .now() + 0.5) { finish() } }
            }
            browser.stateUpdateHandler = { newState in
                if case .failed = newState { finish() }
            }
            browser.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish() }
        }
        
        endpoints.append(contentsOf: bonjourEndpoints)
        return endpoints
    }
    
    // MARK: - One sync
    
    private func request(_ channel: SyncChannel, _ op: String, code: String, revision: String? = nil, body: Data = Data()) async throws -> (SyncWire.Header, Data) {
        var header = SyncWire.Header(op: op)
        header.auth = SyncWire.sign(code: code, op: op, time: header.time)
        header.revision = revision
        header.device = UIDevice.current.name
        try await channel.send(header, body: body)
        let (reply, data) = try await channel.receive()
        if reply.ok != true {
            if reply.error == "Wrong pairing code" { throw SyncError.wrongCode }
            throw SyncError.other(reply.error ?? "The Mac refused the request")
        }
        return (reply, data)
    }
    
    private func sync(with endpoint: NWEndpoint, code: String) async throws -> String {
        let channel = SyncChannel(NWConnection(to: endpoint, using: .tcp))
        defer { channel.close() }
        do { try await channel.start() } catch { throw SyncError.notFound }
        
        _ = try await request(channel, "hello", code: code)
        let store = PlaylistStore.shared
        
        for _ in 0..<3 {
            let (getHeader, remoteData) = try await request(channel, "get", code: code)
            let (_, remoteLyricsData) = try await request(channel, "getLyrics", code: code)
            
            guard let remote = try? JSONDecoder().decode([Playlist].self, from: remoteData), !remote.isEmpty else {
                throw SyncError.other("The Mac's library couldn't be read")
            }
            let remoteLyrics = (try? JSONDecoder().decode(LibraryMerge.Lyrics.self, from: remoteLyricsData)) ?? [:]
            
            let local = store.playlists
            let localLyrics = CustomLyricsStore.shared.all
            let base = SyncBase.load()
            
            // The merging is the slow part: off the main thread
            let (merged, mergedLyrics) = await Task.detached(priority: .userInitiated) {
                (LibraryMerge.merge(base: base.playlists, local: local, remote: remote),
                 LibraryMerge.mergeLyrics(base: base.lyrics, local: localLyrics, remote: remoteLyrics))
            }.value
            
            let nothingToDo = merged == remote && merged == local && mergedLyrics == remoteLyrics && mergedLyrics == localLyrics
            if !nothingToDo {
                // Keep a copy of what's here before it changes
                store.backUpLibrary()
                
                if merged != remote {
                    do {
                        let body = try JSONEncoder().encode(merged)
                        _ = try await request(channel, "put", code: code, revision: getHeader.revision, body: body)
                    } catch SyncError.other("changed") {
                        continue   // the Mac changed meanwhile: read it again and merge again
                    }
                }
                if mergedLyrics != remoteLyrics {
                    let body = try JSONEncoder().encode(mergedLyrics)
                    _ = try await request(channel, "putLyrics", code: code, body: body)
                }
            }
            
            // Both sides now hold `merged`: it's the new common ground
            await SyncBase.save(playlists: merged, lyrics: mergedLyrics)
            
            if store.playlists != local {
                continue   // changed on the phone while syncing: go round again (the base is up to date now)
            }
            if merged != local { store.adoptSynced(merged) }
            if mergedLyrics != localLyrics {
                CustomLyricsStore.shared.replaceAll(mergedLyrics)
                PlaybackManager.shared.reloadLyrics()
            }
            
            lastSync = Date()
            UserDefaults.standard.set(lastSync!.timeIntervalSince1970, forKey: Self.lastKey)
            if nothingToDo { return "Already in sync" }
            let added = merged.reduce(0) { $0 + $1.tracks.count } - local.reduce(0) { $0 + $1.tracks.count }
            return added > 0 ? "Synced (\(added) new songs from the Mac)" : "Synced"
        }
        throw SyncError.other("The library kept changing while syncing. Try again.")
    }
}

/// What both devices agreed on at the last sync (so the next one can tell additions from removals)
enum SyncBase {
    struct Saved: Codable {
        var playlists: [Playlist]
        var lyrics: [String: CustomLyricsStore.Entry]
    }
    
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sync_base.json")
    }
    
    /// Never synced before: the Mac library this app shipped with is the best guess of what both have in common
    static func load() -> Saved {
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Saved.self, from: data) { return saved }
        if let bundled = Bundle.main.url(forResource: "playlists", withExtension: "json", subdirectory: "Resources")
            ?? Bundle.main.url(forResource: "playlists", withExtension: "json"),
           let data = try? Data(contentsOf: bundled), let playlists = try? JSONDecoder().decode([Playlist].self, from: data) {
            return Saved(playlists: playlists, lyrics: [:])
        }
        return Saved(playlists: [], lyrics: [:])
    }
    
    static func save(playlists: [Playlist], lyrics: [String: CustomLyricsStore.Entry]) async {
        let url = url
        await Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(Saved(playlists: playlists, lyrics: lyrics)) { try? data.write(to: url, options: .atomic) }
        }.value
    }
}
