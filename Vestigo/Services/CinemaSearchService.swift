import SwiftUI
import Foundation
import Combine
#if canImport(MapKit)
import MapKit
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif

struct CinemasNearYouSection: View {
    let filmTitle: String
    @ObservedObject var service: CinemaSearchService
    @Binding var selectedDate: Date
    let accentColor: Color

    @State private var selectedTheater: CinemaTheater?
    @State private var didAttemptLoad = false

    private var dateRange: ClosedRange<Date> {
        let today = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 14, to: today) ?? today
        return today...end
    }

    /// AMC pins we're allowed to show. Only AMC theatres with actual showtimes
    /// for the current film + date are surfaced; before AMC data flows, the whole
    /// section stays hidden.
    private var displayedTheaters: [CinemaTheater] {
        service.theaters
            .filter { $0.chain == .amc && !$0.showtimes.isEmpty }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var shouldReveal: Bool {
        !displayedTheaters.isEmpty
    }

    var body: some View {
        Group {
            if shouldReveal {
                visibleSection
            } else {
                // Invisible placeholder — still triggers the initial load so the
                // section can appear the moment AMC returns real data.
                Color.clear
                    .frame(height: 0)
                    .onAppear(perform: kickOffLoadIfNeeded)
            }
        }
        .onChange(of: selectedDate) { _, newValue in
            Task { await service.refreshAMCShowtimes(filmTitle: filmTitle, date: newValue) }
        }
        .sheet(item: $selectedTheater) { theater in
            CinemaInfoSheet(
                theater: theater,
                filmTitle: filmTitle,
                userCoordinate: service.userCoordinate,
                service: service,
                accentColor: accentColor
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var visibleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AMC cinemas nearby")
                .sectionTitle()

            theaterSection
        }
        .onAppear(perform: kickOffLoadIfNeeded)
    }

    private func kickOffLoadIfNeeded() {
        guard !didAttemptLoad else { return }
        didAttemptLoad = true
        Task { await service.loadNearbyTheaters(filmTitle: filmTitle) }
    }

    private var theaterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker(
                "Date",
                selection: $selectedDate,
                in: dateRange,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .frame(maxWidth: .infinity, alignment: .leading)

            CinemaMapView(
                theaters: displayedTheaters,
                userCoordinate: service.userCoordinate,
                accentColor: accentColor,
                onSelect: { theater in
                    selectedTheater = theater
                }
            )
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )

            Text("Tap any AMC pin to see showtimes and open its booking page.")
                .font(.caption)
                .foregroundStyle(.secondary)

            theaterList
        }
    }

    private var theaterList: some View {
        VStack(spacing: 10) {
            ForEach(displayedTheaters.prefix(10)) { theater in
                Button {
                    selectedTheater = theater
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: theater.availability == .showtimesConfirmed ? "sparkles" : "mappin.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(theater.availability == .showtimesConfirmed ? accentColor : .secondary)
                            .frame(width: 30, height: 30)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(theater.name)
                                .font(.headline.bold())
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text(theater.availability == .showtimesConfirmed
                                 ? "Showtimes available"
                                 : "Check availability")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .liquidGlass(cornerRadius: 20)
            }
        }
    }
}

struct CinemaMapView: View {
    let theaters: [CinemaTheater]
    let userCoordinate: CLLocationCoordinate2D?
    let accentColor: Color
    let onSelect: (CinemaTheater) -> Void

    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $cameraPosition) {
            if let userCoordinate {
                Annotation("You", coordinate: userCoordinate) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }

            ForEach(theaters) { theater in
                Annotation(theater.name, coordinate: theater.coordinate) {
                    Button {
                        onSelect(theater)
                    } label: {
                        pin(for: theater)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onAppear {
            guard let userCoordinate else { return }
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: userCoordinate,
                    latitudinalMeters: 40_000,
                    longitudinalMeters: 40_000
                )
            )
        }
    }

    @ViewBuilder
    private func pin(for theater: CinemaTheater) -> some View {
        let confirmed = theater.availability == .showtimesConfirmed
        let size: CGFloat = confirmed ? 32 : 18
        ZStack {
            Circle()
                .fill(confirmed ? accentColor : .secondary.opacity(0.6))
            Image(systemName: confirmed ? "sparkles" : "mappin")
                .font(.system(size: confirmed ? 14 : 10, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(
            Circle().stroke(.white, lineWidth: confirmed ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }
}

struct CinemaInfoSheet: View {
    let theater: CinemaTheater
    let filmTitle: String
    let userCoordinate: CLLocationCoordinate2D?
    @ObservedObject var service: CinemaSearchService
    let accentColor: Color

    @Environment(\.openURL) private var openURL
    @State private var drivingSeconds: TimeInterval?
    @State private var didLoadDriving = false

    var body: some View {
        ZStack {
            AppBackground(settings: .init())
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    distanceRow

                    if theater.availability == .showtimesConfirmed {
                        if theater.showtimes.isEmpty {
                            StatusBubble(
                                title: "No showtimes yet",
                                text: "AMC hasn't published showtimes for this film on the selected date."
                            )
                        } else {
                            showtimeGrid
                        }
                    } else {
                        checkAtChainBubble
                    }

                    openInMapsButton
                }
                .padding(18)
            }
        }
        .task {
            guard !didLoadDriving, let user = userCoordinate else { return }
            didLoadDriving = true
            drivingSeconds = await service.drivingTime(from: user, to: theater.coordinate)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(theater.name)
                .font(.title2.bold())
            if let address = theater.address {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var distanceRow: some View {
        HStack(spacing: 14) {
            if let user = userCoordinate {
                let (mi, km) = distances(user: user, dest: theater.coordinate)
                infoChip(icon: "location.circle", label: String(format: "%.1f mi", mi))
                infoChip(icon: "location.north.line.fill", label: String(format: "%.1f km", km))
            }
            if let drivingSeconds {
                infoChip(icon: "car.fill", label: formatDuration(drivingSeconds))
            }
        }
    }

    private var showtimeGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Showtimes")
                .font(.headline.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 10)], spacing: 10) {
                ForEach(theater.showtimes) { showtime in
                    Button {
                        if let url = showtime.bookingURL {
                            openURL(url)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(showtime.startTime.formatted(date: .omitted, time: .shortened))
                                .font(.headline.bold())
                            if let format = showtime.format, !format.isEmpty {
                                Text(format)
                                    .font(.caption.bold())
                                    .foregroundStyle(accentColor)
                            }
                            if !showtime.accessibility.isEmpty {
                                Text(showtime.accessibility.joined(separator: " · "))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .liquidGlass(cornerRadius: 16)
                }
            }
        }
    }

    private var checkAtChainBubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Check availability")
                .font(.headline.bold())
            Text("Open the theater's website to see if \(filmTitle) is showing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                openChainSite()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Open \(theater.chain.displayName)")
                        .font(.subheadline.bold())
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .liquidGlass(cornerRadius: 22)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 22)
    }

    private var openInMapsButton: some View {
        Button {
            openInMaps()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "map.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("Open in Maps")
                    .font(.subheadline.bold())
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .liquidGlass(cornerRadius: 22)
        }
        .buttonStyle(.plain)
    }

    private func infoChip(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.bold())
            Text(label)
                .font(.caption.bold())
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .liquidGlass(cornerRadius: 15)
    }

    private func distances(user: CLLocationCoordinate2D, dest: CLLocationCoordinate2D) -> (mi: Double, km: Double) {
        let a = CLLocation(latitude: user.latitude, longitude: user.longitude)
        let b = CLLocation(latitude: dest.latitude, longitude: dest.longitude)
        let meters = a.distance(from: b)
        let km = meters / 1000
        let mi = meters / 1609.34
        return (mi, km)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "\(minutes) min drive"
        }
        let hours = minutes / 60
        let remaining = minutes % 60
        return remaining == 0 ? "\(hours)h drive" : "\(hours)h \(remaining)m drive"
    }

    private func openChainSite() {
        if let appURL = theater.chain.searchAppURL(filmTitle: filmTitle),
           UIApplication.shared.canOpenURL(appURL) {
            openURL(appURL)
            return
        }
        if let webURL = theater.chain.searchWebURL(filmTitle: filmTitle) {
            openURL(webURL)
        }
    }

    private func openInMaps() {
        if let mapItem = theater.mapItem {
            mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
            return
        }
        let item = CinemaMapKitBridge.makeMapItem(coordinate: theater.coordinate, name: theater.name)
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

/// Small compatibility bridge for iOS 26 MapKit API deprecations.
/// New API used on iOS 26+, deprecated MKPlacemark/CLGeocoder path retained for older OSes.
enum CinemaMapKitBridge {
    static func makeMapItem(coordinate: CLLocationCoordinate2D, name: String?) -> MKMapItem {
        if #available(iOS 26.0, *) {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let item = MKMapItem(location: location, address: nil)
            item.name = name
            return item
        } else {
            return makeMapItemLegacy(coordinate: coordinate, name: name)
        }
    }

    static func coordinate(of mapItem: MKMapItem) -> CLLocationCoordinate2D {
        if #available(iOS 26.0, *) {
            return mapItem.location.coordinate
        } else {
            return coordinateLegacy(of: mapItem)
        }
    }

    static func addressLine(of mapItem: MKMapItem) -> String? {
        if #available(iOS 26.0, *) {
            return mapItem.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
                ?? mapItem.address?.fullAddress
        } else {
            return addressLineLegacy(of: mapItem)
        }
    }

    static func resolveCountryCode(for location: CLLocation) async -> String? {
        if #available(iOS 26.0, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
            do {
                let mapItems = try await request.mapItems
                return mapItems.first?.addressRepresentations?.region?.identifier
            } catch {
                return nil
            }
        } else {
            return await resolveCountryCodeLegacy(for: location)
        }
    }

    @available(iOS, deprecated: 26.0, message: "Deprecated MKPlacemark path; use MKMapItem(location:address:) on iOS 26+.")
    private static func makeMapItemLegacy(coordinate: CLLocationCoordinate2D, name: String?) -> MKMapItem {
        let placemark = MKPlacemark(coordinate: coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = name
        return item
    }

    @available(iOS, deprecated: 26.0, message: "Deprecated placemark accessor; use MKMapItem.location on iOS 26+.")
    private static func coordinateLegacy(of mapItem: MKMapItem) -> CLLocationCoordinate2D {
        mapItem.placemark.coordinate
    }

    @available(iOS, deprecated: 26.0, message: "Deprecated placemark accessor; use MKMapItem.addressRepresentations on iOS 26+.")
    private static func addressLineLegacy(of mapItem: MKMapItem) -> String? {
        mapItem.placemark.title
    }

    @available(iOS, deprecated: 26.0, message: "Deprecated CLGeocoder path; use MKReverseGeocodingRequest on iOS 26+.")
    private static func resolveCountryCodeLegacy(for location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            return placemarks.first?.isoCountryCode
        } catch {
            return nil
        }
    }
}


final class CinemaSearchService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var userCoordinate: CLLocationCoordinate2D?
    @Published var countryCode: String?
    @Published var theaters: [CinemaTheater] = []
    @Published var isSearching: Bool = false
    @Published var lastError: String?

    private let manager = CLLocationManager()
    private var pendingContinuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermissionIfNeeded() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func loadNearbyTheaters(filmTitle: String, forceRequestPermission: Bool = true) async {
        if forceRequestPermission {
            requestPermissionIfNeeded()
        }

        guard let location = await fetchOneShotLocation() else {
            lastError = "Location unavailable."
            return
        }

        let coord = location.coordinate
        userCoordinate = coord
        await resolveCountry(for: location)

        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "movie theater"
        if #available(iOS 18.0, *) {
            request.resultTypes = .pointOfInterest
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.movieTheater])
        } else {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.movieTheater])
        }
        request.region = MKCoordinateRegion(
            center: coord,
            latitudinalMeters: 60_000,
            longitudinalMeters: 60_000
        )

        do {
            let response = try await MKLocalSearch(request: request).start()
            theaters = response.mapItems.compactMap { item in
                let name = item.name ?? "Cinema"
                let coordinate = CinemaMapKitBridge.coordinate(of: item)
                let identifier = "\(name)|\(coordinate.latitude)|\(coordinate.longitude)"
                let chain = CinemaChain.identify(from: name)
                return CinemaTheater(
                    id: identifier,
                    name: name,
                    chain: chain,
                    coordinate: coordinate,
                    address: CinemaMapKitBridge.addressLine(of: item),
                    phone: item.phoneNumber,
                    mapItem: item,
                    availability: .checkAtChain,
                    showtimes: []
                )
            }

            await enrichAMCShowtimes(filmTitle: filmTitle, date: Date(), userCoordinate: coord)
        } catch {
            lastError = error.localizedDescription
            theaters = []
        }
    }

    func refreshAMCShowtimes(filmTitle: String, date: Date) async {
        guard let coord = userCoordinate else { return }
        await enrichAMCShowtimes(filmTitle: filmTitle, date: date, userCoordinate: coord)
    }

    private func enrichAMCShowtimes(filmTitle: String, date: Date, userCoordinate: CLLocationCoordinate2D) async {
        let amcTheaters = theaters.filter { $0.chain == .amc }
        guard !amcTheaters.isEmpty else { return }

        let result = await AMCShowtimesService.fetchShowtimes(
            filmTitle: filmTitle,
            date: date,
            lat: userCoordinate.latitude,
            lon: userCoordinate.longitude
        )

        // If the backend request failed, leave AMC pins as `.checkAtChain` (users still see them + deep link).
        guard result.succeeded else { return }

        // Backend responded successfully. Upgrade AMC pins that have showtimes,
        // and remove AMC pins whose theatre came back with no showtimes for this film + date.
        theaters = theaters.compactMap { theater in
            guard theater.chain == .amc else { return theater }
            let matched = result.theaters[normalizedName(theater.name)] ?? []
            if matched.isEmpty {
                return nil
            }
            var updated = theater
            updated.availability = .showtimesConfirmed
            updated.showtimes = matched
            return updated
        }
    }

    private func normalizedName(_ name: String) -> String {
        name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func fetchOneShotLocation() async -> CLLocation? {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
                return nil
            }
        default:
            return nil
        }

        return await withCheckedContinuation { continuation in
            pendingContinuation = continuation
            manager.requestLocation()
        }
    }

    private func resolveCountry(for location: CLLocation) async {
        countryCode = await CinemaMapKitBridge.resolveCountryCode(for: location)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in
            self.pendingContinuation?.resume(returning: location)
            self.pendingContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.pendingContinuation?.resume(returning: nil)
            self.pendingContinuation = nil
            self.lastError = error.localizedDescription
        }
    }

    @MainActor
    func drivingTime(from user: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async -> TimeInterval? {
        let source = CinemaMapKitBridge.makeMapItem(coordinate: user, name: nil)
        let dest = CinemaMapKitBridge.makeMapItem(coordinate: destination, name: nil)
        let request = MKDirections.Request()
        request.source = source
        request.destination = dest
        request.transportType = .automobile
        do {
            let response = try await MKDirections(request: request).calculateETA()
            return response.expectedTravelTime
        } catch {
            return nil
        }
    }
}

enum AMCShowtimesService {
    struct Result {
        let theaters: [String: [CinemaShowtime]]
        let succeeded: Bool
    }

    // Fetches AMC showtimes via the Vestigo backend proxy.
    // `succeeded == true` means the backend responded 2xx with a valid body,
    // even if that body's `theaters` was empty (film not playing at nearby AMCs).
    // `succeeded == false` means transport error, non-2xx, or malformed JSON — treat as "no data" and don't hide pins.
    static func fetchShowtimes(filmTitle: String, date: Date, lat: Double, lon: Double) async -> Result {
        let base = "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api"
        var comps = URLComponents(string: base + "/amc-showtimes")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        comps?.queryItems = [
            URLQueryItem(name: "title", value: filmTitle),
            URLQueryItem(name: "date", value: formatter.string(from: date)),
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lon", value: String(lon))
        ]

        guard let url = comps?.url else { return Result(theaters: [:], succeeded: false) }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return Result(theaters: [:], succeeded: false)
            }
            let decoded = try JSONDecoder().decode(AMCShowtimesResponse.self, from: data)
            var map: [String: [CinemaShowtime]] = [:]
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoFallback = ISO8601DateFormatter()
            isoFallback.formatOptions = [.withInternetDateTime]
            for entry in decoded.theaters {
                let key = normalizedName(entry.name)
                let times = entry.showtimes.compactMap { dto -> CinemaShowtime? in
                    let start = iso.date(from: dto.startTime) ?? isoFallback.date(from: dto.startTime)
                    guard let start else { return nil }
                    return CinemaShowtime(
                        id: dto.id,
                        startTime: start,
                        format: dto.format,
                        accessibility: dto.accessibility ?? [],
                        bookingURL: dto.bookingURL.flatMap(URL.init(string:))
                    )
                }
                if !times.isEmpty {
                    map[key] = times
                }
            }
            return Result(theaters: map, succeeded: decoded.ok)
        } catch {
            return Result(theaters: [:], succeeded: false)
        }
    }

    private static func normalizedName(_ name: String) -> String {
        name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct AMCShowtimesResponse: Decodable {
    let ok: Bool
    let theaters: [AMCTheaterEntry]
}

struct AMCTheaterEntry: Decodable {
    let name: String
    let showtimes: [AMCShowtimeEntry]
}

struct AMCShowtimeEntry: Decodable {
    let id: String
    let startTime: String
    let format: String?
    let accessibility: [String]?
    let bookingURL: String?
}

enum CinemaChain: String, Codable, Hashable {
    case amc
    case regal
    case cinemark
    case alamo
    case harkins
    case marcus
    case landmark
    case bnb
    case other

    static func identify(from name: String) -> CinemaChain {
        let normalized = name.lowercased()
        if normalized.contains("amc") { return .amc }
        if normalized.contains("regal") { return .regal }
        if normalized.contains("cinemark") || normalized.contains("century theatre") || normalized.contains("century theater") { return .cinemark }
        if normalized.contains("alamo") { return .alamo }
        if normalized.contains("harkins") { return .harkins }
        if normalized.contains("marcus") { return .marcus }
        if normalized.contains("landmark") { return .landmark }
        if normalized.contains("b&b") || normalized.contains("bnb theatres") { return .bnb }
        return .other
    }

    var displayName: String {
        switch self {
        case .amc: return "AMC"
        case .regal: return "Regal"
        case .cinemark: return "Cinemark"
        case .alamo: return "Alamo Drafthouse"
        case .harkins: return "Harkins"
        case .marcus: return "Marcus Theatres"
        case .landmark: return "Landmark Theatres"
        case .bnb: return "B&B Theatres"
        case .other: return "Cinema"
        }
    }

    func searchAppURL(filmTitle: String) -> URL? {
        let query = filmTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filmTitle
        switch self {
        case .amc:
            return URL(string: "amcmovies://home")
        case .regal:
            return URL(string: "regmovies://home")
        case .cinemark:
            return URL(string: "cinemark://home")
        default:
            _ = query
            return nil
        }
    }

    func searchWebURL(filmTitle: String) -> URL? {
        let title = filmTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        switch self {
        case .amc:
            return URL(string: "https://www.amc.com/movies?query=\(encoded)")
        case .regal:
            return URL(string: "https://www.regmovies.com/search?query=\(encoded)")
        case .cinemark:
            return URL(string: "https://www.cinemark.com/movies?query=\(encoded)")
        case .alamo:
            return URL(string: "https://drafthouse.com/show/search?query=\(encoded)")
        case .harkins:
            return URL(string: "https://www.harkins.com/movies/search?q=\(encoded)")
        case .marcus:
            return URL(string: "https://www.marcustheatres.com/movies/search?query=\(encoded)")
        case .landmark:
            return URL(string: "https://www.landmarktheatres.com/search?query=\(encoded)")
        case .bnb:
            return URL(string: "https://bbtheatres.com/movies/search?q=\(encoded)")
        case .other:
            return URL(string: "https://www.google.com/search?q=\(encoded)+showtimes")
        }
    }
}

enum CinemaAvailability: Hashable {
    case showtimesConfirmed
    case checkAtChain
}

struct CinemaShowtime: Identifiable, Hashable {
    let id: String
    let startTime: Date
    let format: String?
    let accessibility: [String]
    let bookingURL: URL?
}

struct CinemaTheater: Identifiable, Hashable {
    let id: String
    let name: String
    let chain: CinemaChain
    let coordinate: CLLocationCoordinate2D
    let address: String?
    let phone: String?
    let mapItem: MKMapItem?
    var availability: CinemaAvailability
    var showtimes: [CinemaShowtime]

    static func == (lhs: CinemaTheater, rhs: CinemaTheater) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

