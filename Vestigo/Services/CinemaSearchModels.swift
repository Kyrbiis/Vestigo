import Foundation
#if canImport(MapKit)
import MapKit
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif

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
