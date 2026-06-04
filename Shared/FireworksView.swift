import SwiftUI

/// Reusable fireworks show, shared by the watch home screen and the iOS
/// launch splash. Each burst is a spray of coloured sparks that fly out,
/// arc down under a little gravity and fade.
///
/// - `intensity`: scales spark count, size and spawn frequency (1.0 = base,
///   1.5 = half again as dense / busy).
/// - `duration`: how long to keep spawning new bursts, in seconds. After it
///   elapses the last bursts finish fading and the show stops. `nil` loops
///   forever.
struct FireworksView: View {
    var intensity: Double = 1.0
    var duration: Double? = nil

    private struct Spark { let angle: Double; let speed: Double; let size: Double; let color: Color }
    private struct Burst: Identifiable {
        let id = UUID()
        let center: CGPoint        // unit coords (0…1)
        let startedAt: Date
        let sparks: [Spark]
    }

    @State private var bursts: [Burst] = []
    @State private var loop: Task<Void, Never>?

    private let palette: [Color] = [.orange, .pink, .yellow, .green, .cyan, .purple, .red, .mint]
    private let life: Double = 1.6   // seconds a burst stays visible

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date
                let spread = size.width * 0.55
                for burst in bursts {
                    let t = now.timeIntervalSince(burst.startedAt)
                    guard t >= 0, t <= life else { continue }
                    let p = t / life                       // 0 → 1
                    let eased = 1 - pow(1 - p, 3)            // ease-out spread
                    let alpha = max(0, 1 - p)
                    let cx = burst.center.x * size.width
                    let cy = burst.center.y * size.height
                    for s in burst.sparks {
                        let dist = spread * s.speed * eased
                        let x = cx + cos(s.angle) * dist
                        // Gravity pulls the sparks down as they age.
                        let y = cy + sin(s.angle) * dist + p * p * size.height * 0.22
                        let d = s.size * (1 - p * 0.5)
                        let rect = CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)
                        context.opacity = alpha
                        context.fill(Path(ellipseIn: rect), with: .color(s.color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { start() }
        .onDisappear { loop?.cancel() }
    }

    private func start() {
        loop?.cancel()
        bursts.removeAll()
        let started = Date()
        // More frequent bursts at higher intensity.
        let baseDelay = 520.0 / max(0.1, intensity)
        loop = Task { @MainActor in
            // Opening volley — a few near-simultaneous bursts.
            let volley = Int((3.0 * intensity).rounded())
            for _ in 0..<max(2, volley) {
                spawn()
                try? await Task.sleep(for: .milliseconds(160))
            }
            while !Task.isCancelled {
                if let duration, Date().timeIntervalSince(started) >= duration { break }
                let jitter = Double.random(in: 0.7...1.3)
                try? await Task.sleep(for: .milliseconds(Int(baseDelay * jitter)))
                if let duration, Date().timeIntervalSince(started) >= duration { break }
                spawn()
            }
        }
    }

    @MainActor
    private func spawn() {
        let count = Int((Double.random(in: 14...20) * intensity).rounded())
        let baseColor = palette.randomElement() ?? .orange
        let sparks: [Spark] = (0..<count).map { i in
            // Even ring + a little jitter so it doesn't look mechanical.
            let angle = (Double(i) / Double(count)) * 2 * .pi + Double.random(in: -0.12...0.12)
            return Spark(
                angle: angle,
                speed: Double.random(in: 0.65...1.0),
                size: Double.random(in: 3.0...5.0) * (0.85 + intensity * 0.2),
                // Mostly one colour per burst, with the odd contrasting spark.
                color: Double.random(in: 0...1) < 0.18 ? (palette.randomElement() ?? baseColor) : baseColor,
            )
        }
        bursts.append(Burst(
            center: CGPoint(x: .random(in: 0.15...0.85), y: .random(in: 0.14...0.5)),
            startedAt: .now,
            sparks: sparks,
        ))
        bursts.removeAll { $0.startedAt.timeIntervalSinceNow < -life }
    }
}
