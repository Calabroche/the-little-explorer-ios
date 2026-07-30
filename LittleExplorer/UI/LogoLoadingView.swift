import SwiftUI

/// Branded loading screen: the compass mark + "The Little Explorer" wordmark
/// gently pulsing (scale + opacity) on the cream background. Shown while a
/// detail view assembles its heavy pipeline (charts, climbs, media), so the
/// wait reads as intentional instead of a frozen blank.
struct LogoLoadingView: View {
    /// Optional caption under the wordmark (e.g. "Chargement de la sortie…").
    var caption: String? = nil

    @State private var pulse = false

    var body: some View {
        ZStack {
            AppColors.cream.ignoresSafeArea()

            VStack(spacing: 16) {
                // Compass mark — the brand glyph. Scales + fades in a loop.
                Image(systemName: "location.north.circle.fill")
                    .font(.system(size: 52, weight: .regular))
                    .foregroundStyle(AppColors.terra)
                    .scaleEffect(pulse ? 1.14 : 0.86)
                    .opacity(pulse ? 1.0 : 0.55)
                    .shadow(color: AppColors.terra.opacity(pulse ? 0.28 : 0.0), radius: pulse ? 16 : 0)

                // Wordmark, "Explorer" italic terra like the web logo.
                VStack(spacing: -2) {
                    Text("The Little")
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .foregroundStyle(AppColors.ink)
                    Text("Explorer")
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .italic()
                        .foregroundStyle(AppColors.terra)
                }
                .opacity(pulse ? 1.0 : 0.7)

                if let caption {
                    Text(caption)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.inkLight)
                        .padding(.top, 2)
                        .opacity(pulse ? 1.0 : 0.6)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
