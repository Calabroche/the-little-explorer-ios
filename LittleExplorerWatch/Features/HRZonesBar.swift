import SwiftUI

/// Five-zone heart-rate bar, modelled on the Apple Workout / Activity
/// app's "Zone X" pill. The active zone gets a wide rounded pill with
/// a heart glyph + "ZONE N" label inside; inactive zones flank it as
/// smaller colored cells. The whole bar fits ~28 pt of vertical space
/// — big enough to read at a glance, small enough not to crowd the
/// metric grid above it.
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
                cell(for: i)
            }
        }
    }

    @ViewBuilder
    private func cell(for index: Int) -> some View {
        let active = (index == currentZone)
        if active {
            // Active pill: takes ~2.4× the horizontal space of an
            // inactive cell. Heart icon + "ZONE N" text on a colored
            // background, mirroring the Apple Workout layout.
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(colors[index])
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("ZONE \(index + 1)")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(0.5)
                }
                .foregroundStyle(.white)
            }
            .frame(height: 24)
            .frame(maxWidth: .infinity)
            .layoutPriority(2)
        } else {
            // Inactive cells: solid color but dimmer, shorter
            // (~10 pt vs 24 pt) so the active pill pops above the row.
            RoundedRectangle(cornerRadius: 4)
                .fill(colors[index].opacity(0.55))
                .frame(height: 10)
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
        }
    }
}
