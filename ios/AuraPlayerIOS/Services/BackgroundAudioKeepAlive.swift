import Foundation
import AVFoundation

public class BackgroundAudioKeepAlive {
    public static let shared = BackgroundAudioKeepAlive()
    private var audioPlayer: AVAudioPlayer?
    
    private init() {
        setupPlayer()
    }
    
    private func setupPlayer() {
        // 1-second silent WAV audio
        let sampleRate: UInt32 = 8000
        let numSamples = sampleRate
        let dataSize = numSamples * 2
        let fileSize = 36 + dataSize
        
        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVEfmt ".utf8)
        let subchunk1Size: UInt32 = 16
        data.append(contentsOf: withUnsafeBytes(of: subchunk1Size.littleEndian) { Array($0) })
        let audioFormat: UInt16 = 1 // PCM
        data.append(contentsOf: withUnsafeBytes(of: audioFormat.littleEndian) { Array($0) })
        let numChannels: UInt16 = 1
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        let byteRate = sampleRate * 2
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        let blockAlign: UInt16 = 2
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        let bitsPerSample: UInt16 = 16
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        data.append(Data(count: Int(dataSize)))
        
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.numberOfLoops = -1 // Loop indefinitely
            audioPlayer?.volume = 0.001 // Inaudible
            audioPlayer?.prepareToPlay()
        } catch {
            print("Failed to initialize background keep-alive audio: \(error)")
        }
    }
    
    public func start() {
        if audioPlayer?.isPlaying != true {
            audioPlayer?.play()
        }
    }
    
    public func stop() {
        audioPlayer?.pause()
    }
}
