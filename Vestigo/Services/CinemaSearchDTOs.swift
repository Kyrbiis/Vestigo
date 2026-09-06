import Foundation

struct AMCShowtimesResponse: Decodable {
    let ok: Bool
    let theaters: [AMCTheaterEntry]
}

struct AMCTheaterEntry: Decodable {
    let name: String
    let lat: Double?
    let lon: Double?
    let showtimes: [AMCShowtimeEntry]
}

struct AMCShowtimeEntry: Decodable {
    let id: String
    let startTime: String
    let format: String?
    let accessibility: [String]?
    let bookingURL: String?
}

enum AMCShowtimesService {
    struct TheaterResult {
        let name: String
        let lat: Double?
        let lon: Double?
        let showtimes: [CinemaShowtime]
    }

    struct Result {
        let entries: [TheaterResult]
        let succeeded: Bool

        static let failed = Result(entries: [], succeeded: false)
    }

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

        guard let url = comps?.url else { return .failed }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return .failed
            }
            let decoded = try JSONDecoder().decode(AMCShowtimesResponse.self, from: data)

            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoFallback = ISO8601DateFormatter()
            isoFallback.formatOptions = [.withInternetDateTime]
            // AMC returns bare local times ("2026-07-24T19:30:00") with no timezone designator
            let localFmt = DateFormatter()
            localFmt.locale = Locale(identifier: "en_US_POSIX")
            localFmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

            let entries: [TheaterResult] = decoded.theaters.compactMap { entry in
                let times = entry.showtimes.compactMap { dto -> CinemaShowtime? in
                    let start = iso.date(from: dto.startTime)
                        ?? isoFallback.date(from: dto.startTime)
                        ?? localFmt.date(from: dto.startTime)
                    guard let start else { return nil }
                    return CinemaShowtime(
                        id: dto.id,
                        startTime: start,
                        format: dto.format,
                        accessibility: dto.accessibility ?? [],
                        bookingURL: dto.bookingURL.flatMap(URL.init(string:))
                    )
                }
                guard !times.isEmpty else { return nil }
                return TheaterResult(name: entry.name, lat: entry.lat, lon: entry.lon, showtimes: times)
            }

            return Result(entries: entries, succeeded: decoded.ok)
        } catch {
            return .failed
        }
    }
}
