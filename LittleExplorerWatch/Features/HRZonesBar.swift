import SwiftUI

/// Five-zone heart-rate bar à la Apple Workout. Colors match the
/// system app's palette (blue → red as intensity climbs). The current
/// zone is highlighted with a brighter fill + white tick on top, so
/// the rider can read effort at a glance without parsing the bpm
/// number itself.
///
/// Zone boundaries are computed as percentages of `hrMax`:
///   Z1: 50-60 %  recovery
///   Z2: 60-70 %  endurance
///   Z3: 70-80 %  tempo
///   Z4: 80-90 %  threshold
///   Z5: 90-100 % VO2max
///
/// `hrMax` defaults to 195 — a sensible value for a fit cyclist in
/// their 30s. Later we can pipe the user's setting from iOS via
/// WCSession if they want it precise, but for v1 a constant keeps
/// the Watch self-contained.
struct HRZonesBar: View {
    let bpm: Int?
    var hrMax: Int = 195

    /// Resolved zone index 0..4 from the current HR, or nil when no
    /// HR is being captured yet.
    private var currentZone: Int? {
        guard let bpm, bpm > 0 else { return nil }
        let pct = Double(bpm) / Double(hrMax)
        switch pct {
        case ..<0.6:  return 0
        case ..<0.7:  return 1
        case ..<0.8:  return 2
        case ..<0.9:  return 3
        default:      return 4
        }
    }

    /// Apple-like palette — cool → warm as the zone climbs.
    private let colors: [Color] = [
        Color(red: 0.13, green: 0.42, blue: 0.66),    // Z1 deep blue
        Color(red: 0.16, green: 0.66, blue: 0.66),    // Z2 teal
        Color(red: 0.46, green: 0.78, blue: 0.21),    // Z3 green
        Color(red: 0.95, green: 0.59, blue: 0.15),    // Z4 amber
        Color(red: 0.84, green: 0.20, blue: 0.20),    // Z5 red
    ]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                let active = (i == currentZone)
                RoundedRectangle(cornerRadius: 2)
                    .fill(colors[i].opacity(active ? 1.0 : 0.30))
                    .frame(height: active ? 8 : 5)
                    .overlay(alignment: .top) {
                        if active {
                            // Subtle white triangle "tick" anchored at
                            // the cell — same affordance Apple uses to
                            // mark the current zone in the Workout app.
                            Triangle()
                                .fill(.white)
                                .frame(width: 6, height: 4)
                                .offset(y: -5)
                        }
                    }
            }
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to:    CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
