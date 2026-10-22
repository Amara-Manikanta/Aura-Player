import SwiftUI

/// Glowing lights and a spectrum that move with the music, drawn behind Now Playing.
/// In Music mode it follows the real sound (bass, mids, treble); in video mode, where the sound comes
/// from the YouTube player and can't be measured, it pulses to a steady beat while playing.
public struct MusicVisualizer: View {
    let isPlaying: Bool

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let levels = currentLevels(time: t)
            Canvas { gc, size in
                drawLights(gc: &gc, size: size, t: t, levels: levels)
                drawSpectrum(gc: &gc, size: size, t: t, levels: levels)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private func currentLevels(time t: Double) -> AudioLevelMeter.Levels {
        let meter = AudioLevelMeter.shared
        let measured = meter.levels()
        if meter.isLive { return measured }
        guard isPlaying else { return measured } // decays to calm when paused
        // Synthetic beat (~120 BPM) for video mode
        let beat = Float(pow(max(0, sin(t * .pi * 2)), 6))
        let wobble = Float(0.5 + 0.5 * sin(t * 3.1))
        return .init(bass: 0.25 + 0.55 * beat, mid: 0.3 + 0.3 * wobble, treble: 0.2 + 0.25 * Float(0.5 + 0.5 * sin(t * 7.3)), overall: 0.35 + 0.4 * beat)
    }

    /// Three big soft lights that drift around and swell with bass / mids / treble.
    private func drawLights(gc: inout GraphicsContext, size: CGSize, t: Double, levels: AudioLevelMeter.Levels) {
        let lights: [(Color, Float, Double, Double)] = [
            (.purple, levels.bass, 0.17, 0.0),
            (.pink, levels.mid, 0.11, 2.1),
            (Color(red: 0.2, green: 0.7, blue: 1.0), levels.treble, 0.23, 4.2)
        ]
        let base = min(size.width, size.height)
        for (color, level, speed, phase) in lights {
            let x = size.width * (0.5 + 0.32 * cos(t * speed + phase))
            let y = size.height * (0.45 + 0.28 * sin(t * speed * 1.3 + phase))
            let radius = base * (0.28 + 0.32 * CGFloat(level))
            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            let gradient = Gradient(colors: [color.opacity(0.18 + 0.5 * Double(level)), color.opacity(0)])
            gc.fill(Path(ellipseIn: rect), with: .radialGradient(gradient, center: CGPoint(x: x, y: y), startRadius: 0, endRadius: radius))
        }
        // Brief flash of light on strong bass hits
        if levels.bass > 0.6 {
            let flash = Double(levels.bass - 0.6) * 0.35
            gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(flash * 0.25)))
        }
    }

    /// Spectrum bars along the bottom: low bars follow bass, middle bars mids, right bars treble.
    private func drawSpectrum(gc: inout GraphicsContext, size: CGSize, t: Double, levels: AudioLevelMeter.Levels) {
        let count = 48
        let gap: CGFloat = 3
        let barWidth = (size.width - gap * CGFloat(count + 1)) / CGFloat(count)
        let maxHeight = size.height * 0.22
        for i in 0..<count {
            let position = Float(i) / Float(count - 1)               // 0 = bass end, 1 = treble end
            let bandLevel = position < 0.33
                ? levels.bass + (levels.mid - levels.bass) * (position / 0.33)
                : position < 0.66
                    ? levels.mid + (levels.treble - levels.mid) * ((position - 0.33) / 0.33)
                    : levels.treble * (1 - (position - 0.66) * 0.6)
            // per-bar shimmer so neighbouring bars don't move in lockstep
            let shimmer = Float(0.75 + 0.25 * sin(t * (4 + Double(i % 7)) + Double(i) * 1.7))
            let height = max(2, maxHeight * CGFloat(bandLevel * shimmer))
            let x = gap + CGFloat(i) * (barWidth + gap)
            let rect = CGRect(x: x, y: size.height - height - 8, width: barWidth, height: height)
            let hue = 0.78 - Double(position) * 0.25                 // purple → pink → blue
            gc.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .linearGradient(Gradient(colors: [Color(hue: hue, saturation: 0.8, brightness: 1).opacity(0.9),
                                                            Color(hue: hue, saturation: 0.8, brightness: 1).opacity(0.25)]),
                                          startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                          endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        }
    }
}
