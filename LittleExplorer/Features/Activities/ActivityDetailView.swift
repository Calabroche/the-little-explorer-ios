import Charts
import SwiftUI

/// Comprehensive ride detail page — mirrors the web's AnalysisPage,
/// with charts stacked vertically (one above another) so each one has
/// breathing room on a phone-sized screen.
///
/// Layout:
///   1. Header: sport pill + date · location, big serif title
///   2. Top stats card (Durée / Distance / Moy / Max / Montée / FC moy / FC max / Calories)
///   3. FTP estimé card with terra left-rule (cycling-only)
///   4. HR + slope composed chart
///   5. Speed area chart (blue)
///   6. Power area chart (green) — computed from speed + gradient
///   7. Elevation area chart (terra)
///   8. HR Zones bars (5 zones)
///   9. Big interactive map with tap-to-inspect popup
///  10. VO2 max card + Power summary card (estimated)
///  11. Effort & énergie 3-column grid (Puissance / Cardio / Mécanique & Météo)
struct ActivityDetailView: View {
    let activity: RideRecord

    @State private var selectedDist: Double?
    /// Which chart the user last touched. Drives where the scrub card
    /// is rendered — it sits immediately above the active chart so
    /// the finger isn't covering its own readout.
    @State private var activeChart: ChartKind = .hr

    enum ChartKind: Hashable { case hr, speed, power, altitude }

    /// chartData was a computed property running PowerStream.build on
    /// every body re-render. During a drag on any chart, body fires
    /// 60+ times per second, so we ended up recomputing the gradient
    /// + power model thousands of times per second of interaction —
    /// hence the multi-second lag Florian reported. Cached now and
    /// (re)computed exactly once when the view first appears.
    @State private var chartData: [ChartPoint] = []

    /// HR Y-axis bounds depend on chartData, so we cache them too.
    /// Recomputed in the same onAppear pass after chartData is ready.
    @State private var cachedHrRange: (min: Double, max: Double) = (80, 200)

    /// Climbs auto-detected from the altitude stream. Computed once on
    /// appear (same pass as chartData) so we don't re-walk the
    /// stream on every body recomputation.
    @State private var detectedClimbs: [Climb] = []
    /// Index of the climb currently highlighted on the route map.
    /// Tap a climb row to set; tap again to clear. Drives the
    /// `highlightSegment` prop on RouteAnalysisMap so the segment
    /// lights up below the Climbs card.
    @State private var selectedClimbIdx: Int?

    /// Cached + pre-warmed haptic generator so each selection snap
    /// fires in <1ms instead of allocating a new generator each time.
    @State private var haptics = UIImpactFeedbackGenerator(style: .light)

    private var hasHeartRate: Bool { (activity.heartrate?.count ?? 0) > 10 }
    private var hasPower: Bool { chartData.contains(where: { $0.power > 0 }) }
    // Strict threshold: MapPolyline on iOS 26 crashes the view when
    // it gets fewer than ~5 coords. Track rides of a handful of
    // seconds were tripping this — bumped from 1 to 5 to be safe.
    private var hasGPS: Bool { activity.gps.count >= 5 }
    /// Locally-recorded rides have negative ids (we encode the launch
    /// timestamp as -unix). Strava-sourced rides have positive ids.
    /// Only locals can be deleted from the app since they're not on
    /// the server.
    private var isLocalRide: Bool { activity.id < 0 }
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm: Bool = false
    /// Domain ceiling for every chart's `chartXScale`. Swift Charts
    /// crashes (FATAL: closed range with 0 width) when the domain is
    /// 0...0, and renders badly when it's 0...0.01. Floor at 0.5 km so
    /// the axes stay sane even on tiny rides.
    private var maxDistKm: Double {
        max(0.5, chartData.last?.distKm ?? activity.distance ?? 1)
    }

    /// Closest sample to the user's drag-selected X position (used by
    /// every chart's RuleMark + popup annotation).
    private var selectedPoint: ChartPoint? {
        guard let selectedDist, !chartData.isEmpty else { return nil }
        return chartData.min(by: { abs($0.distKm - selectedDist) < abs($1.distKm - selectedDist) })
    }

    var body: some View {
        // DIAGNOSTIC: log every body computation so the user can see in
        // Diagnostics which sections render before the crash. The
        // `_ =` pattern is a SwiftUI side-effect trick that fires once
        // per body evaluation without changing the view hierarchy.
        let _ = Log.ui.notice("ActivityDetailView.body id=\(activity.id) gps=\(activity.gps.count) hr=\(activity.heartrate?.count ?? 0) dist=\(activity.distance ?? -1)")
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                topStatsCard
                if activity.np != nil { ftpCard }

                // Charts are gated behind `!chartData.isEmpty` so a
                // very short Track ride (e.g. a 10 m shakedown that
                // produced fewer than the 10 GPS samples PowerStream
                // needs) doesn't try to render Swift Charts with an
                // empty data set + a near-zero chartXScale domain —
                // that combo crashes the detail view on iOS 26.
                if !chartData.isEmpty {
                    if hasHeartRate {
                        scrubCardSlot(for: .hr)
                        hrSlopeChart
                    }
                    scrubCardSlot(for: .speed)
                    speedChart
                    if hasPower {
                        scrubCardSlot(for: .power)
                        powerChart
                    }
                    scrubCardSlot(for: .altitude)
                    elevationChart
                } else {
                    cardWrapper(label: "DONNÉES") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Trop peu d'échantillons GPS pour tracer les courbes.")
                                .font(.system(size: 12))
                                .foregroundStyle(AppColors.inkMid)
                            Text("Roule au moins 30 s — Health + le local store gardent quand même un workout complet.")
                                .font(.caption)
                                .foregroundStyle(AppColors.inkLight)
                        }
                    }
                }

                if let zones = activity.hrZones { hrZonesCard(zones: zones) }
                if !detectedClimbs.isEmpty {
                    climbsCard
                }
                if hasGPS {
                    cardWrapper(label: "CARTE DU TRAJET") {
                        // Highlight the selected climb's GPS segment on the
                        // map so the user can locate it without scrolling
                        // back up to the chart. Tap a climb row in the
                        // Climbs card → segment lights up here.
                        RouteAnalysisMap(
                            activity: activity,
                            highlightSegment: selectedClimbIdx.flatMap { idx in
                                guard detectedClimbs.indices.contains(idx) else { return nil }
                                let c = detectedClimbs[idx]
                                return (startIdx: c.startIndex, endIdx: c.endIndex)
                            },
                        )
                    }
                }
                summaryRow
                effortMetricsCard
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .background(AppColors.cream)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                BrandLockup(compact: true)
            }
            // Trash icon only for local rides (negative id = recorded
            // by Track or saved at the end of Naviguer). Strava-sourced
            // rides should be deleted on Strava, not here.
            if isLocalRide {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .toolbarTitleDisplayMode(.inline)
        .alert("Supprimer cette sortie ?", isPresented: $showDeleteConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) {
                deleteLocalRide()
            }
        } message: {
            Text("La sortie sera retirée de Petit Explorer (le workout dans l'app Santé reste, supprime-le là-bas si tu veux).")
        }
        .onAppear {
            // Build chartData + derive hrRange once. This is the heavy
            // PowerStream pipeline (gradient + power model on the raw
            // 1Hz streams), and before this cache it was re-running on
            // every frame of a chart drag.
            if chartData.isEmpty {
                chartData = PowerStream.build(from: activity)
                cachedHrRange = computeHrRange()
            }
            if detectedClimbs.isEmpty,
               let alt = activity.altitude,
               let dist = activity.distanceM {
                detectedClimbs = ClimbDetector.detect(
                    altitude: alt,
                    distanceM: dist,
                    timeS: activity.timeS,
                )
            }
            // Pre-warm the haptic engine so the first tick has zero
            // perceptible latency.
            haptics.prepare()
        }
        .onChange(of: selectedDist) { _, newValue in
            if newValue != nil {
                haptics.impactOccurred()
            }
        }
    }

    private var hasInteractiveCharts: Bool {
        !chartData.isEmpty
    }

    /// A near-zero-distance drag gesture used as a fast-path "I'm being
    /// touched" signal for a chart. We piggyback alongside Swift Charts'
    /// own .chartXSelection via .simultaneousGesture so the X value is
    /// still updated normally, while we capture which chart was the
    /// source of the touch and surface the scrub card right next to it.
    /// Guard against redundant state writes — onChanged fires ~60 Hz
    /// during a drag, so only assign when activeChart actually changes.
    private func activationGesture(for kind: ChartKind) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if activeChart != kind { activeChart = kind }
            }
    }

    /// Render the scrub card right above the chart the user is touching.
    /// Returns an empty view for the other three slots so the layout
    /// only has one card at a time.
    @ViewBuilder
    private func scrubCardSlot(for kind: ChartKind) -> some View {
        if activeChart == kind, hasInteractiveCharts, let s = selectedPoint {
            scrubCard(point: s)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// Sticky readout card that surfaces every meaningful value at the
    /// currently-dragged X position. Replaces the per-chart annotation
    /// tooltips with one always-visible card above the chart stack, so
    /// the user gets a coherent multi-metric snapshot no matter which
    /// chart their finger is on.
    private func scrubCard(point: ChartPoint) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%.2f", point.distKm))
                    .font(.system(size: 28, design: .serif).weight(.heavy))
                    .foregroundStyle(AppColors.ink)
                    .monospacedDigit()
                Text("km")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.inkLight)
                Spacer()
                let signed = point.gradientPct >= 0
                    ? String(format: "+%.1f %%", point.gradientPct)
                    : String(format: "%.1f %%", point.gradientPct)
                Text(signed)
                    .font(.system(size: 12, design: .serif).weight(.bold))
                    .foregroundStyle(point.gradientPct >= 0 ? AppColors.terra : AppColors.blue)
                    .monospacedDigit()
            }

            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading)], spacing: 8) {
                if let hr = point.heartRate {
                    scrubStat(label: "FC", value: "\(Int(hr.rounded()))", unit: "bpm", color: AppColors.terra)
                }
                if let speed = point.speedKmh {
                    scrubStat(label: "VITESSE", value: String(format: "%.1f", speed), unit: "km/h", color: AppColors.blue)
                }
                if point.power > 0 {
                    scrubStat(label: "PUISSANCE", value: "\(point.power)", unit: "W", color: AppColors.green)
                }
                if let alt = point.altitude {
                    scrubStat(label: "ALTITUDE", value: "\(Int(alt.rounded()))", unit: "m", color: AppColors.terra)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppColors.terra.opacity(0.5), lineWidth: 1.5))
    }

    private func scrubStat(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9).weight(.bold))
                .tracking(1.2)
                .foregroundStyle(AppColors.inkLight)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 18, design: .serif).weight(.heavy))
                    .foregroundStyle(color)
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.inkLight)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                sportPill
                Text("\(activity.date) · \(activity.location ?? "—")")
                    .font(.system(size: 10).weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(AppColors.inkLight)
                Spacer(minLength: 0)
            }
            Text(activity.title)
                .font(.system(size: 30, design: .serif).weight(.heavy))
                .foregroundStyle(AppColors.ink)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sportPill: some View {
        let sport = Sport(backendType: activity.type)
        let label = sport?.displayName.uppercased() ?? activity.type.uppercased()
        return HStack(spacing: 5) {
            Image(systemName: sport?.symbol ?? "figure.run").font(.system(size: 10))
            Text(label).font(.system(size: 10).weight(.bold)).tracking(1.2)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(sport?.color ?? AppColors.terra, in: Capsule())
        .foregroundStyle(.white)
    }

    // MARK: - Top stats card

    private var topStatsCard: some View {
        cardWrapper(label: nil) {
            LazyVGrid(columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading),
            ], alignment: .leading, spacing: 14) {
                statCell(label: "DURÉE", value: activity.duration, unit: nil)
                statCell(label: "DISTANCE", value: activity.distance.map { String(format: "%.2f", $0) }, unit: "km")
                statCell(label: speedLabel, value: speedValue, unit: speedUnit)
                statCell(label: "MAX", value: activity.maxSpeed.map { String(format: "%.1f", $0) }, unit: "km/h")
                statCell(label: "MONTÉE", value: activity.elevation.map { String(format: "%.1f", $0) }, unit: "m")
                statCell(label: "FC MOY", value: activity.avgHr.map { String(format: "%.1f", $0) }, unit: "bpm")
                statCell(label: "FC MAX", value: activity.maxHr.map(String.init), unit: "bpm")
                statCell(label: "CALORIES", value: activity.calories.map(String.init), unit: "kcal")
            }
        }
    }

    private var speedLabel: String { activity.type == "running" ? "ALLURE" : "MOY" }
    private var speedUnit: String? { activity.type == "running" ? "/km" : "km/h" }
    private var speedValue: String? {
        if activity.type == "running", let pace = activity.paceSPerKm {
            return String(format: "%d:%02d", pace / 60, pace % 60)
        }
        return activity.speed.map { String(format: "%.1f", $0) }
    }

    // MARK: - FTP banner

    private var ftpCard: some View {
        let ftp = activity.ftp ?? PowerStream.fallbackFtp
        let riderKg = activity.riderKg ?? PowerStream.fallbackRiderKg
        let wkg = (Double(ftp) / riderKg * 100).rounded() / 100
        return HStack(spacing: 4) {
            Rectangle().fill(AppColors.terra).frame(width: 4)
            VStack(alignment: .leading, spacing: 12) {
                Text("FTP ESTIMÉ")
                    .font(.system(size: 10).weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(AppColors.inkLight)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(ftp)")
                        .font(.system(size: 36, design: .serif).weight(.heavy))
                        .foregroundStyle(AppColors.ink)
                    Text("W")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.inkLight)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Formule : best 20 min × 0,95 (Coggan)")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.inkMid)
                    HStack(spacing: 4) {
                        Text("FTP =")
                        Text("\(ftp) W").foregroundStyle(AppColors.terra).fontWeight(.bold)
                        Text("·")
                        Text("\(Int(riderKg)) kg → \(String(format: "%.2f", wkg)) W/kg")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.inkMid)
                    Text("Calculée depuis tes meilleures sorties non assistées · pour mesurer (vs estimer), un capteur de puissance est nécessaire.")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.inkLight)
                        .lineSpacing(2)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - HR + Slope chart (dual axis)
    //
    // Y axis is shared between two unrelated series (HR bpm + slope %).
    // Swift Charts only supports one Y scale natively, so we map slope
    // values into HR coordinate space (slopeMin → hrMin, slopeMax → hrMax,
    // 0% → midpoint) and re-label the trailing axis with the original
    // slope percentages. Same trick the web's Recharts does with `yAxisId`.
    //
    // hrMin / hrMax are derived from the activity's actual HR range
    // (rounded to the nearest 10, with a sensible floor/ceiling) so a
    // chill ride at 90-140 bpm doesn't get crammed into the bottom of
    // a 120-200 fixed window. Slope domain stays ±25 % regardless so
    // bars are always proportional to a real gradient scale.

    private static let slopeMin: Double = -25
    private static let slopeMax: Double = 25

    /// Range of HR values observed in this ride, padded out to the
    /// nearest 10 bpm so axis labels read nicely. Returns the cached
    /// value computed once in onAppear so we never scan chartData on
    /// the drag hot path.
    private var hrRange: (min: Double, max: Double) {
        cachedHrRange
    }

    /// Remove this ride from the LocalRideStore + dismiss the view.
    /// Only called for local (negative-id) rides — the toolbar button
    /// that triggers it is hidden for Strava-sourced rides.
    private func deleteLocalRide() {
        environment.localRides.remove(id: activity.id, for: environment.currentUser)
        environment.activityStore.refreshLocal(user: environment.currentUser)
        Log.tracking.notice("deleted local ride id=\(activity.id)")
        dismiss()
    }

    /// Computed once after chartData is built. Mirrors the previous
    /// inline logic but uses the cached chartData reference.
    private func computeHrRange() -> (min: Double, max: Double) {
        let values = chartData.compactMap(\.heartRate)
        guard let lo = values.min(), let hi = values.max(), hi > lo else {
            return (80, 200)
        }
        let pad = max(5.0, (hi - lo) * 0.08)
        let minBpm = max(40, floor((lo - pad) / 10) * 10)
        let maxBpm = min(220, ceil((hi + pad) / 10) * 10)
        return (minBpm, maxBpm)
    }

    private var hrAxisTicks: [Double] {
        let r = hrRange
        let step = (r.max - r.min) / 4
        return stride(from: r.min, through: r.max, by: step).map { $0 }
    }

    /// Map a slope % into the chart's HR coordinate space. 0 % slope
    /// sits at the midpoint of the current HR range so bars are visually
    /// balanced regardless of the rider's HR window.
    private func slopeToHr(_ slope: Double) -> Double {
        let r = hrRange
        let t = (slope - Self.slopeMin) / (Self.slopeMax - Self.slopeMin)
        return r.min + t * (r.max - r.min)
    }

    private var slopeBaselineHr: Double {
        let r = hrRange
        return (r.min + r.max) / 2
    }

    private var hrSlopeChart: some View {
        let range = hrRange
        let baseline = slopeBaselineHr
        return cardWrapper(label: "FRÉQUENCE CARDIAQUE · INCLINAISON") {
            Chart {
                ForEach(chartData) { p in
                    if p.gradientPct != 0 {
                        let mappedY = slopeToHr(p.gradientPct)
                        BarMark(
                            x: .value("km", p.distKm),
                            yStart: .value("base", baseline),
                            yEnd: .value("slope", mappedY),
                            width: .fixed(2),
                        )
                        .foregroundStyle(p.gradientPct > 0
                            ? AppColors.terra.opacity(0.6)
                            : AppColors.blue.opacity(0.6))
                    }
                }
                ForEach(chartData) { p in
                    if let hr = p.heartRate {
                        LineMark(
                            x: .value("km", p.distKm),
                            y: .value("FC", hr),
                            series: .value("series", "hr"),
                        )
                        .foregroundStyle(AppColors.terra)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                    }
                }
                if let s = selectedPoint {
                    RuleMark(x: .value("km", s.distKm))
                        .foregroundStyle(AppColors.terra.opacity(0.75))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    if let hr = s.heartRate {
                        PointMark(x: .value("km", s.distKm), y: .value("FC", hr))
                            .foregroundStyle(AppColors.terra)
                            .symbolSize(90)
                            .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit, y: .disabled)) {
                                tooltipBox(km: s.distKm, lines: [
                                    ("Montée (%)", String(format: "%.1f", max(s.gradientPct, 0)), AppColors.terra),
                                    ("Descente (%)", String(format: "%.1f", min(s.gradientPct, 0)), AppColors.blue),
                                    ("FC (bpm)", "\(Int(hr.rounded()))", AppColors.terra),
                                ])
                            }
                    }
                }
            }
            .frame(height: 240)
            .chartXScale(domain: 0...maxDistKm)
            .chartYScale(domain: range.min...range.max)
            .chartXSelection(value: $selectedDist)
            .simultaneousGesture(activationGesture(for: .hr))
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().font(.system(size: 9)) }
            }
            .chartYAxis {
                // Leading axis: HR values (bpm), derived from the ride's data.
                AxisMarks(position: .leading, values: hrAxisTicks) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))").font(.system(size: 9))
                        }
                    }
                    AxisGridLine().foregroundStyle(AppColors.creamBorder)
                }
                // Trailing axis: re-label the same ticks with the slope %
                // each one represents in our linear mapping.
                AxisMarks(position: .trailing, values: hrAxisTicks) { value in
                    AxisValueLabel {
                        if let hr = value.as(Double.self) {
                            let t = (hr - range.min) / (range.max - range.min)
                            let slope = Self.slopeMin + t * (Self.slopeMax - Self.slopeMin)
                            let formatted = abs(slope) < 0.5 ? "0" : String(format: "%+.0f%%", slope)
                            Text(formatted).font(.system(size: 9))
                        }
                    }
                }
            }
            chartLegend(items: [
                (AppColors.terra, "FC (bpm)"),
                (AppColors.terra.opacity(0.6), "Montée"),
                (AppColors.blue.opacity(0.6), "Descente"),
            ])
        }
    }

    // MARK: - Speed chart

    private var speedChart: some View {
        cardWrapper(label: "VITESSE (KM/H)") {
            Chart {
                ForEach(chartData) { p in
                    if let speed = p.speedKmh {
                        AreaMark(
                            x: .value("km", p.distKm),
                            y: .value("vitesse", speed),
                        )
                        .foregroundStyle(LinearGradient(
                            colors: [AppColors.blue.opacity(0.45), AppColors.blue.opacity(0)],
                            startPoint: .top, endPoint: .bottom,
                        ))
                        LineMark(
                            x: .value("km", p.distKm),
                            y: .value("vitesse", speed),
                        )
                        .foregroundStyle(AppColors.blue)
                        .interpolationMethod(.catmullRom)
                    }
                }
                if let s = selectedPoint, let speed = s.speedKmh {
                    RuleMark(x: .value("km", s.distKm))
                        .foregroundStyle(AppColors.ink.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    PointMark(x: .value("km", s.distKm), y: .value("vitesse", speed))
                        .foregroundStyle(AppColors.blue)
                        .symbolSize(80)
                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit, y: .disabled)) {
                            tooltipBox(km: s.distKm, lines: [
                                ("Vitesse", String(format: "%.1f km/h", speed), AppColors.blue),
                            ])
                        }
                }
            }
            .frame(height: 200)
            .chartXScale(domain: 0...maxDistKm)
            .chartXSelection(value: $selectedDist)
            .simultaneousGesture(activationGesture(for: .speed))
            .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.system(size: 9)) } }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel().font(.system(size: 9))
                    AxisGridLine().foregroundStyle(AppColors.creamBorder)
                }
            }
        }
    }

    // MARK: - Power chart

    private var powerChart: some View {
        cardWrapper(label: "PUISSANCE ESTIMÉE (W)") {
            Chart {
                ForEach(chartData) { p in
                    AreaMark(
                        x: .value("km", p.distKm),
                        y: .value("W", p.power),
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [AppColors.green.opacity(0.5), AppColors.green.opacity(0)],
                        startPoint: .top, endPoint: .bottom,
                    ))
                    LineMark(
                        x: .value("km", p.distKm),
                        y: .value("W", p.power),
                    )
                    .foregroundStyle(AppColors.green)
                    .interpolationMethod(.catmullRom)
                }
                if let s = selectedPoint {
                    RuleMark(x: .value("km", s.distKm))
                        .foregroundStyle(AppColors.ink.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    PointMark(x: .value("km", s.distKm), y: .value("W", s.power))
                        .foregroundStyle(AppColors.green)
                        .symbolSize(80)
                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit, y: .disabled)) {
                            tooltipBox(km: s.distKm, lines: [
                                ("Puissance", "\(s.power) W", AppColors.green),
                                ("Pente", String(format: "%+.1f %%", s.gradientPct), AppColors.inkMid),
                            ])
                        }
                }
            }
            .frame(height: 200)
            .chartXScale(domain: 0...maxDistKm)
            .chartXSelection(value: $selectedDist)
            .simultaneousGesture(activationGesture(for: .power))
            .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.system(size: 9)) } }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel().font(.system(size: 9))
                    AxisGridLine().foregroundStyle(AppColors.creamBorder)
                }
            }
            Text("Glisse ton doigt → détail des forces (gravité, roulement, aéro) à chaque km.")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.inkLight)
                .lineSpacing(2)
        }
    }

    // MARK: - Elevation chart

    private var elevationChart: some View {
        cardWrapper(label: "PROFIL D'ALTITUDE") {
            Chart {
                ForEach(chartData) { p in
                    if let alt = p.altitude {
                        AreaMark(
                            x: .value("km", p.distKm),
                            y: .value("alt", alt),
                        )
                        .foregroundStyle(LinearGradient(
                            colors: [AppColors.terra.opacity(0.4), AppColors.terra.opacity(0)],
                            startPoint: .top, endPoint: .bottom,
                        ))
                        LineMark(
                            x: .value("km", p.distKm),
                            y: .value("alt", alt),
                        )
                        .foregroundStyle(AppColors.terra)
                        .interpolationMethod(.catmullRom)
                    }
                }
                if let s = selectedPoint, let alt = s.altitude {
                    RuleMark(x: .value("km", s.distKm))
                        .foregroundStyle(AppColors.ink.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    PointMark(x: .value("km", s.distKm), y: .value("alt", alt))
                        .foregroundStyle(AppColors.terra)
                        .symbolSize(80)
                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit, y: .disabled)) {
                            tooltipBox(km: s.distKm, lines: [
                                ("Altitude", "\(Int(alt.rounded())) m", AppColors.terra),
                            ])
                        }
                }
            }
            .frame(height: 180)
            .chartXScale(domain: 0...maxDistKm)
            .chartXSelection(value: $selectedDist)
            .simultaneousGesture(activationGesture(for: .altitude))
            .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.system(size: 9)) } }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel().font(.system(size: 9))
                    AxisGridLine().foregroundStyle(AppColors.creamBorder)
                }
            }
        }
    }

    // MARK: - Tooltip box (shared by all 4 charts)

    private func tooltipBox(km: Double, lines: [(String, String, Color)]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.2f km", km))
                .font(.system(size: 10).weight(.semibold))
                .tracking(0.4)
                .foregroundStyle(AppColors.inkLight)
            ForEach(lines.indices, id: \.self) { i in
                HStack(spacing: 4) {
                    Text(lines[i].0).foregroundStyle(AppColors.inkMid)
                    Text(":")
                    Text(lines[i].1).foregroundStyle(lines[i].2).bold()
                }
                .font(.system(size: 11))
                .monospacedDigit()
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
    }

    // MARK: - Climbs

    /// Card listing all detected climbs on this ride. Each row shows
    /// length, elevation gain, avg/max grade, and time. Tap row to
    /// jump the chart selection to the climb's distance position
    /// (so the user sees the elevation profile of that climb).
    private var climbsCard: some View {
        cardWrapper(label: "MONTÉES DÉTECTÉES") {
            VStack(spacing: 10) {
                ForEach(Array(detectedClimbs.enumerated()), id: \.offset) { idx, climb in
                    Button {
                        // Center the chart scrub on this climb's midpoint.
                        let midDistKm = chartData.indices.contains(climb.startIndex)
                            ? chartData[climb.startIndex].distKm
                            : 0
                        selectedDist = midDistKm
                        activeChart = .altitude
                        // Toggle the map highlight — tap a row to light
                        // up the GPS segment on the map below; tap
                        // again to dismiss.
                        selectedClimbIdx = (selectedClimbIdx == idx) ? nil : idx
                    } label: {
                        climbRow(idx: idx + 1, climb: climb, selected: selectedClimbIdx == idx)
                    }
                    .buttonStyle(.plain)
                    if idx < detectedClimbs.count - 1 {
                        Divider().background(AppColors.creamBorder)
                    }
                }

                // NB explaining the strict thresholds — same wording as
                // the web AnalysisPage. Visible at the bottom of every
                // climbs card so a missing kicker isn't read as a bug.
                Divider().background(AppColors.creamBorder).padding(.top, 4)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("NB —")
                            .font(.system(size: 11).weight(.bold))
                            .foregroundStyle(AppColors.inkMid)
                        Text("seuils volontairement stricts")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.inkLight)
                    }
                    Text("≥ 500 m, ≥ 30 m de gain, ≥ 3 % de pente moyenne. Les petits raidards (kickers < 500 m, même à 8-10 %) sont délibérément ignorés pour ne lister que les vraies montées. Altitude lissée sur 30 pts ; pente max sur fenêtre glissante 100 m.")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.inkLight)
                        .lineSpacing(2)
                }
            }
        }
    }

    private func climbRow(idx: Int, climb: Climb, selected: Bool = false) -> some View {
        HStack(spacing: 14) {
            // Numbered chevron pill — the visual marker for "this is
            // climb N on the ride".
            ZStack {
                Circle().fill(AppColors.terra).frame(width: 30, height: 30)
                Text("\(idx)")
                    .font(.system(size: 13).weight(.heavy))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(climb.name)
                        .font(.system(.body, design: .serif).weight(.bold))
                        .foregroundStyle(AppColors.ink)
                    Spacer(minLength: 0)
                    Text(formatClimbDuration(climb.durationSec))
                        .font(.system(size: 11).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppColors.inkMid)
                }
                HStack(spacing: 12) {
                    climbStat(value: formatClimbDistance(climb.distanceM), label: "long.")
                    climbStat(value: "\(Int(climb.elevationM.rounded())) m", label: "D+")
                    climbStat(value: String(format: "%.1f%%", climb.avgGradePct), label: "moy.")
                    climbStat(value: String(format: "%.1f%%", climb.maxGradePct), label: "max")
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, selected ? 8 : 0)
        // Selected state: subtle terra-tinted background + outline so
        // the user sees which row currently maps to the highlighted
        // segment below. Animated so toggling reads smoothly.
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(selected ? AppColors.terra.opacity(0.08) : Color.clear),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(selected ? AppColors.terra : Color.clear, lineWidth: 1.5),
        )
        .animation(.easeInOut(duration: 0.18), value: selected)
    }

    private func climbStat(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value).font(.system(size: 12).weight(.bold)).monospacedDigit().foregroundStyle(AppColors.ink)
            Text(label).font(.system(size: 9)).foregroundStyle(AppColors.inkLight)
        }
    }

    private func formatClimbDistance(_ m: Double) -> String {
        m >= 1000 ? String(format: "%.1f km", m / 1000) : "\(Int(m.rounded())) m"
    }

    private func formatClimbDuration(_ sec: Double) -> String {
        guard sec > 0 else { return "—" }
        let s = Int(sec.rounded())
        let h = s / 3600
        let m = (s % 3600) / 60
        let r = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, r) : String(format: "%d:%02d", m, r)
    }

    // MARK: - HR Zones

    private func hrZonesCard(zones: HRZones) -> some View {
        let rows: [(String, String, Double, Color)] = [
            ("Z1 — Récupération", "< 136 bpm", zones.z1, AppColors.blue),
            ("Z2 — Endurance",    "137–149 bpm", zones.z2, AppColors.green),
            ("Z3 — Tempo",        "150–162 bpm", zones.z3, AppColors.terra),
            ("Z4 — Seuil",        "163–175 bpm", zones.z4, Color(hex: "E07030")),
            ("Z5 — VO₂max",       "> 176 bpm",   zones.z5, Color(hex: "CC3333")),
        ]
        let total = rows.reduce(0) { $0 + $1.2 }
        return cardWrapper(label: "ZONES FC — TEMPS PASSÉ") {
            VStack(spacing: 12) {
                ForEach(rows.indices, id: \.self) { i in
                    let (label, bpm, val, color) = rows[i]
                    let pct = total > 0 ? val / total * 100 : 0
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(label)
                                .font(.system(size: 11).weight(.semibold))
                                .foregroundStyle(AppColors.inkMid)
                            Text(bpm)
                                .font(.system(size: 10))
                                .foregroundStyle(AppColors.inkLight)
                            Spacer()
                            HStack(spacing: 4) {
                                Text(String(format: "%.0f min", val))
                                Text("·")
                                Text(String(format: "%.0f%%", pct)).foregroundStyle(AppColors.ink).bold()
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.inkLight)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2).fill(AppColors.creamDark).frame(height: 7)
                                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: geo.size.width * pct / 100, height: 7)
                            }
                        }
                        .frame(height: 7)
                    }
                }
            }
        }
    }

    // MARK: - Summary cards row (VO2 + Power estimate)

    private var summaryRow: some View {
        VStack(spacing: 14) {
            if activity.maxHr != nil {
                Vo2MaxCard(activity: activity)
            }
            if hasPower {
                PowerSummaryCard(activity: activity, chartData: chartData)
            }
        }
    }

    // MARK: - Effort metrics

    private var effortMetricsCard: some View {
        guard activity.np != nil || activity.tss != nil || activity.trimp != nil else {
            return AnyView(EmptyView())
        }
        return AnyView(
            cardWrapper(label: "EFFORT & ÉNERGIE") {
                VStack(alignment: .leading, spacing: 18) {
                    metricsBlock(title: "PUISSANCE", color: AppColors.terra, rows: powerRows)
                    metricsBlock(title: "CARDIO", color: AppColors.blue, rows: cardioRows)
                    metricsBlock(title: "MÉCANIQUE & MÉTÉO", color: AppColors.green, rows: mechanicalRows)
                    if let weather = activity.weather {
                        weatherBlock(weather: weather)
                    }
                }
            },
        )
    }

    private struct MetricRow: Identifiable {
        let id = UUID()
        let key: String
        let value: String
        let unit: String?
        let tip: String?
    }

    private var powerRows: [MetricRow] {
        var rows: [MetricRow] = []
        if let np = activity.np { rows.append(MetricRow(key: "NP", value: "\(np)", unit: "W", tip: "Puissance normalisée")) }
        if let avg = activity.avgPower { rows.append(MetricRow(key: "AP", value: "\(avg)", unit: "W", tip: "Puissance moyenne brute")) }
        if let tss = activity.tss { rows.append(MetricRow(key: "TSS", value: "\(tss)", unit: nil, tip: "Charge totale de la sortie")) }
        if let f = activity.ifFactor { rows.append(MetricRow(key: "IF", value: String(format: "%.2f", f), unit: nil, tip: "Intensité relative au FTP")) }
        if let vi = activity.vi { rows.append(MetricRow(key: "VI", value: String(format: "%.1f", vi), unit: nil, tip: "Régularité de l'effort")) }
        if let wkg = activity.wkg { rows.append(MetricRow(key: "W/kg", value: String(format: "%.2f", wkg), unit: "W/kg", tip: "Puissance par kg")) }
        return rows
    }

    private var cardioRows: [MetricRow] {
        var rows: [MetricRow] = []
        if let trimp = activity.trimp { rows.append(MetricRow(key: "TRIMP", value: "\(trimp)", unit: nil, tip: "Charge cardiaque totale")) }
        if let ef = activity.ef { rows.append(MetricRow(key: "EF", value: String(format: "%.2f", ef), unit: "W/bpm", tip: "Efficacité aérobie")) }
        if let aed = activity.aed { rows.append(MetricRow(key: "AeD", value: String(format: "%.1f%%", aed), unit: nil, tip: "Dérive cardiaque")) }
        if let avgHr = activity.avgHr { rows.append(MetricRow(key: "FC moy", value: String(format: "%.1f", avgHr), unit: "bpm", tip: "Fréquence cardiaque moyenne")) }
        if let maxHr = activity.maxHr { rows.append(MetricRow(key: "FC max", value: "\(maxHr)", unit: "bpm", tip: "Fréquence max mesurée")) }
        return rows
    }

    private var mechanicalRows: [MetricRow] {
        var rows: [MetricRow] = []
        if let vam = activity.vam { rows.append(MetricRow(key: "VAM", value: "\(Int(vam.rounded()))", unit: "m/h", tip: "Vitesse ascensionnelle")) }
        if let max = activity.maxIncline { rows.append(MetricRow(key: "Pente max", value: String(format: "+%.1f", max), unit: "%", tip: "Inclinaison maximale")) }
        if let min = activity.minIncline { rows.append(MetricRow(key: "Pente min", value: String(format: "%.1f", min), unit: "%", tip: "Descente max")) }
        return rows
    }

    private func metricsBlock(title: String, color: Color, rows: [MetricRow]) -> some View {
        guard !rows.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 10).weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(color)
                ForEach(rows) { row in
                    metricRow(row)
                    Divider().background(AppColors.creamBorder)
                }
            },
        )
    }

    private func metricRow(_ row: MetricRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.key)
                    .font(.system(size: 11).weight(.bold))
                    .foregroundStyle(AppColors.inkMid)
                if let tip = row.tip {
                    Text(tip)
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.inkLight)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(row.value)
                    .font(.system(size: 22, design: .serif).weight(.heavy))
                    .foregroundStyle(AppColors.ink)
                    .monospacedDigit()
                if let unit = row.unit {
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.inkLight)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func weatherBlock(weather: Weather) -> some View {
        let temp = weather.temp.map { String(format: "%.0f°C", $0) } ?? "—"
        let wind = weather.windspeed.map { "\(Int($0)) km/h" } ?? "—"
        let hum = weather.humidity.map { "\($0)%" } ?? "—"
        let desc = weather.description ?? ""
        return VStack(alignment: .leading, spacing: 6) {
            Text("MÉTÉO DU JOUR")
                .font(.system(size: 10).weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(AppColors.inkLight)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(desc) · \(temp)")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.inkMid)
                Text("Vent \(wind) · Humidité \(hum)")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.inkMid)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.creamDark, in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Helpers

    @ViewBuilder
    private func cardWrapper<Content: View>(label: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let label {
                Text(label)
                    .font(.system(size: 10).weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(AppColors.inkLight)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    private func statCell(label: String, value: String?, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9).weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(AppColors.inkLight)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value ?? "—")
                    .font(.system(size: 22, design: .serif).weight(.heavy))
                    .foregroundStyle(AppColors.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit, value != nil {
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.inkLight)
                }
            }
        }
    }

    private func chartLegend(items: [(Color, String)]) -> some View {
        HStack(spacing: 14) {
            ForEach(items.indices, id: \.self) { i in
                HStack(spacing: 5) {
                    Rectangle().fill(items[i].0).frame(width: 12, height: 3)
                    Text(items[i].1).font(.system(size: 10)).foregroundStyle(AppColors.inkLight)
                }
            }
        }
    }
}

// MARK: - VO2 max card

private struct Vo2MaxCard: View {
    let activity: RideRecord
    @State private var hrRest: Double = 60

    var body: some View {
        let hrMax = activity.maxHr ?? 0
        let vo2 = hrMax > 0 ? ((15 * Double(hrMax) / hrRest) * 10).rounded() / 10 : 0
        let zone: (label: String, color: Color) = {
            if vo2 >= 55 { return ("Excellent", AppColors.green) }
            if vo2 >= 45 { return ("Bon", AppColors.blue) }
            if vo2 >= 35 { return ("Moyen", AppColors.terra) }
            return ("Faible", AppColors.inkLight)
        }()

        VStack(alignment: .leading, spacing: 14) {
            Text("VO₂ MAX ESTIMÉ")
                .font(.system(size: 10).weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(AppColors.inkLight)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(String(format: "%.1f", vo2))")
                    .font(.system(size: 42, design: .serif).weight(.heavy))
                    .foregroundStyle(AppColors.ink)
                Text("ml/kg/min")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.inkLight)
            }
            Text(zone.label.uppercased())
                .font(.system(size: 10).weight(.bold)).tracking(1.2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(zone.color, in: Capsule())
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 4) {
                Text("FC REPOS (BPM)")
                    .font(.system(size: 9).weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(AppColors.inkLight)
                HStack(spacing: 12) {
                    Slider(value: $hrRest, in: 40...90, step: 1)
                        .tint(AppColors.terra)
                    Text("\(Int(hrRest))")
                        .font(.system(size: 18, design: .serif).weight(.bold))
                        .foregroundStyle(AppColors.ink)
                        .frame(minWidth: 28, alignment: .trailing)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Formule : 15 × (FC max / FC repos)")
                Text("FC max mesurée : \(activity.maxHr.map { "\($0) bpm" } ?? "—")")
            }
            .font(.system(size: 11))
            .foregroundStyle(AppColors.inkLight)
            .lineSpacing(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }
}

// MARK: - Estimated power summary card

private struct PowerSummaryCard: View {
    let activity: RideRecord
    let chartData: [ChartPoint]

    var body: some View {
        let avg = chartData.isEmpty ? 0 : Int((Double(chartData.reduce(0) { $0 + $1.power }) / Double(chartData.count)).rounded())
        let max = chartData.map(\.power).max() ?? 0
        let totalKj = Double(avg) * Double(activity.durationMin) * 60 / 1000
        let rider = activity.riderKg ?? PowerStream.fallbackRiderKg
        let total = activity.totalMass ?? PowerStream.fallbackMass
        let bike = ((total - rider) * 100).rounded() / 100
        let fr = (total * PowerStream.g * PowerStream.crr * 10).rounded() / 10

        return VStack(alignment: .leading, spacing: 14) {
            Text("PUISSANCE ESTIMÉE")
                .font(.system(size: 10).weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(AppColors.inkLight)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(avg)")
                    .font(.system(size: 42, design: .serif).weight(.heavy))
                    .foregroundStyle(AppColors.ink)
                Text("watts moyens")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.inkLight)
            }
            HStack(spacing: 24) {
                stat(label: "MAX", value: "\(max)", unit: "W")
                stat(label: "TRAVAIL TOTAL", value: "\(Int(totalKj.rounded()))", unit: "kJ")
            }
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                Text("Formule : P = (F_gravité + F_roulement + F_aéro) × v")
                Text("Coureur : \(Int(rider)) kg · Vélo : \(String(format: "%.2f", bike)) kg · Total : \(String(format: "%.2f", total)) kg")
                HStack(spacing: 4) {
                    Text("F_roulement").foregroundStyle(AppColors.terra)
                    Text("= \(String(format: "%.2f", total)) × 9,81 × 0,004 = ")
                    Text("\(String(format: "%.1f", fr)) N").foregroundStyle(AppColors.ink).bold()
                    Text("(constant)")
                }
                HStack(spacing: 4) {
                    Text("F_gravité").foregroundStyle(AppColors.terra)
                    Text("= \(String(format: "%.2f", total)) × 9,81 × pente → varie")
                }
                HStack(spacing: 4) {
                    Text("F_aéro").foregroundStyle(AppColors.terra)
                    Text("= 0,5 × 1,225 × 0,3 × v² → varie")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(AppColors.inkMid)
            .lineSpacing(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppColors.creamBorder, lineWidth: 1))
    }

    private func stat(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9).weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(AppColors.inkLight)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 18, design: .serif).weight(.bold))
                    .foregroundStyle(AppColors.ink)
                    .monospacedDigit()
                Text(unit).font(.system(size: 10)).foregroundStyle(AppColors.inkLight)
            }
        }
    }
}
