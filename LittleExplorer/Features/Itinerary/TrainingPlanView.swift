import SwiftUI
import Charts

/// "Plan d'entraînement" — adapts its inputs to the SportCategory.
///   Vélo    → cible distance (km) + dénivelé (m) — l'algo TSS d'origine.
///   Course  → cible distance (km) + allure (min/km) — TSS estimé par
///             puissance d'effort liée à la VMA.
///   Snow / Water / Indoor → placeholder pour l'instant.
struct TrainingPlanView: View {
    let category: SportCategory
    @Environment(AppEnvironment.self) private var environment

    @State private var targetKm: Double = 100
    @State private var targetElev: Double = 1500
    /// Target running pace expressed in seconds per km. Slider works
    /// in seconds so the conversion stays in one place; UI formats
    /// it back to "5:30 /km".
    @State private var targetPaceSecPerKm: Double = 5 * 60   // 5:00 /km default
    @State private var startDate: Date = Date()
    @State private var targetDate: Date = Calendar.current.date(byAdding: .day, value: 56, to: Date()) ?? Date()
    @State private var generated: Bool = false

    init(category: SportCategory = .cycling) {
        self.category = category
    }

    var body: some View {
        switch category {
        case .cycling: cyclingBody
        case .footing: runningBody
        case .snow, .water, .indoor: placeholderBody
        }
    }

    // MARK: - Cycling (original TSS plan)

    private var cyclingBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                introBlock
                form
                generateButton
                if generated, let result = planResult {
                    safeZoneBanner(result: result)
                    chart(result: result)
                    weeksList(result: result)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(AppColors.cream)
    }

    // MARK: - Running variant (pace target instead of elevation)

    private var runningBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                runningHeader
                runningIntro
                runningForm
                generateButton
                if generated, let result = planResult {
                    safeZoneBanner(result: result)
                    chart(result: result)
                    weeksList(result: result)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(AppColors.cream)
    }

    private var runningHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("§ PLAN").font(.system(size: 10).weight(.bold)).tracking(1.5).foregroundStyle(AppColors.green)
                Rectangle().fill(AppColors.creamBorder).frame(width: 20, height: 1)
                Text("PLAN COURSE À PIED").font(.system(size: 10).weight(.bold)).tracking(1.5).foregroundStyle(AppColors.inkMid)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Construis ta course.")
                    .font(.system(.title, design: .serif).weight(.heavy))
                    .foregroundStyle(AppColors.ink)
                Text("Distance + allure.")
                    .font(.system(.title, design: .serif).weight(.bold).italic())
                    .foregroundStyle(AppColors.green)
            }
            .padding(.top, 4)
        }
    }

    private var runningIntro: some View {
        Text("Renseigne ta distance cible (5k → semi → marathon) et ton allure cible. Je dimensionne la charge semaine par semaine en gardant le même cycle 3:1 + 2 semaines de taper que pour le vélo.")
            .font(.system(size: 12)).foregroundStyle(AppColors.inkLight).lineSpacing(2)
    }

    private var runningForm: some View {
        VStack(spacing: 14) {
            slider(label: "OBJECTIF DISTANCE", value: $targetKm, range: 5...50, step: 1, unit: "km")
            paceSlider(label: "ALLURE CIBLE", value: $targetPaceSecPerKm, range: 210...480, step: 5)
            HStack(spacing: 12) {
                datePickerCell(label: "DÉBUT DE PRÉPARATION", date: $startDate)
                datePickerCell(label: "DATE DE L'OBJECTIF", date: $targetDate)
            }
        }
        .padding(14)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    /// Pace slider — value is seconds per km, display is mm:ss /km.
    private func paceSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.system(size: 10).weight(.bold)).tracking(1.2).foregroundStyle(AppColors.inkLight)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(formatPace(value.wrappedValue))
                        .font(.system(.title2, design: .serif).weight(.bold))
                        .foregroundStyle(AppColors.ink)
                    Text("/km").font(.system(size: 11)).foregroundStyle(AppColors.inkLight)
                }
            }
            Slider(value: value, in: range, step: step)
                .tint(AppColors.green)
            HStack {
                Text("3:30").font(.system(size: 9)).foregroundStyle(AppColors.inkLight)
                Spacer()
                Text("8:00").font(.system(size: 9)).foregroundStyle(AppColors.inkLight)
            }
        }
    }

    private func formatPace(_ secPerKm: Double) -> String {
        let s = Int(secPerKm.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - Placeholder for snow / water / indoor

    private var placeholderBody: some View {
        VStack(spacing: 18) {
            Image(systemName: placeholderIcon)
                .font(.system(size: 48))
                .foregroundStyle(AppColors.terra)
            Text(placeholderTitle)
                .font(.system(.title2, design: .serif).weight(.heavy))
                .foregroundStyle(AppColors.ink)
            Text(placeholderBlurb)
                .font(.system(.callout, design: .serif))
                .foregroundStyle(AppColors.inkMid)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("Bientôt disponible")
                .font(.system(size: 11).weight(.bold)).tracking(1.2)
                .foregroundStyle(AppColors.terra)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(AppColors.terraLight, in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.cream)
    }

    private var placeholderIcon: String {
        switch category {
        case .snow:   return "snowflake"
        case .water:  return "drop.fill"
        case .indoor: return "dumbbell.fill"
        default:      return "sparkles"
        }
    }
    private var placeholderTitle: String {
        switch category {
        case .snow:   return "Plan ski"
        case .water:  return "Plan natation"
        case .indoor: return "Plan séance indoor"
        default:      return "Plan d'entraînement"
        }
    }
    private var placeholderBlurb: String {
        switch category {
        case .snow:   return "Cycle d'entraînement pour ta sortie ski (alpin / nordique). Plans dédiés à venir."
        case .water:  return "Séances bassin par distance + intervalles. À venir."
        case .indoor: return "Plans de force, HIIT, RPM, yoga par durée + intensité. À venir."
        default:      return "À venir."
        }
    }

    // MARK: - Header + intro

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("§ PLAN").font(.system(size: 10).weight(.bold)).tracking(1.5).foregroundStyle(AppColors.terra)
                Rectangle().fill(AppColors.creamBorder).frame(width: 20, height: 1)
                Text("PLAN D'ENTRAÎNEMENT").font(.system(size: 10).weight(.bold)).tracking(1.5).foregroundStyle(AppColors.inkMid)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Construis ta progression.")
                    .font(.system(.title, design: .serif).weight(.heavy))
                    .foregroundStyle(AppColors.ink)
                Text("Semaine par semaine.")
                    .font(.system(.title, design: .serif).weight(.bold).italic())
                    .foregroundStyle(AppColors.terra)
            }
            .padding(.top, 4)
        }
    }

    private var introBlock: some View {
        let baseline = baselineWeeklyTss()
        return VStack(alignment: .leading, spacing: 4) {
            Text("Renseigne ton objectif, je dimensionne la charge semaine par semaine. Cycle 3:1 (3 semaines de progression +10% / 1 semaine d'allègement), 2 semaines de taper avant la date cible.")
                .font(.system(size: 12)).foregroundStyle(AppColors.inkLight).lineSpacing(2)
            if baseline.hasData {
                Text("Base : \(baseline.tss) TSS / sem (4 dernières semaines)")
                    .font(.system(size: 11).italic()).foregroundStyle(AppColors.inkLight)
            } else {
                Text("Pas assez d'historique récent — base fixée à 250 TSS / sem.")
                    .font(.system(size: 11).italic()).foregroundStyle(AppColors.inkLight)
            }
        }
    }

    // MARK: - Form

    private var form: some View {
        VStack(spacing: 14) {
            slider(label: "OBJECTIF DISTANCE", value: $targetKm, range: 20...200, step: 5, unit: "km")
            slider(label: "OBJECTIF DÉNIVELÉ", value: $targetElev, range: 100...4000, step: 50, unit: "m")
            HStack(spacing: 12) {
                datePickerCell(label: "DÉBUT DE PRÉPARATION", date: $startDate)
                datePickerCell(label: "DATE DE L'OBJECTIF", date: $targetDate)
            }
        }
        .padding(14)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    private func slider(label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.system(size: 10).weight(.bold)).tracking(1.2).foregroundStyle(AppColors.inkLight)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(value.wrappedValue))")
                        .font(.system(.title2, design: .serif).weight(.bold))
                        .foregroundStyle(AppColors.ink)
                    Text(unit).font(.system(size: 11)).foregroundStyle(AppColors.inkLight)
                }
            }
            Slider(value: value, in: range, step: step)
                .tint(AppColors.terra)
            HStack {
                Text("\(Int(range.lowerBound)) \(unit)").font(.system(size: 9)).foregroundStyle(AppColors.inkLight)
                Spacer()
                Text("\(Int(range.upperBound)) \(unit)").font(.system(size: 9)).foregroundStyle(AppColors.inkLight)
            }
        }
    }

    private func datePickerCell(label: String, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10).weight(.bold)).tracking(1.2).foregroundStyle(AppColors.inkLight)
            DatePicker("", selection: date, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var generateButton: some View {
        Button {
            generated = true
        } label: {
            Text("GÉNÉRER LE PLAN  →")
                .font(.system(size: 12).weight(.bold)).tracking(1.5)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppColors.terra, in: RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Result

    private func safeZoneBanner(result: PlanResult) -> some View {
        HStack(alignment: .top) {
            Rectangle().fill(result.tooSteep ? Color.red : AppColors.green).frame(width: 3)
            if result.tooSteep {
                Text("Fenêtre de \(result.totalWeeks) semaines : la progression est trop raide. Allonge la prépa ou réduis l'objectif.")
                    .font(.system(size: 11)).foregroundStyle(AppColors.inkMid).lineSpacing(2)
            } else {
                Text("Fenêtre de \(result.totalWeeks) semaines · pic à ×\(String(format: "%.2f", result.peak)) la base — progression sûre.")
                    .font(.system(size: 11)).foregroundStyle(AppColors.inkMid).lineSpacing(2)
            }
            Spacer()
        }
        .padding(10)
        .background(AppColors.creamDark, in: RoundedRectangle(cornerRadius: 3))
    }

    private func chart(result: PlanResult) -> some View {
        let baseline = baselineWeeklyTss().tss
        return Chart {
            ForEach(result.weeks) { week in
                BarMark(
                    x: .value("Semaine", "S\(week.index)"),
                    y: .value("TSS", week.totalTss),
                )
                .foregroundStyle(week.phase.color)
                .cornerRadius(3)
            }
            RuleMark(y: .value("Baseline", baseline))
                .foregroundStyle(AppColors.inkLight.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .frame(height: 160)
        .padding(10)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    private func weeksList(result: PlanResult) -> some View {
        VStack(spacing: 6) {
            ForEach(result.weeks) { week in
                weekCard(week: week)
            }
        }
    }

    private func weekCard(week: WeekPlan) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(week.phase.color).frame(width: 4)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Semaine \(week.index)")
                        .font(.system(.body, design: .serif).weight(.bold))
                        .foregroundStyle(AppColors.ink)
                    if week.isPeak {
                        Text("PEAK")
                            .font(.system(size: 8).weight(.bold)).tracking(1.0)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(AppColors.terra, in: RoundedRectangle(cornerRadius: 2))
                    }
                    Spacer()
                    Text(week.phase.label.uppercased())
                        .font(.system(size: 9).weight(.bold)).tracking(0.8)
                        .foregroundStyle(week.phase.color)
                }
                Text(weekRangeLabel(week))
                    .font(.system(size: 10)).foregroundStyle(AppColors.inkLight)
                HStack(spacing: 16) {
                    statMini(label: "TSS",  value: "\(week.totalTss)",  color: week.phase.color)
                    statMini(label: "KM",   value: "\(week.totalKm)",   color: AppColors.ink)
                    statMini(label: "D+",   value: "\(week.totalElev) m", color: AppColors.ink)
                }
                dayGrid(week: week)
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
        }
        .background(AppColors.creamDark, in: RoundedRectangle(cornerRadius: 3))
    }

    private func dayGrid(week: WeekPlan) -> some View {
        HStack(spacing: 3) {
            ForEach(week.days, id: \.dow) { day in
                VStack(spacing: 2) {
                    Text(dayLabel(day.dow))
                        .font(.system(size: 8).weight(.bold))
                        .foregroundStyle(AppColors.inkLight)
                    Rectangle()
                        .fill(dayColor(day: day, phase: week.phase))
                        .frame(height: 18)
                        .cornerRadius(2)
                        .overlay(
                            Text(day.tss > 0 ? "\(day.tss)" : "")
                                .font(.system(size: 8).weight(.bold))
                                .foregroundStyle(day.tss > 30 ? .white : AppColors.inkMid),
                        )
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 2)
    }

    private func dayLabel(_ dow: Int) -> String {
        ["L","M","M","J","V","S","D"][dow]
    }

    private func dayColor(day: DayPlan, phase: Phase) -> Color {
        if day.tss == 0 { return AppColors.creamBorder.opacity(0.4) }
        let intensity = min(1.0, Double(day.tss) / 200.0)
        return phase.color.opacity(0.3 + 0.6 * intensity)
    }

    private func statMini(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 8).weight(.bold)).tracking(0.8).foregroundStyle(AppColors.inkLight)
            Text(value).font(.system(.callout, design: .serif).weight(.bold)).foregroundStyle(color)
        }
    }

    private func weekRangeLabel(_ week: WeekPlan) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        formatter.locale = Locale(identifier: "fr_FR")
        return "\(formatter.string(from: week.weekStart)) → \(formatter.string(from: week.weekEnd))"
    }

    // MARK: - Algorithm

    private var planResult: PlanResult? {
        guard generated else { return nil }
        guard targetDate.timeIntervalSince(startDate) >= 2 * 86400 else { return nil }
        let baseline = Double(baselineWeeklyTss().tss)

        let oneDayTss: Double
        let peakWeeklyKm: Double
        let peakWeeklyElev: Double
        let goalElev: Double

        switch category {
        case .footing:
            // Running TSS model. Pace 5:00 /km is the "reference"
            // (~7 TSS/km). Faster pace → higher TSS/km (squared so
            // the curve climbs steeply for sub-4:00 efforts). No
            // elevation target — runners think in pace, not D+.
            let intensity = 300.0 / max(targetPaceSecPerKm, 180)
            oneDayTss = targetKm * 7 * intensity * intensity
            peakWeeklyKm = targetKm * 1.4
            peakWeeklyElev = 0
            goalElev = 0
        case .cycling:
            // Original cycling model: distance + elevation feed TSS.
            oneDayTss = targetKm * 2.5 + targetElev * 0.05
            peakWeeklyKm = targetKm * 1.6
            peakWeeklyElev = targetElev * 1.5
            goalElev = targetElev
        default:
            return nil
        }

        let peakWeeklyTss = oneDayTss * 2.4
        return buildPlan(
            baseline: baseline,
            peakWeeklyTss: peakWeeklyTss,
            peakWeeklyKm: peakWeeklyKm,
            peakWeeklyElev: peakWeeklyElev,
            startDate: startDate,
            targetDate: targetDate,
            goal: (km: targetKm, elev: goalElev, oneDayTss: oneDayTss),
        )
    }

    private func baselineWeeklyTss() -> (tss: Int, hasData: Bool) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        let recent = environment.activityStore.activities.filter { record in
            guard let d = RideDate.parse(record.rawDate) else { return false }
            return d >= cutoff
        }
        let total = recent.compactMap { $0.tss }.reduce(0, +)
        if recent.count < 2 || total <= 0 { return (250, false) }
        return (max(150, total / 4), true)
    }
}

// MARK: - Plan algorithm types

/// Phase of a single week in the training plan.
enum Phase: String, Hashable {
    case build, deload, taper, race

    var color: Color {
        switch self {
        case .build:  return AppColors.terra
        case .deload: return AppColors.blue
        case .taper:  return Color(hex: "9B6FB5")
        case .race:   return AppColors.green
        }
    }

    var label: String {
        switch self {
        case .build:  return "Construction"
        case .deload: return "Allègement"
        case .taper:  return "Affûtage"
        case .race:   return "Objectif"
        }
    }
}

enum DayType: String, Hashable {
    case rest, recovery, endurance, tempo, long, openers, goal, outside
}

struct DayPlan: Hashable {
    let dow: Int
    let date: Date
    let type: DayType
    let km: Int
    let elev: Int
    let tss: Int
}

struct WeekPlan: Identifiable, Hashable {
    let index: Int
    let weekStart: Date
    let weekEnd: Date
    let ratio: Double
    let phase: Phase
    let isPeak: Bool
    let totalTss: Int
    let totalKm: Int
    let totalElev: Int
    let days: [DayPlan]

    var id: Int { index }
}

struct PlanResult {
    let weeks: [WeekPlan]
    let tooSteep: Bool
    let peak: Double
    let totalWeeks: Int
}

// MARK: - Plan algorithm

private let SESSION_RATIO: [DayType: Double] = [
    .long: 0.40, .tempo: 0.25, .endurance: 0.20, .recovery: 0.15,
]

/// Day-of-week templates per phase: index 0=Monday … 6=Sunday.
private let DOW_TEMPLATES: [Phase: [DayType]] = [
    .build:  [.recovery, .tempo, .endurance, .rest, .rest, .long, .rest],
    .deload: [.recovery, .endurance, .rest, .rest, .rest, .long, .rest],
    .taper:  [.endurance, .rest, .tempo, .rest, .rest, .long, .rest],
]

private func shareFor(_ type: DayType) -> Double {
    SESSION_RATIO[type] ?? 0
}

private func startOfMonday(_ date: Date) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2  // Monday
    let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
    return cal.date(from: comps) ?? date
}

private func dayFromShare(dow: Int, date: Date, type: DayType, share: Double, totals: (tss: Double, km: Double, elev: Double)) -> DayPlan {
    DayPlan(
        dow: dow, date: date, type: type,
        km: Int((totals.km * share).rounded()),
        elev: Int((totals.elev * share).rounded()),
        tss: Int((totals.tss * share).rounded()),
    )
}

private func buildBuildishWeek(weekStart: Date, phase: Phase, totals: (tss: Double, km: Double, elev: Double), startDate: Date, goalDate: Date) -> [DayPlan] {
    let tpl = DOW_TEMPLATES[phase] ?? DOW_TEMPLATES[.build]!
    return (0..<7).map { dow in
        let date = Calendar.current.date(byAdding: .day, value: dow, to: weekStart) ?? weekStart
        if date < startDate || date > goalDate {
            return DayPlan(dow: dow, date: date, type: .outside, km: 0, elev: 0, tss: 0)
        }
        let t = tpl[dow]
        if t == .rest {
            return DayPlan(dow: dow, date: date, type: .rest, km: 0, elev: 0, tss: 0)
        }
        return dayFromShare(dow: dow, date: date, type: t, share: shareFor(t), totals: totals)
    }
}

private func raceWeekDay(daysToGoal: Int) -> (type: DayType, km: Int, elev: Int, tss: Int) {
    switch daysToGoal {
    case 0:  return (.goal,     0, 0, 0)
    case 1:  return (.rest,     0, 0, 0)
    case 2:  return (.openers,  8, 60, 25)
    case 3:  return (.recovery, 10, 60, 18)
    case 4:  return (.rest,     0, 0, 0)
    case 5:  return (.endurance, 18, 130, 40)
    default: return (.rest,     0, 0, 0)
    }
}

private func buildRaceWeek(weekStart: Date, goalDate: Date, goal: (km: Double, elev: Double, oneDayTss: Double), startDate: Date) -> [DayPlan] {
    (0..<7).map { dow in
        let date = Calendar.current.date(byAdding: .day, value: dow, to: weekStart) ?? weekStart
        if date < startDate || date > goalDate {
            return DayPlan(dow: dow, date: date, type: .outside, km: 0, elev: 0, tss: 0)
        }
        let daysToGoal = Int(round(goalDate.timeIntervalSince(date) / 86400))
        if daysToGoal == 0 {
            return DayPlan(dow: dow, date: date, type: .goal, km: Int(goal.km.rounded()), elev: Int(goal.elev.rounded()), tss: Int(goal.oneDayTss.rounded()))
        }
        let r = raceWeekDay(daysToGoal: daysToGoal)
        return DayPlan(dow: dow, date: date, type: r.type, km: r.km, elev: r.elev, tss: r.tss)
    }
}

private func buildRatios(totalWeeks: Int, targetPeak: Double) -> (steps: [(ratio: Double, phase: Phase)], tooSteep: Bool, peak: Double) {
    if totalWeeks <= 1 {
        return ([(ratio: 0.40, phase: .race)], true, 0.40)
    }
    let taperWeeks = totalWeeks >= 3 ? 2 : max(0, totalWeeks - 1)
    let racePresent = totalWeeks >= 2
    let trainingWeeks = totalWeeks - taperWeeks - (racePresent ? 1 : 0)
    if trainingWeeks <= 0 {
        var out: [(ratio: Double, phase: Phase)] = []
        if taperWeeks >= 2 { out.append((ratio: 0.85, phase: .taper)) }
        if taperWeeks >= 1 { out.append((ratio: 0.65, phase: .taper)) }
        if racePresent     { out.append((ratio: 0.50, phase: .race)) }
        return (out, true, 0.85)
    }
    let useDeloadPattern = trainingWeeks >= 6
    let progressiveCount = useDeloadPattern
        ? trainingWeeks - (trainingWeeks / 4)
        : trainingWeeks
    let N = max(1, progressiveCount - 1)
    let step = pow(targetPeak, 1.0 / Double(N))
    let tooSteep = step > 1.105

    var out: [(ratio: Double, phase: Phase)] = []
    var cur = 1.0
    var lastProgressive = 1.0
    for i in 0..<trainingWeeks {
        let isFourth = (i + 1) % 4 == 0
        if useDeloadPattern, isFourth, i < trainingWeeks - 1 {
            out.append((ratio: (lastProgressive * 0.6).rounded2, phase: .deload))
        } else {
            lastProgressive = cur
            out.append((ratio: cur.rounded2, phase: .build))
            cur *= step
        }
    }
    let peak = out.map { $0.ratio }.max() ?? 1.0
    if taperWeeks >= 2 {
        out.append((ratio: (peak * 0.65).rounded2, phase: .taper))
        out.append((ratio: (peak * 0.45).rounded2, phase: .taper))
    } else if taperWeeks == 1 {
        out.append((ratio: (peak * 0.55).rounded2, phase: .taper))
    }
    if racePresent {
        out.append((ratio: 0.40, phase: .race))
    }
    return (out, tooSteep, peak)
}

private extension Double {
    var rounded2: Double { (self * 100).rounded() / 100 }
}

private func buildPlan(baseline: Double, peakWeeklyTss: Double, peakWeeklyKm: Double, peakWeeklyElev: Double, startDate: Date, targetDate: Date, goal: (km: Double, elev: Double, oneDayTss: Double)) -> PlanResult {
    let start = startOfMonday(startDate)
    let targetMonday = startOfMonday(targetDate)
    let rawSpan = Int(ceil(targetMonday.timeIntervalSince(start) / (7 * 86400))) + 1
    let totalWeeks = min(24, max(1, rawSpan))
    let targetPeak = max(1.05, peakWeeklyTss / max(baseline, 1))
    let r = buildRatios(totalWeeks: totalWeeks, targetPeak: targetPeak)

    let weeks: [WeekPlan] = r.steps.enumerated().map { (i, step) in
        let weekStart = Calendar.current.date(byAdding: .day, value: i * 7, to: start) ?? start
        let weekEnd = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let days: [DayPlan]
        if step.phase == .race {
            days = buildRaceWeek(weekStart: weekStart, goalDate: targetDate, goal: goal, startDate: startDate)
        } else {
            let totals = (
                tss:  baseline * step.ratio,
                km:   peakWeeklyKm   * (step.ratio / r.peak),
                elev: peakWeeklyElev * (step.ratio / r.peak),
            )
            days = buildBuildishWeek(weekStart: weekStart, phase: step.phase, totals: totals, startDate: startDate, goalDate: targetDate)
        }
        return WeekPlan(
            index: i + 1,
            weekStart: weekStart, weekEnd: weekEnd,
            ratio: step.ratio, phase: step.phase,
            isPeak: step.ratio == r.peak,
            totalTss:  days.map(\.tss).reduce(0, +),
            totalKm:   days.map(\.km).reduce(0, +),
            totalElev: days.map(\.elev).reduce(0, +),
            days: days,
        )
    }
    return PlanResult(weeks: weeks, tooSteep: r.tooSteep, peak: r.peak, totalWeeks: totalWeeks)
}
