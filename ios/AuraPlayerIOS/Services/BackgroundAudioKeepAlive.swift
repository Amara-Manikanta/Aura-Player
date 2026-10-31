import Foundation
import AVFoundation

public class BackgroundAudioKeepAlive {
    public static let shared = BackgroundAudioKeepAlive()
    private var audioPlayer: AVAudioPlayer?
    private var isStarted: Bool = false
    
    private init() {
        setupPlayer()
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }
    
    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        if type == .ended {
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) && isStarted {
                    start()
                }
            }
        }
    }
    
    private func setupPlayer() {
        // Generate 1 second of 44.1kHz 16-bit mono digital silence PCM
        let sampleRate: UInt32 = 44100
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
            audioPlayer?.volume = 0.0001 // Inaudible
            audioPlayer?.prepareToPlay()
        } catch {
            print("Failed to initialize background keep-alive audio: \(error)")
        }
    }
    
    /// Audio session changes can block for a while (iOS warns about doing them on the main thread:
    /// buttons stopped responding), so they run here, one at a time
    private static let sessionQueue = DispatchQueue(label: "aura.audio-session", qos: .userInitiated)
    
    private static var sessionActivated = false
    
    /// Once is enough: activating again while the web player is playing interrupts its audio
    public static func activateSession() {
        sessionQueue.async {
            guard !sessionActivated else { return }
            sessionActivated = true
            do {
                // Only the category: the web player's own audio session activates itself. Activating a
                // second session from the app was interrupting it (see aura_log.txt)
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .moviePlayback)
                try session.setActive(true)
                AppLog.log("audio session active (playback)")
            } catch {
                print("Failed to set audio category: \(error)")
            }
        }
    }
    
    /// The silent loop is off: the log showed iOS pausing the video about half a second after it
    /// started (the second audio source interrupted the web player's audio session).
    public func start() {
        isStarted = true
        AppLog.log("keep-alive start skipped")
    }
    
    public func stop() {
        isStarted = false
        audioPlayer?.pause()
    }
}
