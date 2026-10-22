import Foundation
import AVFoundation

/// Live bass / mid / treble levels of the audio output for the ambient visualizer.
public final class AudioLevelMeter: @unchecked Sendable {
    public static let shared = AudioLevelMeter()

    public struct Levels: Sendable {
        public var bass: Float
        public var mid: Float
        public var treble: Float
        public var overall: Float
        public static let zero = Levels(bass: 0, mid: 0, treble: 0, overall: 0)
    }

    private let lock = NSLock()
    private var raw = Levels.zero
    private var smoothed = Levels.zero
    private var lastSample = Date.distantPast
    private var lastRead = Date()

    private init() {}

    public var isLive: Bool {
        lock.lock(); defer { lock.unlock() }
        return Date().timeIntervalSince(lastSample) < 0.4
    }

    public func levels() -> Levels {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        let dt = Float(min(now.timeIntervalSince(lastRead), 0.2))
        lastRead = now
        let live = now.timeIntervalSince(lastSample) < 0.4
        let target = live ? raw : .zero
        
        func follow(_ current: Float, _ goal: Float) -> Float {
            let rate: Float = goal > current ? 18 : 5
            return current + (goal - current) * min(1, rate * dt)
        }
        
        smoothed.bass = follow(smoothed.bass, target.bass)
        smoothed.mid = follow(smoothed.mid, target.mid)
        smoothed.treble = follow(smoothed.treble, target.treble)
        smoothed.overall = follow(smoothed.overall, target.overall)
        return smoothed
    }
}
