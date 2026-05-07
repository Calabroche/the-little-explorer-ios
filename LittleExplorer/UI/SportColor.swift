import SwiftUI

extension Sport {
    /// Editorial palette mapping — used to colour-code per-sport bars,
    /// polylines, and chart series. Mirrors the web's tokens choice.
    var color: Color {
        switch self {
        case .cycling:                          return AppColors.terra
        case .running, .ski, .snowshoe:         return AppColors.green
        case .hiking, .swim:                    return AppColors.blue
        case .walking:                          return AppColors.inkLight
        }
    }
}
