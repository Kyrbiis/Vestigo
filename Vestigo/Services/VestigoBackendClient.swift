import Foundation

enum VestigoBackendConfiguration {
    nonisolated static let baseURL = URL(string: "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api")!
}

struct TVDBFranchiseList: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String
    let overview: String?
    let memberTitles: Set<String>
}

struct BackendMediaItemDTO: Decodable {
    let id: Int
    let kind: String
    let title: String
    let overview: String
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let voteAverage: Double
    let genreIDs: [Int]
    let originalLanguage: String?

    nonisolated var mediaItem: MediaItem {
        MediaItem(
            id: id,
            kind: kind == "tv" ? .tv : .movie,
            title: title,
            overview: overview,
            posterPath: posterPath,
            backdropPath: backdropPath,
            releaseDate: releaseDate,
            voteAverage: voteAverage,
            genreIDs: genreIDs,
            creditRole: nil,
            runtime: nil,
            originalLanguage: originalLanguage
        )
    }
}

struct BackendFranchiseRecommendationsResponse: nonisolated Decodable {
    struct WikidataFranchise: nonisolated Decodable {
        let name: String?
    }

    let ok: Bool
    let source: String?
    let wikidataFranchise: WikidataFranchise?
    let tvdbEntityIDCount: Int?
    let embeddedExactRefCount: Int?
    let tmdbFindRefCount: Int?
    let wikidataExactRefCount: Int?
    let tmdbSearchRefCount: Int?
    let results: [BackendMediaItemDTO]

    nonisolated var hasExactProviderEvidence: Bool {
        (tvdbEntityIDCount ?? 0) > 0 ||
        (embeddedExactRefCount ?? 0) > 0 ||
        (tmdbFindRefCount ?? 0) > 0 ||
        (wikidataExactRefCount ?? 0) > 0 ||
        (source?.contains("wikidata-linked-franchise") == true)
    }

    nonisolated var mediaItems: [MediaItem] {
        results.map(\.mediaItem)
    }
}

actor VestigoBackendClient {
    private let baseURL: URL

    init(baseURL: URL = VestigoBackendConfiguration.baseURL) {
        self.baseURL = baseURL
    }

    func franchiseList(id: String, matching query: String) async throws -> TVDBFranchiseList? {
        var components = URLComponents(url: baseURL.appending(path: "franchise-membership"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "query", value: query)
        ]

        guard let url = components.url else { return nil }
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode == 404 {
            return nil
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(BackendFranchiseMembershipResponse.self, from: data)
        return decoded.franchise
    }
    
    func franchiseRecommendations(id: String, matching query: String) async throws -> [MediaItem] {
        let response = try await franchiseRecommendationResponse(id: id, matching: query)
        return response.mediaItems
    }

    func exactFranchiseRecommendations(id: String, matching query: String) async throws -> [MediaItem] {
        let response = try await franchiseRecommendationResponse(id: id, matching: query)
        guard response.hasExactProviderEvidence else { return [] }
        return response.mediaItems
    }

    private func franchiseRecommendationResponse(id: String, matching query: String) async throws -> BackendFranchiseRecommendationsResponse {
        var components = URLComponents(url: baseURL.appending(path: "franchise-recommendations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "query", value: query)
        ]

        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(BackendFranchiseRecommendationsResponse.self, from: data)
    }
    
    func tmdbCollection(for item: MediaItem) async throws -> BackendTMDbCollectionDTO? {
        guard item.kind == .movie else { return nil }

        var components = URLComponents(url: baseURL.appending(path: "tmdb-collection-for-item"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "id", value: String(item.id))
        ]

        guard let url = components.url else { return nil }
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode == 404 {
            return nil
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(BackendTMDbCollectionResponse.self, from: data)
        return decoded.collection
    }

    func tmdbCollectionRecommendations(collectionID: Int) async throws -> [MediaItem] {
        var components = URLComponents(url: baseURL.appending(path: "tmdb-collection"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "id", value: String(collectionID))
        ]

        guard let url = components.url else { return [] }
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(BackendTMDbCollectionResponse.self, from: data)
        return decoded.collection?.mediaItems ?? []
    }

    func ratings(for item: MediaItem, primaryKey: String = "", backupKey: String = "") async throws -> ExternalRatings? {
        guard item.kind == .movie || item.kind == .tv else { return nil }

        let releaseYear = item.releaseDate.flatMap { releaseDate -> String? in
            guard releaseDate.count >= 4 else { return nil }
            return String(releaseDate.prefix(4))
        }

        var components = URLComponents(url: baseURL.appending(path: "ratings"), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "tmdbID", value: String(item.id)),
            URLQueryItem(name: "kind", value: item.kind.rawValue),
            URLQueryItem(name: "title", value: item.title),
            URLQueryItem(name: "year", value: releaseYear)
        ]
        if !primaryKey.isEmpty { queryItems.append(URLQueryItem(name: "userKey", value: primaryKey)) }
        if !backupKey.isEmpty { queryItems.append(URLQueryItem(name: "userBackupKey", value: backupKey)) }
        components.queryItems = queryItems

        guard let url = components.url else { return nil }
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else { return nil }

        guard (200...299).contains(httpResponse.statusCode) else {
            return nil
        }

        let decoded = try JSONDecoder().decode(BackendRatingsResponse.self, from: data)
        return decoded.ratings
    }

    static func normalizedTitle(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct BackendFranchiseMembershipResponse: nonisolated Decodable {
    let ok: Bool
    let franchise: TVDBFranchiseList?
}

struct BackendTMDbCollectionResponse: nonisolated Decodable {
    let ok: Bool
    let collection: BackendTMDbCollectionDTO?
}

struct BackendRatingsResponse: nonisolated Decodable {
    let ok: Bool
    let ratings: ExternalRatings?
}

struct BackendTMDbCollectionDTO: nonisolated Decodable, Identifiable {
    let id: Int
    let name: String
    let overview: String?
    let items: [BackendMediaItemDTO]

    nonisolated var mediaItems: [MediaItem] {
        items.map(\.mediaItem)
    }
}
