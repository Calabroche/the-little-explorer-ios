import Foundation
import Observation

@Observable
final class AppEnvironment {
    var currentUser: AppUser = .florian

    let api = APIClient.shared
    let location = LocationManager()
    let watch = WatchSessionManager()
    let activityManager = RideActivityManager()
}
