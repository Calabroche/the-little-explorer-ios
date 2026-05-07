import SwiftUI

struct ProfileView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        NavigationStack {
            Form {
                Section("Rider") {
                    Picker("User", selection: bindingForUser()) {
                        ForEach(AppUser.allCases) { user in
                            Text(user.displayName).tag(user)
                        }
                    }
                }
                Section("Backend") {
                    LabeledContent("API", value: "the-little-explorer-app.vercel.app")
                }
                Section("Apple Watch") {
                    LabeledContent("Paired", value: environment.watch.isPaired ? "Yes" : "No")
                    LabeledContent("Reachable", value: environment.watch.isReachable ? "Yes" : "No")
                }
                Section("About") {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Profile")
        }
    }

    private func bindingForUser() -> Binding<AppUser> {
        Binding(
            get: { environment.currentUser },
            set: { environment.currentUser = $0 },
        )
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }
}
