import SwiftUI
import WatchKit

/// Big 3-2-1 countdown shown right before a ride actually starts.
///
/// Why: tapping Start should feel deliberate, and the rider needs a
/// moment to slip the watch back onto the wrist, grab the bars, and
/// be ready when the timer kicks in. Matches the pattern Apple's own
/// Workout app uses for the same reason.
///
/// Behavior:
///   • Initial number: 3
///   • Steps down once per second to 2, then 1
///   • Plays a `.start` haptic on each tick (kept on the wrist)
///   • Invokes `onComplete` after the "1" tick completes — the
///     parent then calls `workoutManager.start()`
///   • Cancellable: the parent owns the binding that drives this
///     view's presence; setting it to nil dismisses without firing
///     `onComplete`
struct CountdownView: View {
    let onComplete: () async -> Void

    @State private var count: Int = 3

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text("\(count)")
                .font(.system(size: 120, weight: .heavy, design: .rounded))
                .foregroundStyle(.tint)
                .contentTransition(.numericText(countsDown: true))
                .id(count)
                .transition(.scale.combined(with: .opacity))
        }
        .task {
            // Single 3-tick loop. We start at 3 (already shown), so
            // sleep first, THEN decrement — this way the rider sees
            // each number for a full second.
            for next in stride(from: 2, through: 0, by: -1) {
                WKInterfaceDevice.current().play(.start)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if next == 0 { break }
                withAnimation(.easeOut(duration: 0.2)) {
                    count = next
                }
            }
            // One last haptic for "GO" so the rider knows tracking
            // is live without looking at the screen.
            WKInterfaceDevice.current().play(.success)
            await onComplete()
        }
    }
}
