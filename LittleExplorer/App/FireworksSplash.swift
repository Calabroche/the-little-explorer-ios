import SwiftUI

/// Full-screen launch splash: a dark backdrop so the fireworks pop, the
/// app wordmark, and the shared `FireworksView` running for ~5 seconds.
/// RootView fades it out once the timer elapses.
struct FireworksSplash: View {
    var body: some View {
        ZStack {
            AppColors.ink.ignoresSafeArea()
            FireworksView(intensity: 1.5, duration: 5)
                .ignoresSafeArea()
            VStack(spacing: 2) {
                Text("The Little")
                    .font(.system(.largeTitle, design: .serif).weight(.black))
                    .foregroundStyle(.white)
                Text("Explorer")
                    .font(.system(.largeTitle, design: .serif).weight(.black).italic())
                    .foregroundStyle(AppColors.terra)
            }
        }
    }
}
