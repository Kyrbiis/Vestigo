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
        async let movieSuggestions = fetchSuggestions(rawQuery: rawQuery, filterParam: "movie")
        async let tvSuggestions    = fetchSuggestions(rawQuery: rawQuery, filterParam: "tv")
        let (movies, tv) = try await (movieSuggestions, tvSuggestions)
        async let movieResults = resolve(suggestions: movies, filter: .movie)
        async let tvResults    = resolve(suggestions: tv,     filter: .tv)
        let (mr, tr) = await (movieResults, tvResults)
        return mr + tr
    }

    // MARK: - Groq recommendation fetch

    private struct Suggestion: Decodable {
        let title: String
        let year: Int?
        let reason: String
    }

    private struct RecommendResponse: Decodable {
        let ok: Bool
        let titles: [Suggestion]
    }

    private func fetchSuggestions(rawQuery: String, filterParam: String) async throws -> [Suggestion] {
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
        return decoded.titles
    }

    // MARK: - TMDb resolution

    private func resolve(suggestions: [Suggestion], filter: MediaFilter) async -> [ThematicSearchResult] {
        await withTaskGroup(of: ThematicSearchResult?.self) { group in
            for (index, suggestion) in suggestions.enumerated() {
                let s = suggestion
                let rank = index
                group.addTask {
                    guard let item = await self.resolveTitle(s.title, year: s.year, filter: filter) else { return nil }
                    let score = Double(suggestions.count - rank)
                    return ThematicSearchResult(
                        item: item,
                        matchedFacets: [s.reason],
                        penaltySignals: [],
                        score: score
                    )
                }
            }
            var results: [ThematicSearchResult] = []
            for await r in group { if let r { results.append(r) } }

            // Deduplicate by MediaKey, keeping highest score (earliest Groq suggestion)
            var seen = Set<MediaKey>()
            return results
                .sorted { $0.score > $1.score }
                .filter { seen.insert($0.item.key).inserted }
        }
    }

    private func resolveTitle(_ title: String, year: Int?, filter: MediaFilter) async -> MediaItem? {
        guard let results = try? await tmdb.search(query: title, filter: filter), !results.isEmpty else { return nil }

        let normalized = normalize(title)

        // Prefer an exact or near-exact title match
        if let exact = results.first(where: { normalize($0.title) == normalized }) {
            return exact
        }

        // If year provided, prefer the result whose release year matches
        if let year {
            if let yearMatch = results.first(where: { releaseYear(of: $0) == year }) {
                return yearMatch
            }
        }

        // Fall back to first result only if title is reasonably close
        let first = results[0]
        let firstNorm = normalize(first.title)
        if firstNorm.contains(normalized) || normalized.contains(firstNorm) {
            return first
        }

        return nil
    }

    private func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9 ]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\b(the|a|an)\b"#, with: "", options: .regularExpression)
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func releaseYear(of item: MediaItem) -> Int? {
        guard let date = item.releaseDate, date.count >= 4 else { return nil }
        return Int(date.prefix(4))
    }
}
