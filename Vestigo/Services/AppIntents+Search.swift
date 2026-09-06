import Foundation
import SwiftUI
#if canImport(AppIntents)
import AppIntents

// MARK: - Catalog search

@available(iOS 16.0, *)
enum VestigoIntentSearch {
    private static let base = "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api"

    static func searchCatalog(query: String) async -> [VestigoMediaEntity] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var comps = URLComponents(string: base + "/tmdb-proxy")
        comps?.queryItems = [
            URLQueryItem(name: "path", value: "/search/multi"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "query", value: trimmed),
            URLQueryItem(name: "include_adult", value: "false")
        ]

        guard let url = comps?.url else { return [] }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return [] }
            let decoded = try JSONDecoder().decode(TMDbSearchResponse.self, from: data)
            return decoded.results.compactMap { result -> VestigoMediaEntity? in
                guard let mediaType = result.media_type,
                      mediaType == "movie" || mediaType == "tv",
                      let id = result.id else { return nil }
                let title = mediaType == "tv" ? (result.name ?? "") : (result.title ?? "")
                guard !title.isEmpty else { return nil }
                let year: String? = (result.release_date ?? result.first_air_date).flatMap { date in
                    date.count >= 4 ? String(date.prefix(4)) : nil
                }
                let filter: VestigoMediaKindFilter = mediaType == "tv" ? .shows : .movies
                return VestigoMediaEntity(id: "\(mediaType)-\(id)", title: title, kindFilter: filter, releaseYear: year)
            }
        } catch {
            return []
        }
    }

    private struct TMDbSearchResponse: Decodable {
        let results: [TMDbSearchResult]
    }
    private struct TMDbSearchResult: Decodable {
        let id: Int?
        let title: String?
        let name: String?
        let media_type: String?
        let release_date: String?
        let first_air_date: String?
    }
}

#endif
