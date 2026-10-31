import Foundation

/// Combines the iPhone's library with the Mac's. Both are compared with `base`: what both devices had
/// the last time they synced. That tells "removed on one side" apart from "added on the other":
///  - added on either side: kept
///  - removed on one side: removed (unless the other side changed it meanwhile)
///  - play counts: both sides' new plays are added together
///  - anything else changed on one side: that change wins; changed on both: the iPhone's wins
enum LibraryMerge {
    
    // MARK: - Playlists
    
    static func merge(base: [Playlist], local: [Playlist], remote: [Playlist]) -> [Playlist] {
        let baseById = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let localById = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let remoteById = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        
        var order = local.map(\.id)
        let known = Set(order)
        order += remote.map(\.id).filter { !known.contains($0) }
        
        var result: [Playlist] = []
        var seen = Set<UUID>()
        for id in order where seen.insert(id).inserted {
            let b = baseById[id]
            switch (localById[id], remoteById[id]) {
            case let (l?, r?):
                result.append(mergePlaylist(b, l, r))
            case let (l?, nil):
                // gone on the Mac: drop it, unless it was changed here since
                if let b, unchanged(b, l) { continue }
                result.append(l)
            case let (nil, r?):
                if let b, unchanged(b, r) { continue }
                result.append(r)
            default: break
            }
        }
        return result
    }
    
    private static func unchanged(_ a: Playlist, _ b: Playlist) -> Bool {
        a.name == b.name && a.tracks.map(\.id) == b.tracks.map(\.id)
    }
    
    private static func mergePlaylist(_ b: Playlist?, _ l: Playlist, _ r: Playlist) -> Playlist {
        var merged = l
        if let b {
            merged.name = l.name != b.name ? l.name : r.name
            merged.iconName = l.iconName != b.iconName ? l.iconName : r.iconName
        }
        
        let baseIds = Set(b?.tracks.map(\.id) ?? [])
        let hasBase = b != nil
        let localById = Dictionary(l.tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let remoteById = Dictionary(r.tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let baseTracks = Dictionary((b?.tracks ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        
        // Keep: on both sides, or added on one side (not in base). Dropped: it was in base and one side removed it.
        func keep(_ id: UUID) -> Bool {
            let inL = localById[id] != nil, inR = remoteById[id] != nil
            if inL && inR { return true }
            if !hasBase { return true }
            return !baseIds.contains(id)
        }
        
        var tracks: [MediaTrack] = []
        var seen = Set<UUID>()
        for t in l.tracks where keep(t.id) && seen.insert(t.id).inserted {
            if let rt = remoteById[t.id] { tracks.append(mergeTrack(baseTracks[t.id], t, rt)) } else { tracks.append(t) }
        }
        for t in r.tracks where keep(t.id) && seen.insert(t.id).inserted {
            tracks.append(t)
        }
        merged.tracks = tracks
        return merged
    }
    
    // MARK: - One song
    
    private static func mergeTrack(_ b: MediaTrack?, _ l: MediaTrack, _ r: MediaTrack) -> MediaTrack {
        if l == r { return l }
        if let b {
            if l == b { return r }
            if r == b { return l }
        }
        
        guard let ld = dictionary(l), let rd = dictionary(r) else { return l }
        let bd = b.flatMap(dictionary)
        var out = ld
        
        for key in Set(ld.keys).union(rd.keys) {
            let lv = ld[key], rv = rd[key], bv = bd?[key]
            switch key {
            case "playCount":
                // each side's plays since the last sync, added together (no base: the larger, so nothing is counted twice)
                if bd != nil {
                    out[key] = max(0, Int(number(lv) + number(rv) - number(bv)))
                } else {
                    out[key] = Int(max(number(lv), number(rv)))
                }
            case "applePlayCount":
                if lv != nil || rv != nil { out[key] = Int(max(number(lv), number(rv))) }
            case "lastPlayedDate":
                if lv != nil || rv != nil { out[key] = max(number(lv), number(rv)) }
            case "rejectedVideoIds":
                let ids = ((lv as? [String]) ?? []) + ((rv as? [String]) ?? [])
                var seen = Set<String>()
                out[key] = ids.filter { seen.insert($0).inserted }
            default:
                if bd != nil {
                    // not changed on the iPhone since the last sync: take the Mac's version (including "removed")
                    if same(lv, bv) {
                        if let rv { out[key] = rv } else { out.removeValue(forKey: key) }
                    }
                    // changed on the iPhone (or on both): keep the iPhone's value
                } else if lv == nil, let rv {
                    out[key] = rv
                }
            }
        }
        
        guard let data = try? JSONSerialization.data(withJSONObject: out),
              let track = try? JSONDecoder().decode(MediaTrack.self, from: data) else { return l }
        return track
    }
    
    private static func dictionary(_ track: MediaTrack) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(track) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    
    private static func number(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }
    
    private static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return (a as AnyObject).isEqual(b as AnyObject)
        default: return false
        }
    }
    
    // MARK: - Custom lyrics
    
    typealias Lyrics = [String: CustomLyricsStore.Entry]
    
    static func mergeLyrics(base: Lyrics, local: Lyrics, remote: Lyrics) -> Lyrics {
        var result: Lyrics = [:]
        for key in Set(local.keys).union(remote.keys) {
            let l = local[key], r = remote[key], b = base[key]
            switch (l, r) {
            case let (l?, r?):
                if l.sameContent(r) { result[key] = l }
                else if let b, l.sameContent(b) { result[key] = r }
                else if let b, r.sameContent(b) { result[key] = l }
                else { result[key] = (l.modified ?? 0) >= (r.modified ?? 0) ? l : r }
            case let (l?, nil):
                if let b, b.sameContent(l) { continue }   // removed on the Mac
                result[key] = l
            case let (nil, r?):
                if let b, b.sameContent(r) { continue }   // removed here
                result[key] = r
            default: break
            }
        }
        return result
    }
}
