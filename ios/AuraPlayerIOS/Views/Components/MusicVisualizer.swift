import SwiftUI

public struct MusicVisualizer: View {
    public let isPlaying: Bool
    
    public init(isPlaying: Bool) {
        self.isPlaying = isPlaying
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { context in
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
        guard isPlaying else { return .zero }
        
        let beat = Float(pow(max(0, sin(t * .pi * 2)), 6))
        let wobble = Float(0.5 + 0.5 * sin(t * 3.1))
        return .init(
            bass: 0.25 + 0.55 * beat,
            mid: 0.3 + 0.3 * wobble,
            treble: 0.2 + 0.25 * Float(0.5 + 0.5 * sin(t * 7.3)),
            overall: 0.35 + 0.4 * beat
        )
    }

    private func drawLights(gc: inout GraphicsContext, size: CGSize, t: Double, levels: AudioLevelMeter.Levels) {
        let lights: [(Color, Float, Double, Double)] = [
            (AuraTheme.primary, levels.bass, 0.17, 0.0),
            (Color.purple, levels.mid, 0.11, 2.1),
            (Color(red: 0.2, green: 0.7, blue: 1.0), levels.treble, 0.23, 4.2)
        ]
        let base = min(size.width, size.height)
        for (color, level, speed, phase) in lights {
            let x = size.width * (0.5 + 0.32 * cos(t * speed + phase))
            let y = size.height * (0.45 + 0.28 * sin(t * speed * 1.3 + phase))
            let radius = base * (0.28 + 0.32 * CGFloat(level))
            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            let gradient = Gradient(colors: [color.opacity(0.18 + 0.45 * Double(level)), color.opacity(0)])
            gc.fill(Path(ellipseIn: rect), with: .radialGradient(gradient, center: CGPoint(x: x, y: y), startRadius: 0, endRadius: radius))
        }
        
        if levels.bass > 0.6 {
            let flash = Double(levels.bass - 0.6) * 0.35
            gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(flash * 0.20)))
        }
    }

    private func drawSpectrum(gc: inout GraphicsContext, size: CGSize, t: Double, levels: AudioLevelMeter.Levels) {
        let count = 36
        let gap: CGFloat = 3
        let barWidth = (size.width - gap * CGFloat(count + 1)) / CGFloat(count)
        guard barWidth > 1 else { return }
        
        let maxHeight = size.height * 0.15
        for i in 0..<count {
            let fraction = Float(i) / Float(count - 1)
            let bandLevel: Float
            if fraction < 0.33 {
                bandLevel = levels.bass
            } else if fraction < 0.66 {
                bandLevel = levels.mid
            } else {
                bandLevel = levels.treble
            }
            
            let ripple = Float(0.5 + 0.5 * sin(t * 4.0 + Double(i) * 0.35))
            let h = CGFloat(max(0.04, min(1.0, bandLevel * (0.6 + 0.4 * ripple)))) * maxHeight
            let x = gap + CGFloat(i) * (barWidth + gap)
            let y = size.height - h - 10
            
            let rect = CGRect(x: x, y: y, width: barWidth, height: h)
            let color = AuraTheme.primary.opacity(0.35 + 0.5 * Double(bandLevel))
            gc.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(color))
        }
    }
}
