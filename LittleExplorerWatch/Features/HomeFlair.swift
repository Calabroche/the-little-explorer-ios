import SwiftUI

/// Celebratory fireworks shown behind the watch home screen. Each burst
/// is a ring of coloured particles that fly outward, fall a little under
/// "gravity" and fade. New bursts spawn at random positions on a loop, so
/// opening the app always greets the rider with a little show.
struct FireworksView: View {
    private struct Burst: Identifiable {
        let id = UUID()
        let center: CGPoint        // unit coords (0…1) within the canvas
        let color: Color
        let startedAt: Date
        let particles: Int
    }

    @State private var bursts: [Burst] = []
    @State private var loop: Task<Void, Never>?

    private let palette: [Color] = [.orange, .pink, .yellow, .green, .cyan, .purple, .red]
    private let life: Double = 1.5   // seconds a burst stays visible

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date
                for burst in bursts {
                    let t = now.timeIntervalSince(burst.startedAt)
                    guard t >= 0, t <= life else { continue }
                    let p = t / life                       // 0 → 1
                    let eased = 1 - pow(1 - p, 3)            // ease-out spread
                    let radius = size.width * 0.45 * eased
                    let alpha = max(0, 1 - p)
                    let dot = 3.6 * (1 - p * 0.5)
                    let cx = burst.center.x * size.width
                    let cy = burst.center.y * size.height
                    for i in 0..<burst.particles {
                        let angle = (Double(i) / Double(burst.particles)) * 2 * .pi
                        let x = cx + cos(angle) * radius
                        // A touch of gravity so the sparks arc downward.
                        let y = cy + sin(angle) * radius + p * p * size.height * 0.18
                        let rect = CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot)
                        context.opacity = alpha
                        context.fill(Path(ellipseIn: rect), with: .color(burst.color))
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
        loop = Task { @MainActor in
            // An opening volley of three quick bursts, then a steady drip.
            for _ in 0..<3 {
                spawn()
                try? await Task.sleep(for: .milliseconds(220))
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Int.random(in: 550...950)))
                spawn()
            }
        }
    }

    @MainActor
    private func spawn() {
        bursts.append(Burst(
            center: CGPoint(x: .random(in: 0.18...0.82), y: .random(in: 0.16...0.5)),
            color: palette.randomElement() ?? .orange,
            startedAt: .now,
            particles: Int.random(in: 12...18),
        ))
        // Drop bursts that have finished so the array stays tiny.
        bursts.removeAll { $0.startedAt.timeIntervalSinceNow < -life }
    }
}

/// A cyclist who keeps pedalling — replaces the old static bicycle on the
/// home screen. The figure bobs forward with a repeating motion and a
/// gentle lean so it reads as "someone riding" rather than a frozen icon.
struct PedalingCyclist: View {
    @State private var riding = false

    var body: some View {
        Image(systemName: "figure.outdoor.cycle")
            .font(.system(size: 42, weight: .semibold))
            .foregroundStyle(.tint)
            .symbolEffect(.bounce, options: .repeating)
            .rotationEffect(.degrees(riding ? 4 : -4), anchor: .bottom)
            .offset(y: riding ? -2 : 2)
            .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true), value: riding)
            .onAppear { riding = true }
            .accessibilityLabel("Cycliste qui pédale")
    }
}
