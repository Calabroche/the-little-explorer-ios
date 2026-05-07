import SwiftUI

struct ActivitiesListView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = ActivitiesViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Activities")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Picker("User", selection: bindingForUser()) {
                            ForEach(AppUser.allCases) { user in
                                Text(user.displayName).tag(user)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .task { await viewModel.load(user: environment.currentUser) }
                .refreshable { await viewModel.load(user: environment.currentUser) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let msg):
            ContentUnavailableView(
                "Couldn't load activities",
                systemImage: "exclamationmark.triangle",
                description: Text(msg),
            )
        case .loaded:
            if viewModel.activities.isEmpty {
                ContentUnavailableView(
                    "No activities yet",
                    systemImage: "bicycle",
                    description: Text("Sync your rides from the web app."),
                )
            } else {
                List(viewModel.activities) { activity in
                    NavigationLink(value: activity) {
                        ActivityRow(activity: activity)
                    }
                }
                .navigationDestination(for: Activity.self) { activity in
                    ActivityDetailView(activity: activity)
                }
            }
        }
    }

    private func bindingForUser() -> Binding<AppUser> {
        Binding(
            get: { environment.currentUser },
            set: { newUser in
                environment.currentUser = newUser
                Task { await viewModel.load(user: newUser) }
            },
        )
    }
}

private struct ActivityRow: View {
    let activity: Activity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.sportSymbol)
                .font(.title2)
                .frame(width: 36, height: 36)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(activity.date)
                    if let distance = activity.distance {
                        Text("· \(String(format: "%.1f km", distance))")
                    }
                    Text("· \(activity.duration)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
