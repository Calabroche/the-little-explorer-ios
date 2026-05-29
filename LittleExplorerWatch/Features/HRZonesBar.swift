import SwiftUI

/// Five-zone heart-rate bar — Apple Activity / Workout style.
///
/// Layout:
///   • 5 cells in a row, all visible at full color (cool blue → warm
///     red as intensity climbs).
///   • Inactive cells are square-ish colored chips (~28×26 pt).
///   • The active cell expands into a wider rounded pill with a
///     heart glyph + "ZONE N" text. Same row height, larger width.
///   • A small white triangle pointing UP sits directly below the
///     active cell — same affordance Apple uses in the Workout app.
///
/// Text color in the active pill is luminance-aware so it stays
/// readable against any zone's background (black on bright Z3 green
/// and Z4 amber; white on the darker Z1 / Z2 / Z5).
///
/// Zone boundaries: percentages of `hrMax`:
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
        Color(red: 0.66, green: 0.92, blue: 0.18),    // Z3 bright lime
        Color(red: 0.95, green: 0.59, blue: 0.15),    // Z4 amber
        Color(red: 0.84, green: 0.20, blue: 0.20),    // Z5 red
    ]

    /// Z3 (lime) and Z4 (amber) are bright enough that black text
    /// reads better than white. Z1 / Z2 / Z5 are darker → white text.
    private func textColor(forZone index: Int) -> Color {
        (index == 2 || index == 3) ? .black : .white
    }

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    cell(for: i)
                }
            }
            // Triangle row — same HStack layout so the indicator
            // lands directly under the active cell's column. Empty
            // placeholders maintain horizontal alignment on the
            // other columns. Widths match the cell row's geometry
            // (active flex, inactive 18 pt).
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    if i == currentZone {
                        Triangle()
                            .fill(.white)
                            .frame(width: 8, height: 5)
                            .frame(minWidth: 95, maxWidth: .infinity)
                            .layoutPriority(10)
                    } else {
                        Color.clear
                            .frame(width: 18, height: 5)
                            .layoutPriority(1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(for index: Int) -> some View {
        let active = (index == currentZone)
        if active {
            // Active pill — takes ~55 % of the bar's width so the
            // "ZONE N" text always fits without truncation. Bigger
            // and more dramatic than the inactive cells:
            //   • height 32 pt vs 24 pt
            //   • font 13 pt heavy + heart glyph
            //   • generous horizontal pad so the text breathes
            //   • rounded pill shape (cornerRadius 16 pt)
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 13, weight: .bold))
                Text("ZONE \(index + 1)")
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(0.3)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(textColor(forZone: index))
            .padding(.horizontal, 10)
            .frame(minWidth: 95, maxWidth: .infinity)
            .frame(height: 32)
            .background(colors[index], in: RoundedRectangle(cornerRadius: 16))
            .layoutPriority(10)
        } else {
            // Inactive cells: smaller squares so the active pill has
            // room to display its full "ZONE N" text. Compact but
            // still visually present at the 18 × 24 pt baseline.
            RoundedRectangle(cornerRadius: 5)
                .fill(colors[index])
                .frame(width: 18, height: 24)
                .layoutPriority(1)
        }
    }
}

/// Equilateral-ish triangle pointing UP (apex at top). Used as the
/// "current zone" indicator below the HR bar.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to:    CGPoint(x: rect.midX, y: rect.minY))   // apex up
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))   // base bottom-left
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))   // base bottom-right
        p.closeSubpath()
        return p
    }
}
