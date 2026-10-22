import Foundation
import AVFoundation
import MediaToolbox

/// Live bass / mid / treble levels of the audio player's output, for the visualizer.
/// Reads the samples through an audio tap; the sound itself is not changed.
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
    private var raw = Levels.zero          // latest measurement from the audio thread
    private var smoothed = Levels.zero     // what the visualizer shows
    private var lastSample = Date.distantPast
    private var lastRead = Date()
    // one-pole filter state (audio thread only)
    private var lowState: Float = 0
    private var midState: Float = 0

    private init() {}

    /// True while real audio data is arriving (audio mode); false in video mode / paused.
    public var isLive: Bool {
        lock.lock(); defer { lock.unlock() }
        return Date().timeIntervalSince(lastSample) < 0.4
    }

    /// Smoothed levels (0…1): fast rise, slower fall, like a VU meter.
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
        smoothed = Levels(
            bass: follow(smoothed.bass, target.bass),
            mid: follow(smoothed.mid, target.mid),
            treble: follow(smoothed.treble, target.treble),
            overall: follow(smoothed.overall, target.overall)
        )
        return smoothed
    }

    // MARK: - Tap

    /// Attaches the measuring tap to an audio player item.
    @MainActor
    public func attach(to item: AVPlayerItem) async {
        guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first else { return }
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: nil,
            init: { _, _, storageOut in storageOut.pointee = nil },
            finalize: { _ in },
            prepare: nil,
            unprepare: nil,
            process: { tap, numberFrames, _, bufferList, framesOut, flagsOut in
                guard MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferList, flagsOut, nil, framesOut) == noErr else { return }
                AudioLevelMeter.shared.measure(bufferList, frames: Int(framesOut.pointee))
            }
        )
        var tap: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap) == noErr,
              let tap else { return }
        let params = AVMutableAudioMixInputParameters(track: track)
        params.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        item.audioMix = mix
    }

    /// Called on the audio thread with float samples.
    fileprivate func measure(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard frames > 0 else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard let first = buffers.first, let data = first.mData else { return }
        let samples = data.assumingMemoryBound(to: Float.self)
        let count = min(frames, Int(first.mDataByteSize) / MemoryLayout<Float>.size)
        guard count > 0 else { return }

        // Split into bands with two one-pole filters (~150 Hz and ~2.5 kHz at 44.1 kHz)
        var low = lowState, midLP = midState
        var bassSum: Float = 0, midSum: Float = 0, trebleSum: Float = 0, allSum: Float = 0
        for i in 0..<count {
            let x = samples[i]
            low += 0.021 * (x - low)
            midLP += 0.30 * (x - midLP)
            let bassPart = low, midPart = midLP - low, treblePart = x - midLP
            bassSum += bassPart * bassPart
            midSum += midPart * midPart
            trebleSum += treblePart * treblePart
            allSum += x * x
        }
        lowState = low; midState = midLP

        let n = Float(count)
        // RMS → 0…1 with gains that make typical music land mid-range
        func scale(_ sum: Float, _ gain: Float) -> Float { min(1, sqrt(sum / n) * gain) }
        let levels = Levels(bass: scale(bassSum, 3.2), mid: scale(midSum, 4.5), treble: scale(trebleSum, 22), overall: scale(allSum, 3))
        lock.lock()
        raw = levels
        lastSample = Date()
        lock.unlock()
    }
}
