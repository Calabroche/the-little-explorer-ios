import CoreLocation
import MapKit
import SwiftUI

/// "Trouver un professionnel" — finds bike shops / repairers near the rider
/// and shows them on a map + as a list. Mirrors the web's FindProModal:
///
///   * pick your bike brand (default Canyon) so specialists get flagged,
///   * choose a radius (5 / 10 / 15 km),
///   * tap a pin to focus its card and vice-versa.
///
/// Data comes from `/api/bike-shops` (OpenStreetMap + a best-effort website
/// scan for brands). Presented as a sheet from the Matériel screen.
struct BikeShopsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var brand: String = BikeBrands.defaultBrand
    @State private var customBrand: String = ""
    @State private var usingCustom: Bool = false
    @State private var radiusKm: Double = 10

    @State private var shops: [BikeShop] = []
    @State private var loading = false
    @State private var error: String?
    @State private var hasSearched = false
    @State private var activeId: String?
    @State private var cameraPosition: MapCameraPosition = .automatic

    /// Web uses this same purple for brand specialists.
    private let special = Color(hex: "8A4FB5")
    private let radii: [Double] = [5, 10, 15]

    private var effectiveBrand: String {
        let b = usingCustom ? customBrand.trimmingCharacters(in: .whitespaces) : brand
        return b.isEmpty ? BikeBrands.defaultBrand : b
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controls
                Divider().overlay(AppColors.creamBorder)
                content
            }
            .background(AppColors.cream.ignoresSafeArea())
            .navigationTitle("Trouver un pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .tint(AppColors.terra)
                }
            }
        }
        .task { await firstLoad() }
        .onChange(of: environment.location.lastLocation != nil) { _, hasFix in
            // Auto-search the first time a fix lands (the initial appear may
            // have fired before Core Location had a position). CLLocation isn't
            // Equatable, so we watch the nil → non-nil transition as a Bool.
            if hasFix && !hasSearched && !loading { Task { await search() } }
        }
    }

    // MARK: - Controls (brand + radius)

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("Ma marque")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.inkMid)
                Spacer()
                brandMenu
            }
            if usingCustom {
                TextField("Marque de ton vélo", text: $customBrand)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await search() } }
            }

            HStack(spacing: 10) {
                Text("Rayon")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.inkMid)
                Picker("Rayon", selection: $radiusKm) {
                    ForEach(radii, id: \.self) { r in
                        Text("\(Int(r)) km").tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: radiusKm) { _, _ in
                    if hasSearched { Task { await search() } }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var brandMenu: some View {
        Menu {
            ForEach(BikeBrands.all, id: \.self) { b in
                Button {
                    brand = b; usingCustom = false
                    Task { await search() }
                } label: {
                    if !usingCustom && b == brand {
                        Label(b, systemImage: "checkmark")
                    } else {
                        Text(b)
                    }
                }
            }
            Divider()
            Button("Autre marque…") { usingCustom = true }
        } label: {
            HStack(spacing: 4) {
                Text(usingCustom ? (customBrand.isEmpty ? "Autre marque…" : customBrand) : brand)
                    .font(.system(size: 14, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11))
            }
            .foregroundStyle(AppColors.terra)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(AppColors.terraLight, in: Capsule())
        }
    }

    // MARK: - Content (map + list / states)

    @ViewBuilder
    private var content: some View {
        if loading && shops.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("Recherche des professionnels…")
                    .font(.system(size: 13)).foregroundStyle(AppColors.inkMid)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            errorState(error)
        } else if hasSearched && shops.isEmpty {
            emptyState
        } else if !hasSearched {
            idleState
        } else {
            resultsView
        }
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            map.frame(height: 260)
            Divider().overlay(AppColors.creamBorder)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if loading {
                            ProgressView().padding(.top, 6)
                        }
                        ForEach(shops) { shop in
                            shopCard(shop)
                                .id(shop.id)
                                .onTapGesture { focus(shop) }
                        }
                    }
                    .padding(14)
                }
                .onChange(of: activeId) { _, id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .top) }
                }
            }
        }
    }

    private var map: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()
            ForEach(shops) { shop in
                // Empty title: we draw our own marker, and an under-pin label
                // would clutter the map (and .annotationTitles(.hidden) is iOS 18+).
                Annotation("", coordinate: shop.coordinate) {
                    marker(shop)
                        .onTapGesture { focus(shop) }
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls { MapUserLocationButton() }
    }

    private func marker(_ shop: BikeShop) -> some View {
        let active = shop.id == activeId
        let color = shop.isSpecialist ? special : AppColors.terra
        return Image(systemName: shop.isSpecialist ? "star.fill" : "wrench.and.screwdriver.fill")
            .font(.system(size: active ? 13 : 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: active ? 32 : 24, height: active ? 32 : 24)
            .background(color, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: active ? 3 : 2))
            .shadow(radius: active ? 4 : 1)
    }

    // MARK: - Shop card

    private func shopCard(_ shop: BikeShop) -> some View {
        let active = shop.id == activeId
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(shop.name)
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundStyle(AppColors.ink)
                Spacer()
                Text("à \(shop.distKm.formatted(.number.precision(.fractionLength(1)))) km")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.inkMid)
            }

            HStack(spacing: 6) {
                if shop.isSpecialist {
                    badge("Spécialiste \(effectiveBrand)", fg: special, bg: special.opacity(0.14))
                }
                if shop.repairs {
                    badge("Réparation", fg: AppColors.green, bg: AppColors.greenLight)
                }
            }

            if let address = shop.address {
                label("mappin.and.ellipse", address)
            }
            if let hours = shop.hours {
                label("clock", hours)
            }

            if !shop.brands.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shop.brands, id: \.self) { b in
                            let mine = b.lowercased() == effectiveBrand.lowercased()
                            Text(b)
                                .font(.system(size: 11, weight: mine ? .bold : .regular))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(mine ? special.opacity(0.14) : AppColors.creamDark, in: Capsule())
                                .foregroundStyle(mine ? special : AppColors.inkMid)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                if let phone = shop.phone, let url = URL(string: "tel:\(phone.filter { !$0.isWhitespace })") {
                    Link(destination: url) { actionChip("Appeler", "phone.fill") }
                }
                if let site = shop.website, let url = URL(string: site) {
                    Link(destination: url) { actionChip("Site", "safari.fill") }
                }
                Link(destination: mapsURL(shop)) { actionChip("Itinéraire", "location.fill") }
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(active ? AppColors.terra : AppColors.creamBorder, lineWidth: active ? 2 : 1),
        )
    }

    private func badge(_ text: String, fg: Color, bg: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(bg, in: Capsule())
            .foregroundStyle(fg)
    }

    private func label(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(AppColors.inkLight)
            Text(text).font(.system(size: 12)).foregroundStyle(AppColors.inkMid)
        }
    }

    private func actionChip(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(AppColors.terraLight, in: Capsule())
            .foregroundStyle(AppColors.terra)
    }

    // MARK: - States

    private var idleState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 34)).foregroundStyle(AppColors.terra)
            Text("On cherche les vélocistes autour de toi")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(AppColors.ink)
                .multilineTextAlignment(.center)
            Button {
                environment.location.requestOneShotLocation()
                Task { await search() }
            } label: {
                Label("Utiliser ma position", systemImage: "location.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(minHeight: 38).padding(.horizontal, 18)
            }
            .buttonStyle(.borderedProminent).tint(AppColors.terra)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30)).foregroundStyle(AppColors.inkLight)
            Text("Aucun professionnel trouvé dans \(Int(radiusKm)) km.")
                .font(.system(size: 14)).foregroundStyle(AppColors.inkMid)
                .multilineTextAlignment(.center)
            Button("Élargir à 15 km") { radiusKm = 15; Task { await search() } }
                .font(.system(size: 13, weight: .semibold)).tint(AppColors.terra)
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28)).foregroundStyle(AppColors.terra)
            Text(message)
                .font(.system(size: 13)).foregroundStyle(AppColors.inkMid)
                .multilineTextAlignment(.center)
            Button("Réessayer") { Task { await search() } }
                .font(.system(size: 13, weight: .semibold)).tint(AppColors.terra)
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func firstLoad() async {
        environment.location.requestOneShotLocation()
        if environment.location.lastLocation != nil {
            await search()
        }
    }

    private func search() async {
        guard let loc = environment.location.lastLocation else {
            // No fix yet — requestOneShotLocation() is in flight; the
            // onChange handler will retry once it arrives.
            environment.location.requestOneShotLocation()
            return
        }
        loading = true
        error = nil
        do {
            let result = try await environment.api.bikeShops(
                lat: loc.coordinate.latitude,
                lng: loc.coordinate.longitude,
                radiusKm: radiusKm,
                brand: effectiveBrand,
            )
            shops = result
            hasSearched = true
            activeId = nil
            frameMap(on: loc.coordinate)
        } catch {
            self.error = friendlyMessage(error)
        }
        loading = false
    }

    private func focus(_ shop: BikeShop) {
        activeId = shop.id
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(
                center: shop.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02),
            ))
        }
    }

    private func frameMap(on center: CLLocationCoordinate2D) {
        let delta = max(0.04, (radiusKm * 2.4) / 111)
        cameraPosition = .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta),
        ))
    }

    private func mapsURL(_ shop: BikeShop) -> URL {
        let q = shop.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "vélociste"
        return URL(string: "http://maps.apple.com/?ll=\(shop.lat),\(shop.lng)&q=\(q)")
            ?? URL(string: "http://maps.apple.com/")!
    }

    private func friendlyMessage(_ error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .unauthorized: return "Session expirée. Reconnecte-toi."
            case .transport:    return "Pas de réseau. Vérifie ta connexion."
            default:            return "La recherche a échoué. Réessaie."
            }
        }
        return "La recherche a échoué. Réessaie."
    }
}
