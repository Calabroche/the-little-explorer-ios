import SwiftUI

/// A cyclist who keeps pedalling — replaces the old static bicycle on the
/// home screen. The figure bobs forward with a repeating motion and a
/// gentle lean so it reads as "someone riding" rather than a frozen icon.
struct PedalingCyclist: View {
    @State private var riding = false

    var body: some View {
        Image(systemName: "figure.outdoor.cycle")
            .font(.system(size: 42, weight: .semibold))
            .foregroundStyle(.tint)
            .symbolEffect(.bounce, options: .repeating)
            .rotationEffect(.degrees(riding ? 4 : -4), anchor: .bottom)
            .offset(y: riding ? -2 : 2)
            .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true), value: riding)
            .onAppear { riding = true }
            .accessibilityLabel("Cycliste qui pédale")
    }
}
