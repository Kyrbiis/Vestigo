import Foundation

// MARK: - Result

struct ThematicSearchResult: Identifiable {
    let item: MediaItem
    let matchedFacets: [String]
    let penaltySignals: [String]
    var id: MediaKey { item.key }
    var score: Double
}

// MARK: - Service

struct ThematicSearchService {
    let tmdb: TMDbService

    static var isAvailable: Bool { true }
    static let dailyLimit = 14_400

    func search(rawQuery: String, filter: MediaFilter) async throws -> [ThematicSearchResult] {
        async let movieItems = fetchItems(rawQuery: rawQuery, filterParam: "movie")
        async let tvItems    = fetchItems(rawQuery: rawQuery, filterParam: "tv")
        let (movies, tv) = try await (movieItems, tvItems)

        var seen = Set<MediaKey>()
        return (movies + tv)
            .sorted { $0.score > $1.score }
            .filter { seen.insert($0.item.key).inserted }
    }

    // MARK: - Backend fetch

    private struct ThematicItem: Decodable {
        let id: Int
        let title: String?
        let name: String?
        let overview: String?
        let posterPath: String?
        let backdropPath: String?
        let releaseDate: String?
        let firstAirDate: String?
        let voteAverage: Double?
        let voteCount: Int?
        let genreIDs: [Int]?
        let originalLanguage: String?
        let mediaType: String?

        enum CodingKeys: String, CodingKey {
            case id, title, name, overview
            case posterPath = "poster_path"
            case backdropPath = "backdrop_path"
            case releaseDate = "release_date"
            case firstAirDate = "first_air_date"
            case voteAverage = "vote_average"
            case voteCount = "vote_count"
            case genreIDs = "genre_ids"
            case originalLanguage = "original_language"
            case mediaType = "media_type"
        }

        var asMediaItem: MediaItem {
            MediaItem(
                id: id,
                kind: mediaType == "tv" ? .tv : .movie,
                title: title ?? name ?? "",
                overview: overview ?? "",
                posterPath: posterPath,
                backdropPath: backdropPath,
                releaseDate: releaseDate ?? firstAirDate,
                voteAverage: voteAverage ?? 0,
                voteCount: voteCount,
                genreIDs: genreIDs ?? [],
                creditRole: nil,
                runtime: nil,
                originalLanguage: originalLanguage
            )
        }
    }

    private struct RecommendResponse: Decodable {
        let ok: Bool
        let items: [ThematicItem]
    }

    private func fetchItems(rawQuery: String, filterParam: String) async throws -> [ThematicSearchResult] {
        struct Body: Encodable { let query: String; let filter: String }

        var req = URLRequest(url: VestigoBackendConfiguration.baseURL.appending(path: "thematic-recommend"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(Body(query: rawQuery, filter: filterParam))

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(RecommendResponse.self, from: data)

        return decoded.items
            .filter { !($0.title ?? $0.name ?? "").isEmpty }
            .enumerated()
            .map { index, item in
                ThematicSearchResult(
                    item: item.asMediaItem,
                    matchedFacets: [],
                    penaltySignals: [],
                    score: Double(decoded.items.count - index)
                )
            }
    }
}
