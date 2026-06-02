import HealthKit

/// Sports the rider can pick from the watchOS home screen before
/// starting a workout.
///
/// Each case carries everything `WorkoutManager.start()` needs to
/// configure HealthKit (HKWorkoutActivityType + indoor/outdoor) plus
/// the metadata the home picker uses to render it (label + SF Symbol)
/// and the sport string we stamp on the resulting PendingRide so the
/// iPhone-side sync routes it to the correct TLE bucket.
///
/// Adding a sport: append a case, add the matching meta in `meta`,
/// and (if it should be routed to a new TLE SportId server-side)
/// update the sportFromType mapping in /api/strava/sync. The list is
/// rendered in `WatchSport.allCases` order — keep cycling / running
/// at the top since those are the most-frequent rides for our riders.
enum WatchSport: String, CaseIterable, Identifiable, Hashable {
    // ── Outdoor cardio ────────────────────────────────────────────
    case cyclingOutdoor
    case running
    case walking
    case hiking
    // ── Snow / water ──────────────────────────────────────────────
    case swimOpenWater
    case skiAlpine
    case skiNordic
    case snowboard
    // ── Indoor / strength / body ─────────────────────────────────
    case cyclingIndoor
    case runningIndoor
    case rowingIndoor
    case elliptical
    case stairs
    case yoga
    case pilates
    case strength               // Functional strength training
    case crossfit               // HighIntensityIntervalTraining
    case mixedCardio
    // ── Other ─────────────────────────────────────────────────────
    case other

    var id: String { rawValue }

    /// Display metadata. Bundled in one struct so adding a sport is
    /// one edit per axis (config / label / icon).
    struct Meta {
        let label:        String                          // FR label shown on the picker row
        let symbol:       String                          // SF Symbol
        let hk:           HKWorkoutActivityType
        let location:     HKWorkoutSessionLocationType
        /// Sport string written into PendingRide.sport and read on
        /// the iPhone side to route the resulting RideRecord. Must
        /// match a case the server's sportFromType() knows about
        /// (see /api/strava/sync/route.ts).
        let tleSport:     String
    }

    var meta: Meta {
        switch self {
        case .cyclingOutdoor: return Meta(label: "Vélo",          symbol: "bicycle",                            hk: .cycling,                       location: .outdoor, tleSport: "cycling")
        case .running:        return Meta(label: "Course",        symbol: "figure.run",                         hk: .running,                       location: .outdoor, tleSport: "running")
        case .walking:        return Meta(label: "Marche",        symbol: "figure.walk",                        hk: .walking,                       location: .outdoor, tleSport: "walking")
        case .hiking:         return Meta(label: "Rando",         symbol: "figure.hiking",                      hk: .hiking,                        location: .outdoor, tleSport: "hiking")
        case .swimOpenWater:  return Meta(label: "Nage",          symbol: "figure.pool.swim",                   hk: .swimming,                      location: .outdoor, tleSport: "swim")
        case .skiAlpine:      return Meta(label: "Ski alpin",     symbol: "figure.skiing.downhill",             hk: .downhillSkiing,                location: .outdoor, tleSport: "ski")
        case .skiNordic:      return Meta(label: "Ski de fond",   symbol: "figure.skiing.crosscountry",         hk: .crossCountrySkiing,            location: .outdoor, tleSport: "ski")
        case .snowboard:      return Meta(label: "Snowboard",     symbol: "figure.snowboarding",                hk: .snowboarding,                  location: .outdoor, tleSport: "snowboard")
        case .cyclingIndoor:  return Meta(label: "Vélo indoor",   symbol: "bicycle.circle",                     hk: .cycling,                       location: .indoor,  tleSport: "cycling")
        case .runningIndoor:  return Meta(label: "Tapis",         symbol: "figure.run",                         hk: .running,                       location: .indoor,  tleSport: "running")
        case .rowingIndoor:   return Meta(label: "Rameur",        symbol: "figure.rower",                       hk: .rowing,                        location: .indoor,  tleSport: "rowing")
        case .elliptical:     return Meta(label: "Elliptique",    symbol: "figure.elliptical",                  hk: .elliptical,                    location: .indoor,  tleSport: "cardio")
        case .stairs:         return Meta(label: "Stepper",       symbol: "figure.stairs",                      hk: .stairClimbing,                 location: .indoor,  tleSport: "cardio")
        case .yoga:           return Meta(label: "Yoga",          symbol: "figure.yoga",                        hk: .yoga,                          location: .indoor,  tleSport: "yoga")
        case .pilates:        return Meta(label: "Pilates",       symbol: "figure.pilates",                     hk: .pilates,                       location: .indoor,  tleSport: "yoga")
        case .strength:       return Meta(label: "Renforcement",  symbol: "figure.strengthtraining.functional", hk: .functionalStrengthTraining,    location: .indoor,  tleSport: "workout")
        case .crossfit:       return Meta(label: "Crossfit",      symbol: "figure.cross.training",              hk: .highIntensityIntervalTraining, location: .indoor,  tleSport: "workout")
        case .mixedCardio:    return Meta(label: "Cardio mix",    symbol: "figure.mixed.cardio",                hk: .mixedCardio,                   location: .indoor,  tleSport: "cardio")
        case .other:          return Meta(label: "Autre",         symbol: "ellipsis.circle",                    hk: .other,                         location: .outdoor, tleSport: "other")
        }
    }

    /// Default sport when the user starts an itinerary ride. Stays
    /// cycling because our itineraries are bike routes (planned via
    /// the web /planificateur using OSRM cycling profile).
    static let defaultForItinerary: WatchSport = .cyclingOutdoor
}
