import SwiftUI

/// 26-week (≈ 6 months) TSS heatmap. Each cell is one day; intensity
/// scales with the total TSS recorded that day. Cells size dynamically
/// to fill the card's available width, so the chart never has dead
/// whitespace on the right. Tap a cell to surface its summary line.
struct ActivityCalendarView: View {
    let activities: [RideRecord]

    @State private var hoverIndex: Int?

    private static let weeksShown = 26
    private static let cellGap: CGFloat = 2
    private static let labelW: CGFloat = 14
    private static let minCell: CGFloat = 8
    private static let maxCell: CGFloat = 18

    private struct DayCell: Identifiable, Hashable {
        let id: Int
        let date: Date
        let isoDay: String
        let activities: [RideRecord]
        let totalTss: Int
        let inFuture: Bool
    }

    var body: some View {
        let cells = buildGrid()
        let cols: [[DayCell]] = (0..<Self.weeksShown).map { w in
            Array(cells[(w * 7)..<((w + 1) * 7)])
        }

        VStack(alignment: .leading, spacing: 8) {
            header
            GeometryReader { geo in
                let cellSize = computeCellSize(for: geo.size.width)
                grid(cols: cols, cellSize: cellSize)
            }
            .frame(height: gridHeight(for: 0))
            .onAppear {} // force re-layout on rotation / size class changes
            if let idx = hoverIndex, idx < cells.count {
                tooltip(for: cells[idx])
            }
        }
        .padding(14)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("6 DERNIERS MOIS")
                .font(.system(size: 9).weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(AppColors.terra)
            Rectangle().fill(AppColors.creamBorder).frame(width: 16, height: 1)
            Text("HEATMAP TSS")
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

    // MARK: - Grid

    private func computeCellSize(for availableWidth: CGFloat) -> CGFloat {
        let weeks = CGFloat(Self.weeksShown)
        let totalGapWidth = (weeks - 1) * Self.cellGap + Self.cellGap // include gap after the day-label column too
        let usable = max(0, availableWidth - Self.labelW - totalGapWidth)
        let raw = usable / weeks
        return max(Self.minCell, min(Self.maxCell, floor(raw)))
    }

    /// Approximate height the grid needs (used to size the
    /// GeometryReader before its proxy resolves the final width).
    private func gridHeight(for cellSize: CGFloat) -> CGFloat {
        let s = cellSize > 0 ? cellSize : Self.maxCell
        return s * 7 + Self.cellGap * 6 + 18 // 7 rows + 6 gaps + month label row
    }

    private func grid(cols: [[DayCell]], cellSize: CGFloat) -> some View {
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

        return VStack(alignment: .leading, spacing: Self.cellGap) {
            // Month row.
            HStack(spacing: Self.cellGap) {
                Color.clear.frame(width: Self.labelW)
                ForEach(0..<cols.count, id: \.self) { i in
                    let m = monthAt[i]
                    let prev = i > 0 ? monthAt[i - 1] : -1
                    let label = (m != prev && cols[i].first != nil)
                        ? formatter.string(from: cols[i].first!.date).replacingOccurrences(of: ".", with: "")
                        : ""
                    Text(label)
                        .font(.system(size: 9))
                        .foregroundStyle(AppColors.inkLight)
                        .frame(width: cellSize, alignment: .leading)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            // 7 rows of cells.
            ForEach(0..<7, id: \.self) { row in
                HStack(spacing: Self.cellGap) {
                    Text(row % 2 == 0 ? dayShort[row] : "")
                        .font(.system(size: 9))
                        .foregroundStyle(AppColors.inkLight)
                        .frame(width: Self.labelW, height: cellSize)
                    ForEach(0..<cols.count, id: \.self) { w in
                        let cell = cols[w][row]
                        cellView(for: cell, size: cellSize)
                    }
                }
            }
        }
    }

    private func cellView(for cell: DayCell, size: CGFloat) -> some View {
        let bg: Color = cell.inFuture
            ? Color.clear
            : intensityColor(tss: cell.totalTss, hasActivity: !cell.activities.isEmpty)
        return Rectangle()
            .fill(bg)
            .frame(width: size, height: size)
            .overlay(
                Rectangle()
                    .stroke(cell.inFuture ? Color.clear : AppColors.creamBorder, lineWidth: 0.5),
            )
            .cornerRadius(2)
            .onTapGesture { hoverIndex = cell.id }
    }

    // MARK: - Tooltip

    private func tooltip(for cell: DayCell) -> some View {
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "EEE d MMM"
            f.locale = Locale(identifier: "fr_FR")
            return f
        }()
        let dateLbl = formatter.string(from: cell.date)
        let text: String
        if cell.activities.isEmpty {
            text = "\(dateLbl) — pas d'activité"
        } else {
            let km = cell.activities.compactMap { $0.distance }.reduce(0, +)
            let tss = cell.totalTss
            let n = cell.activities.count
            text = n == 1
                ? "\(dateLbl) — \(Int(km)) km · TSS \(tss)"
                : "\(dateLbl) — \(n) sorties · \(Int(km)) km · TSS \(tss)"
        }
        return Text(text)
            .font(.system(size: 10))
            .foregroundStyle(AppColors.inkMid)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(AppColors.creamDark, in: RoundedRectangle(cornerRadius: 3))
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

        // Group activities by ISO day.
        var byDay: [String: [RideRecord]] = [:]
        for a in activities {
            let key = String(a.rawDate.prefix(10))
            byDay[key, default: []].append(a)
        }

        var cells: [DayCell] = []
        cells.reserveCapacity(Self.weeksShown * 7)
        for i in 0..<(Self.weeksShown * 7) {
            let day = calendar.date(byAdding: .day, value: i, to: start)!
            let key = RideDate.isoDay(day)
            let acts = byDay[key] ?? []
            let totalTss = acts.compactMap(\.tss).reduce(0, +)
            cells.append(DayCell(
                id: i,
                date: day,
                isoDay: key,
                activities: acts,
                totalTss: totalTss,
                inFuture: day > today,
            ))
        }
        return cells
    }

    private func intensityColor(tss: Int, hasActivity: Bool) -> Color {
        guard hasActivity else { return AppColors.heat0 }
        if tss >= 100 { return AppColors.heat4 }
        if tss >= 60  { return AppColors.heat3 }
        if tss >= 30  { return AppColors.heat2 }
        return AppColors.heat1
    }
}
