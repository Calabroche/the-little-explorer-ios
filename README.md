# Little Explorer — iOS

Native iOS companion app for [The Little Explorer](https://the-little-explorer-app.vercel.app) — turn-by-turn cycling navigation, live ride tracking, Lock Screen Live Activity, and an Apple Watch companion.

## Stack

- **iOS 17+** / **watchOS 10+**
- **SwiftUI** + `@Observable` (no Combine, no third-party deps)
- **MapKit**, **CoreLocation**, **ActivityKit**, **WatchConnectivity**, **HealthKit** (Watch)
- Backend: existing Next.js API at `the-little-explorer-app.vercel.app`

## Targets

| Target | Bundle ID | Notes |
| --- | --- | --- |
| `LittleExplorer` | `com.calabrese.little-explorer-ios` | Main iOS app |
| `LittleExplorerLiveActivity` | `com.calabrese.little-explorer-ios.LiveActivity` | Lock Screen + Dynamic Island during rides |
| `LittleExplorerWatch` | `com.calabrese.little-explorer-ios.watchkitapp` | watchOS app — HKWorkoutSession + HR |

## Getting started

The Xcode project is generated from `project.yml` via [xcodegen](https://github.com/yonaskolb/XcodeGen). It is **not** checked in (see `.gitignore`).

```bash
brew install xcodegen
xcodegen generate
open LittleExplorer.xcodeproj
```

Then in Xcode:

1. Select the `LittleExplorer` scheme.
2. Pick a simulator (or your iPhone). Build and run.
3. To build the Watch app, select `LittleExplorerWatch` and choose a watch simulator.

## Project layout

```
project.yml                       # xcodegen spec (source of truth)
Shared/                           # Code shared by all 3 targets
  Models/                         # Activity, Coordinate, Route, User
  RideActivityAttributes.swift    # ActivityKit payload
  Formatters.swift
LittleExplorer/                   # Main iOS app
  App/                            # @main, RootView, AppEnvironment
  Features/
    Activities/                   # List + detail (calls /api/activities)
    Tracking/                     # Live ride recorder
    Planning/                     # BAN search + OSRM routing
    Navigation/                   # Turn-by-turn (uses Live Activity)
    Profile/                      # User picker, settings
  Services/                       # APIClient, LocationManager, RideActivityManager, WatchSessionManager
  Resources/                      # Assets, Info.plist (generated)
  Entitlements/
LittleExplorerLiveActivity/       # Widget extension (Live Activity only)
LittleExplorerWatch/              # watchOS app (single target)
.github/workflows/ios.yml         # CI: build on macOS runners
```

## Backend contract

All requests hit `https://the-little-explorer-app.vercel.app`. Endpoints used:

| Method | Path | Used for |
| --- | --- | --- |
| `GET` | `/api/activities?user=florian\|helena` | Activities list |
| `GET` | `/api/commune-search?q=...` or `?lat=&lng=` | Place search / reverse geocode |
| `POST` | `/api/elevation` | Elevation profile for a planned route |
| `POST` | `/api/route-bike` | OSRM cycling route + optional turn-by-turn steps |

See [`LittleExplorer/Services/APIClient.swift`](LittleExplorer/Services/APIClient.swift) for the typed client.

## What ships in v0

- Tab navigation: Activities · Track · Plan · Profile.
- Activities list + detail (map polyline + metrics grid + inline elevation chart).
- Live ride tracking: GPS path, distance/speed/elevation gain, Live Activity on Lock Screen + Dynamic Island.
- Route planning: BAN address search + OSRM cycling routes.
- Apple Watch app: HKWorkoutSession with HR + distance, two-page TabView (metrics / controls), reachable from iPhone via WatchConnectivity.
- User switcher (Florian / Helena), matching the web app.

## What's intentionally not here yet

- HealthKit save on iPhone after a ride (Watch saves; iPhone-only rides don't).
- Turn-by-turn voice prompts.
- Offline tile caching for MapKit.
- Full Charts integration (we use a hand-rolled sparkline for elevation).
- Push-based Live Activity updates (we update in-process via the running app).
- App icons (placeholders only — drop PNGs into `*.appiconset`).

## Apple Developer

- Team ID: `BKZ9F73H65`
- App Group: `group.com.calabrese.little-explorer-ios` (defined in entitlements; not used yet, set up for future shared-defaults work).
- Provisioning: managed by Xcode (Automatic signing).
