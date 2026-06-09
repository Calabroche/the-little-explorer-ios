import SwiftUI

/// 17-week (≈ 4 months) TSS heatmap. Each cell is one day; intensity
/// scales with the total TSS recorded that day. Tap a cell to surface
/// its summary line.
struct ActivityCalendarView: View {
    let activities: [RideRecord]

    @State private var hoverIndex: Int?

    private static let weeksShown = 17
    private static let cellSize: CGFloat = 14
    private static let cellGap: CGFloat = 3

    private struct DayCell: Identifiable, Hashable {
        let id: Int
        let date: Date
        let isoDay: String
        let activities: [RideRecord]
        let totalKm: Double
        let totalElevationM: Double
        let totalDurationMin: Int
        let inFuture: Bool

        /// Weighted by total time: km/h = totalKm / totalHours.
        /// Returns nil when no usable duration is available.
        var avgSpeedKmh: Double? {
            guard totalDurationMin > 0, totalKm > 0 else { return nil }
            return totalKm / (Double(totalDurationMin) / 60)
        }

        /// Max over the day's activities (already km/h).
        var maxSpeedKmh: Double? { activities.compactMap(\.maxSpeed).max() }
        /// Steepest incline over the day's activities (already %).
        var maxInclinePct: Double? { activities.compactMap(\.maxIncline).max() }
        /// Duration-weighted average heart rate (bpm) over activities that have it.
        var avgHrBpm: Int? {
            let withHr = activities.filter { $0.avgHr != nil }
            guard !withHr.isEmpty else { return nil }
            let totalMin = withHr.map(\.durationMin).reduce(0, +)
            if totalMin > 0 {
                let weighted = withHr.reduce(0.0) { $0 + ($1.avgHr ?? 0) * Double($1.durationMin) }
                return Int((weighted / Double(totalMin)).rounded())
            }
            return Int((withHr.compactMap(\.avgHr).reduce(0, +) / Double(withHr.count)).rounded())
        }
    }

    var body: some View {
        let cells = buildGrid()
        // Split into weeks first…
        let allWeeks: [[DayCell]] = (0..<Self.weeksShown).map { w in
            Array(cells[(w * 7)..<((w + 1) * 7)])
        }
        // …then drop every leading empty week so months with no
        // activity at all (e.g. January, February for Florian's data)
        // don't waste space at the start of the heatmap.
        let firstActiveIdx = allWeeks.firstIndex(where: { week in
            week.contains(where: { !$0.activities.isEmpty })
        }) ?? 0
        let cols: [[DayCell]] = Array(allWeeks[firstActiveIdx...])

        VStack(alignment: .leading, spacing: 8) {
            header(cols: cols)
            grid(cols: cols)
            if let idx = hoverIndex, idx < cells.count {
                tooltip(for: cells[idx])
            }
        }
        .padding(14)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    private func header(cols: [[DayCell]]) -> some View {
        // Header label adapts to the visible range. "ACTIVITÉ DEPUIS
        // <month>" reads better than a static "4 DERNIERS MOIS" once
        // leading empty months get trimmed.
        let firstDate = cols.first?.first?.date
        let monthFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "MMM yyyy"
            f.locale = Locale(identifier: "fr_FR")
            return f
        }()
        let label = firstDate.map {
            "DEPUIS \(monthFormatter.string(from: $0).uppercased())"
        } ?? "ACTIVITÉ"
        return HStack {
            Text(label)
                .font(.system(size: 9).weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(AppColors.terra)
            Rectangle().fill(AppColors.creamBorder).frame(width: 16, height: 1)
            Text("DISTANCE PAR JOUR")
                .font(.system(size: 9).weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(AppColors.inkLight)
            Spacer()
            HStack(spacing: 3) {
                Text("low").font(.system(size: 9)).foregroundStyle(AppColors.inkLight)
                ForEach([AppColors.heat0, AppColors.heat1, AppColors.heat2, AppColors.heat3, AppColors.heat4], id: \.self) { c in
                    Rectangle().fill(c)
                        .frame(width: 9, height: 9)
                        .overlay(Rectangle().stroke(AppColors.creamBorder, lineWidth: 0.5))
                        .cornerRadius(2)
                }
                Text("high").font(.system(size: 9)).foregroundStyle(AppColors.inkLight)
            }
        }
    }

    private func grid(cols: [[DayCell]]) -> some View {
        let labelW: CGFloat = 14
        let dayShort = ["L", "M", "M", "J", "V", "S", "D"]

        // Month labels: only show when month changes between consecutive weeks.
        let monthAt: [Int] = cols.map { col in
            guard let first = col.first?.date else { return -1 }
            return Calendar.current.component(.month, from: first)
        }
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "MMM"
            f.locale = Locale(identifier: "fr_FR")
            return f
        }()

        // Month label row uses absolute positioning so each label
        // can render its full name (e.g. "févr") without being
        // clipped to a single cellSize-wide box. Labels overlap into
        // the next column's space — that's fine because the row sits
        // above the heatmap and there's nothing to collide with.
        let columnAdvance = Self.cellSize + Self.cellGap
        let labelRowOriginX = labelW + Self.cellGap

        return VStack(alignment: .leading, spacing: Self.cellGap) {
            ZStack(alignment: .topLeading) {
                // Invisible spacer to size the ZStack to match the
                // grid's full width.
                HStack(spacing: Self.cellGap) {
                    Color.clear.frame(width: labelW, height: 14)
                    ForEach(0..<cols.count, id: \.self) { _ in
                        Color.clear.frame(width: Self.cellSize, height: 14)
                    }
                }
                ForEach(0..<cols.count, id: \.self) { i in
                    let m = monthAt[i]
                    let prev = i > 0 ? monthAt[i - 1] : -1
                    if m != prev, let first = cols[i].first {
                        let raw = formatter.string(from: first.date)
                            .replacingOccurrences(of: ".", with: "")
                        // Cap at 3 letters minimum if the formatter
                        // returned something longer (some locales
                        // return e.g. "septembre" for short month).
                        let label = raw.count > 4 ? String(raw.prefix(3)) : raw
                        Text(label.capitalized)
                            .font(.system(size: 9).weight(.semibold))
                            .foregroundStyle(AppColors.inkLight)
                            .fixedSize(horizontal: true, vertical: false)
                            .offset(x: labelRowOriginX + CGFloat(i) * columnAdvance)
                    }
                }
            }

            // 7 rows of cells.
            ForEach(0..<7, id: \.self) { row in
                HStack(spacing: Self.cellGap) {
                    Text(row % 2 == 0 ? dayShort[row] : "")
                        .font(.system(size: 9))
                        .foregroundStyle(AppColors.inkLight)
                        .frame(width: labelW, height: Self.cellSize)
                    ForEach(0..<cols.count, id: \.self) { w in
                        let cell = cols[w][row]
                        cellView(for: cell)
                    }
                }
            }
        }
    }

    private func cellView(for cell: DayCell) -> some View {
        let bg: Color = cell.inFuture
            ? Color.clear
            : intensityColor(km: cell.totalKm, hasActivity: !cell.activities.isEmpty)
        return Rectangle()
            .fill(bg)
            .frame(width: Self.cellSize, height: Self.cellSize)
            .overlay(
                Rectangle()
                    .stroke(cell.inFuture ? Color.clear : AppColors.creamBorder, lineWidth: 0.5),
            )
            .cornerRadius(2)
            .onTapGesture { hoverIndex = cell.id }
    }

    private func tooltip(for cell: DayCell) -> some View {
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "EEE d MMM"
            f.locale = Locale(identifier: "fr_FR")
            return f
        }()
        let dateLbl = formatter.string(from: cell.date)

        let hrColor = Color(red: 0.78, green: 0.25, blue: 0.18)
        var chips: [(String, String, Color)] = []
        chips.append(("KM", String(format: "%.1f", cell.totalKm), AppColors.terra))
        if let speed = cell.avgSpeedKmh { chips.append(("MOY", String(format: "%.1f km/h", speed), AppColors.blue)) }
        if cell.totalElevationM > 0 { chips.append(("D+", "\(Int(cell.totalElevationM)) m", AppColors.green)) }
        if cell.totalDurationMin > 0 { chips.append(("DURÉE", formatDuration(cell.totalDurationMin), AppColors.ink)) }
        if let v = cell.maxSpeedKmh { chips.append(("V. MAX", String(format: "%.1f km/h", v), AppColors.blue)) }
        if let p = cell.maxInclinePct { chips.append(("PENTE MAX", String(format: "%.1f %%", p), AppColors.terra)) }
        if let hr = cell.avgHrBpm { chips.append(("FC MOY", "\(hr) bpm", hrColor)) }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(dateLbl.capitalized)
                    .font(.system(size: 10).weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(AppColors.ink)
                if cell.activities.count == 1, let title = cell.activities.first?.title, !title.isEmpty {
                    Text("· \(title)")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.inkLight)
                        .lineLimit(1)
                } else if cell.activities.count > 1 {
                    Text("· \(cell.activities.count) sorties")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.inkLight)
                }
            }

            if cell.activities.isEmpty {
                Text("Pas d'activité")
                    .font(.system(size: 10).italic())
                    .foregroundStyle(AppColors.inkLight)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 74), spacing: 14, alignment: .leading)],
                    alignment: .leading, spacing: 8,
                ) {
                    ForEach(chips, id: \.0) { chip in
                        statChip(label: chip.0, value: chip.1, color: chip.2)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppColors.creamDark, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 0.5))
    }

    private func formatDuration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h\(String(format: "%02d", m))" : "\(m) min"
    }

    private func statChip(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8).weight(.bold))
                .tracking(1.0)
                .foregroundStyle(AppColors.inkLight)
            Text(value)
                .font(.system(size: 11, design: .serif).weight(.bold))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }

    // MARK: - Grid construction

    private func buildGrid() -> [DayCell] {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())

        // Find the most recent Monday (or today if it's Monday).
        let weekday = calendar.component(.weekday, from: today) // 1=Sun..7=Sat
        let mondayOffset = ((weekday + 5) % 7) // 0 if Mon
        let lastMonday = calendar.date(byAdding: .day, value: -mondayOffset, to: today)!
        let start = calendar.date(byAdding: .day, value: -((Self.weeksShown - 1) * 7), to: lastMonday)!

        // Group activities by their LOCAL ISO day (yyyy-MM-dd in the
        // device's timezone). Used to mirror the grid keys, which are
        // also formatted in local time. Naively using `rawDate.prefix(10)`
        // would bucket every ride under its UTC date — late-evening
        // rides in Paris would land in the wrong cell, and "today's"
        // cell would systematically be one day off near midnight UTC.
        var byDay: [String: [RideRecord]] = [:]
        for a in activities {
            let key = RideDate.localIsoDay(parsing: a.rawDate)
            byDay[key, default: []].append(a)
        }

        var cells: [DayCell] = []
        cells.reserveCapacity(Self.weeksShown * 7)
        for i in 0..<(Self.weeksShown * 7) {
            let day = calendar.date(byAdding: .day, value: i, to: start)!
            let key = RideDate.isoDay(day)
            let acts = byDay[key] ?? []
            let totalKm = acts.compactMap(\.distance).reduce(0, +)
            let totalElev = acts.compactMap(\.elevation).reduce(0, +)
            let totalDur = acts.map(\.durationMin).reduce(0, +)
            cells.append(DayCell(
                id: i,
                date: day,
                isoDay: key,
                activities: acts,
                totalKm: totalKm,
                totalElevationM: totalElev,
                totalDurationMin: totalDur,
                inFuture: day > today,
            ))
        }
        return cells
    }

    /// Colour ramps with distance now (matches the new "DISTANCE PAR
    /// JOUR" header). Bins are cycling-leaning since most of Florian's
    /// data is bike rides, but still readable for running / walking.
    private func intensityColor(km: Double, hasActivity: Bool) -> Color {
        guard hasActivity else { return AppColors.heat0 }
        if km >= 60 { return AppColors.heat4 }
        if km >= 30 { return AppColors.heat3 }
        if km >= 15 { return AppColors.heat2 }
        return AppColors.heat1
    }
}
