import Foundation
import FoundationModels

// MARK: - Structured query (Apple Intelligence only)

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Structured search parameters extracted from a natural language movie/TV request")
struct ParsedThematicQuery {
    @Guide(description: "Titles of films or shows the user wants to find something similar to, e.g. from 'like Inception' or 'similar to Breaking Bad'.")
    var similarToTitles: [String]

    @Guide(description: "Titles of films or shows whose overall style or content the user wants to avoid.")
    var avoidSimilarToTitles: [String]

    @Guide(description: "Director or actor names the user wants included.")
    var people: [String]

    @Guide(description: "Themes, topics, moods, or story elements the user wants. Include inferred themes from aspects they liked, e.g. 'I liked the heist planning' → 'heist'.")
    var positiveThemes: [String]

    @Guide(description: "Themes, moods, or story elements to exclude. Include inferred themes from aspects they disliked, e.g. 'not the romance' → 'romance'.")
    var negativeThemes: [String]

    @Guide(description: "Genre names to include, e.g. 'thriller', 'sci-fi', 'comedy'.")
    var genres: [String]

    @Guide(description: "Genre names to exclude.")
    var excludedGenres: [String]
}

// MARK: - Result

struct ThematicSearchResult: Identifiable {
    let item: MediaItem
    let matchedFacets: [String]   // positive signals that matched, for display
    let penaltySignals: [String]  // negative signals that were present (shown if score is still positive)

    var id: MediaKey { item.key }
    var score: Double             // higher = better fit
}

// MARK: - Service (requires Apple Intelligence)

@available(iOS 26.0, macOS 26.0, *)
struct ThematicSearchService {
    let tmdb: TMDbService

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    func search(rawQuery: String, filter: MediaFilter) async throws -> [ThematicSearchResult] {
        let parsed = try await parseQuery(rawQuery)
        return try await discoverAndScore(parsed: parsed, rawQuery: rawQuery, filter: filter)
    }

    // MARK: - Query parsing

    private func parseQuery(_ rawQuery: String) async throws -> ParsedThematicQuery {
        let session = LanguageModelSession(instructions: """
            Extract structured search parameters from a movie or TV show request. \
            Use empty arrays for fields not mentioned. \
            Infer themes from aspects the user liked or disliked (e.g. 'I liked the heist planning' → positiveThemes: ['heist']; \
            'not the sentimental parts' → negativeThemes: ['sentimental', 'family drama']). \
            Use your real-world knowledge to translate vague or indirect descriptions into concrete search terms. \
            For example: 'the sprinter who competed at the 1936 Olympics in Nazi Germany' → people: ['Jesse Owens']; \
            'the painter who cut off his ear' → people: ['Vincent van Gogh']; \
            'the unsinkable ship' → similarToTitles: ['Titanic'], positiveThemes: ['ship', 'disaster']. \
            Always try to identify specific people, events, or subjects even when described indirectly.
            """)
        return try await session.respond(to: rawQuery, generating: ParsedThematicQuery.self).content
    }

    // MARK: - Discovery and scoring

    private struct ResolvedPerson: Sendable {
        let name: String
        let ids: [Int]
    }

    private struct ResolvedKeyword: Sendable {
        let term: String
        let ids: [Int]
    }

    private struct Batch: Sendable {
        let items: [MediaItem]
        let facetLabel: String   // empty = text search fallback
    }

    private func discoverAndScore(parsed: ParsedThematicQuery, rawQuery: String, filter: MediaFilter) async throws -> [ThematicSearchResult] {
        // Resolve all signals concurrently
        async let likedItems      = resolveReferenceTitles(titles: parsed.similarToTitles, filter: filter)
        async let avoidItems      = resolveReferenceTitles(titles: parsed.avoidSimilarToTitles, filter: filter)
        async let people          = resolvePeople(names: parsed.people)
        async let posKeywords     = resolveKeywords(themes: parsed.positiveThemes)
        let (liked, avoided, resolvedPeople, posKW) = await (
            likedItems, avoidItems, people, posKeywords
        )

        let positiveGenreIDs = parsed.genres.reduce(into: Set<Int>()) { $0.formUnion(Self.genreIDsForName($1)) }
        let excludedGenreIDs = parsed.excludedGenres.reduce(into: Set<Int>()) { $0.formUnion(Self.genreIDsForName($1)) }
            .union(Set(avoided.flatMap { $0.genreIDs }))   // genres from explicitly avoided films

        // Build candidate pool
        var batches: [Batch] = []

        await withTaskGroup(of: Batch.self) { group in
            // Similar-to reference films: recommendations + similar
            for item in liked {
                // Capture value types before entering concurrency context
                let key = item.key
                let title = item.title
                group.addTask {
                    var items: [MediaItem] = []
                    items += (try? await tmdb.recommendations(for: key)) ?? []
                    items += (try? await tmdb.sameSeriesOrSimilar(for: key)) ?? []
                    return Batch(items: items, facetLabel: "Similar to \(title)")
                }
            }
            // Person-based discovery
            for person in resolvedPeople {
                group.addTask {
                    let items = (try? await tmdb.discoverThematic(personIDs: person.ids, keywordIDs: [], genreIDs: [], filter: filter)) ?? []
                    return Batch(items: items, facetLabel: person.name)
                }
            }
            // Positive keyword discovery
            for kw in posKW {
                group.addTask {
                    let items = (try? await tmdb.discoverThematic(personIDs: [], keywordIDs: kw.ids, genreIDs: [], filter: filter)) ?? []
                    return Batch(items: items, facetLabel: kw.term)
                }
            }
            // Genre discovery (only if no other signals — avoids drowning specific results)
            if liked.isEmpty && resolvedPeople.isEmpty && posKW.isEmpty && !positiveGenreIDs.isEmpty {
                group.addTask {
                    let items = (try? await tmdb.discoverThematic(personIDs: [], keywordIDs: [], genreIDs: positiveGenreIDs, filter: filter)) ?? []
                    return Batch(items: items, facetLabel: "")
                }
            }
            // Raw text search as a safety net
            group.addTask {
                let items = (try? await tmdb.search(query: rawQuery, filter: filter)) ?? []
                return Batch(items: items, facetLabel: "")
            }
            for await batch in group { batches.append(batch) }
        }

        // Build per-item facet sets and item map
        var itemFacets: [MediaKey: Set<String>] = [:]
        var itemMap: [MediaKey: MediaItem] = [:]

        for batch in batches {
            for item in batch.items {
                itemMap[item.key] = item
                if !batch.facetLabel.isEmpty {
                    itemFacets[item.key, default: []].insert(batch.facetLabel)
                } else {
                    // Text fallback: check which parsed terms appear in title/overview
                    let text = "\(item.title) \(item.overview)".lowercased()
                    for person in resolvedPeople where text.contains(person.name.lowercased()) {
                        itemFacets[item.key, default: []].insert(person.name)
                    }
                    for kw in posKW where text.contains(kw.term.lowercased()) {
                        itemFacets[item.key, default: []].insert(kw.term)
                    }
                    for theme in parsed.positiveThemes where text.contains(theme.lowercased()) {
                        itemFacets[item.key, default: []].insert(theme)
                    }
                }
                // Genre facets
                let itemGenres = Set(item.genreIDs)
                if !itemGenres.intersection(positiveGenreIDs).isEmpty {
                    for genre in parsed.genres where !itemGenres.intersection(Self.genreIDsForName(genre)).isEmpty {
                        itemFacets[item.key, default: []].insert(genre)
                    }
                }
            }
        }

        // Score each candidate
        let avoidedTitleKeys = Set(avoided.map(\.key))
        let likedTitleKeys   = Set(liked.map(\.key))

        return itemMap.values.compactMap { item in
            // Exclude the reference films themselves and avoided titles
            guard !likedTitleKeys.contains(item.key), !avoidedTitleKeys.contains(item.key) else { return nil }

            let positiveHits = Array(itemFacets[item.key] ?? [])
            let itemGenres = Set(item.genreIDs)
            let text = "\(item.title) \(item.overview)".lowercased()

            // Negative signal detection
            var penaltySignals: [String] = []
            var penalty = 0.0

            // Excluded genres
            let hitExcludedGenres = itemGenres.intersection(excludedGenreIDs)
            if !hitExcludedGenres.isEmpty {
                for genre in parsed.excludedGenres where !itemGenres.intersection(Self.genreIDsForName(genre)).isEmpty {
                    penaltySignals.append(genre)
                }
                penalty += Double(hitExcludedGenres.count) * 3.0
            }
            // Negative themes in text
            for theme in parsed.negativeThemes where text.contains(theme.lowercased()) {
                if !penaltySignals.contains(theme) { penaltySignals.append(theme) }
                penalty += 2.5
            }
            // Negative keyword IDs (requires item detail — best-effort text fallback above covers most cases)
            // Hard exclude if penalty is overwhelming and no positive hits
            if positiveHits.isEmpty { return nil }
            if penalty > 0 && Double(positiveHits.count) * 2.0 <= penalty { return nil }

            let score = Double(positiveHits.count) * 2.0 - penalty + min(item.voteAverage * 0.15, 1.5)

            return ThematicSearchResult(
                item: item,
                matchedFacets: positiveHits.sorted(),
                penaltySignals: penaltySignals,
                score: score
            )
        }
        .sorted { $0.score > $1.score }
    }

    // MARK: - Resolution helpers

    private func resolveReferenceTitles(titles: [String], filter: MediaFilter) async -> [MediaItem] {
        guard !titles.isEmpty else { return [] }
        return await withTaskGroup(of: MediaItem?.self) { group in
            for title in titles {
                group.addTask {
                    guard let item = try? await tmdb.search(query: title, filter: filter).first else { return nil }
                    return item
                }
            }
            var out: [MediaItem] = []
            for await r in group { if let r { out.append(r) } }
            return out
        }
    }

    private func resolvePeople(names: [String]) async -> [ResolvedPerson] {
        guard !names.isEmpty else { return [] }
        return await withTaskGroup(of: ResolvedPerson?.self) { group in
            for name in names {
                group.addTask {
                    guard let ids = try? await tmdb.personIDs(for: name), !ids.isEmpty else { return nil }
                    return ResolvedPerson(name: name, ids: ids)
                }
            }
            var out: [ResolvedPerson] = []
            for await r in group { if let r { out.append(r) } }
            return out
        }
    }

    private func resolveKeywords(themes: [String]) async -> [ResolvedKeyword] {
        guard !themes.isEmpty else { return [] }
        return await withTaskGroup(of: ResolvedKeyword?.self) { group in
            for theme in themes {
                group.addTask {
                    guard let ids = try? await tmdb.keywordIDs(for: theme), !ids.isEmpty else { return nil }
                    return ResolvedKeyword(term: theme, ids: ids)
                }
            }
            var out: [ResolvedKeyword] = []
            for await r in group { if let r { out.append(r) } }
            return out
        }
    }

    // MARK: - Genre mapping

    private static let genreNameToIDs: [String: Set<Int>] = [
        "action": [28, 10759],
        "adventure": [12, 10759],
        "animation": [16],
        "anime": [16],
        "comedy": [35],
        "crime": [80],
        "documentary": [99],
        "drama": [18],
        "family": [10751],
        "fantasy": [14, 10765],
        "history": [36],
        "historical": [36],
        "horror": [27],
        "music": [10402],
        "mystery": [9648],
        "romance": [10749],
        "romantic": [10749],
        "sci-fi": [878, 10765],
        "scifi": [878, 10765],
        "science fiction": [878, 10765],
        "thriller": [53],
        "war": [10752, 10768],
        "western": [37]
    ]

    private static func genreIDsForName(_ name: String) -> Set<Int> {
        genreNameToIDs[name.lowercased()] ?? []
    }
}
