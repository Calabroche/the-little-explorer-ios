import SwiftUI

struct WatchRootView: View {
    @Environment(WorkoutManager.self) private var workoutManager

    var body: some View {
        if workoutManager.isActive {
            RideView()
        } else {
            StartView()
        }
    }
}

private struct StartView: View {
    @Environment(WorkoutManager.self) private var workoutManager

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bicycle")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
            Text("Little Explorer")
                .font(.headline)
            Button {
                Task { await workoutManager.start() }
            } label: {
                Label("Start ride", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
