import Foundation

/// One real-user API-timing sample from the iOS app (mirrors the web
/// PerfCollector). Sent to POST /api/perf and read back on /admin/perf, so the
/// performance dashboard tracks iOS loading speed alongside the web.
struct PerfSample: Sendable {
    let label: String   // normalized route, e.g. /api/users/:id
    let ms: Double
    let status: Int
}

/// Response of GET /api/admin/perf.
struct AdminPerf: Decodable, Sendable {
    let window: String
    let totalSamples: Int
    let api: [PerfStat]
    let nav: [PerfStat]
    let vital: [PerfStat]
}
struct PerfStat: Decodable, Sendable, Identifiable {
    let label: String
    let count: Int
    let p50: Int
    let p95: Int
    let avg: Int
    let max: Int
    let errorRate: Int
    var id: String { label }
}

/// Buffers API-timing samples and flushes them to the server in batches.
actor PerfTracker {
    static let shared = PerfTracker()
    private var buffer: [PerfSample] = []

    func record(_ s: PerfSample) {
        // Never track the perf endpoint itself (feedback loop).
        if s.label.contains("/api/perf") { return }
        buffer.append(s)
        if buffer.count >= 12 { flush() }
    }

    /// Flush whatever's buffered (called on batch-full and on background).
    func flush() {
        guard !buffer.isEmpty else { return }
        let batch = buffer
        buffer = []
        Task { await APIClient.shared.sendPerfSamples(batch) }
    }

    /// Collapse ids/uuids in a path to `:id` so routes aggregate (matches the
    /// web collector's labels).
    static func normalize(_ path: String) -> String {
        let uuid = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map { seg -> String in
            let s = String(seg)
            if !s.isEmpty && s.allSatisfy(\.isNumber) { return ":id" }
            if (try? uuid.wholeMatch(in: s)) != nil { return ":id" }
            return s
        }
        return parts.joined(separator: "/")
    }
}
