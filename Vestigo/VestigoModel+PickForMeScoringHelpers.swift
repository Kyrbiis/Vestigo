import SwiftUI
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

extension VestigoModel {

    func pickForMeThematicCandidates(query: String, filter: MediaFilter) async -> [MediaItem] {
        if let cached = pickForMeThematicCache[query] { return cached }
        var results = await pickForMeGroqCandidates(query: query, filter: filter)
        if results.isEmpty {
            #if canImport(FoundationModels)
            results = await pickForMeAppleIntelligenceCandidates(query: query, filter: filter)
            #endif
        }
        pickForMeThematicCache[query] = results
        return results
    }

    func pickForMeGroqRerank(candidates: [MediaItem], query: String) async -> [MediaKey: Int] {
        let candidateData: [[String: Any]] = candidates.map { item in
            var d: [String: Any] = ["title": item.title]
            if let year = thematicReleaseYear(of: item) { d["year"] = year }
            if !item.overview.isEmpty { d["overview"] = String(item.overview.prefix(180)) }
            return d
        }
        guard let body = try? JSONSerialization.data(withJSONObject: ["query": query, "candidates": candidateData]) else { return [:] }
        var req = URLRequest(url: VestigoBackendConfiguration.baseURL.appending(path: "groq-rerank"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rankings = json["rankings"] as? [[String: Any]] else { return [:] }

        var result: [MediaKey: Int] = [:]
        for (rankIndex, entry) in rankings.enumerated() {
            guard let title = entry["title"] as? String else { continue }
            let year = entry["year"] as? Int ?? 0
            let norm = normalizeThematicTitle(title)
            if let match = candidates.first(where: {
                normalizeThematicTitle($0.title) == norm ||
                (year > 0 && thematicReleaseYear(of: $0) == year && normalizeThematicTitle($0.title).contains(norm))
            }) {
                if result[match.key] == nil { result[match.key] = rankIndex + 1 }
            }
        }
        return result
    }

    func pickForMeGroqCandidates(query: String, filter: MediaFilter) async -> [MediaItem] {
        let filterParams: [String]
        switch filter {
        case .movie: filterParams = ["movie"]
        case .tv:    filterParams = ["tv"]
        case .both:  filterParams = ["movie", "tv"]
        }

        // Build requests on MainActor before entering nonisolated task group to avoid Codable actor-isolation warnings
        let requests: [(URLRequest, MediaFilter)] = filterParams.compactMap { filterParam in
            guard let body = try? JSONSerialization.data(withJSONObject: ["query": query, "filter": filterParam]) else { return nil }
            var req = URLRequest(url: VestigoBackendConfiguration.baseURL.appending(path: "thematic-recommend"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            return (req, filterParam == "tv" ? .tv : .movie)
        }

        return await withTaskGroup(of: [MediaItem].self) { group in
            for (req, mediaFilter) in requests {
                group.addTask {
                    do {
                        let (data, response) = try await URLSession.shared.data(for: req)
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
                        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let titles = json["titles"] as? [[String: Any]] else { return [] }
                        let suggestions: [(String, Int)] = titles.compactMap { dict in
                            guard let title = dict["title"] as? String else { return nil }
                            return (title, dict["year"] as? Int ?? 0)
                        }
                        return await withTaskGroup(of: MediaItem?.self) { inner in
                            for (title, year) in suggestions {
                                inner.addTask { await self.resolveThematicTitle(title, year: year, filter: mediaFilter) }
                            }
                            var items: [MediaItem] = []
                            for await item in inner { if let item { items.append(item) } }
                            return items
                        }
                    } catch { return [] }
                }
            }
            var all: [MediaItem] = []
            for await items in group { all.append(contentsOf: items) }
            return all
        }
    }

    #if canImport(FoundationModels)
    func pickForMeAppleIntelligenceCandidates(query: String, filter: MediaFilter) async -> [MediaItem] {
        guard SystemLanguageModel.default.isAvailable else { return [] }
        let session = LanguageModelSession()
        let mediaType: String
        switch filter {
        case .movie: mediaType = "films"
        case .tv: mediaType = "TV shows"
        case .both: mediaType = "films and TV shows"
        }
        let prompt = "List 15 \(query) \(mediaType). Format each title exactly as: Title (Year). One per line. Only the title and year — no other text."
        guard let response = try? await session.respond(to: prompt) else { return [] }
        return await resolveThematicTitles(from: response.content, filter: filter)
    }
    #endif

    func resolveThematicTitles(from text: String, filter: MediaFilter) async -> [MediaItem] {
        let pattern = try? NSRegularExpression(pattern: #"(.+?)\s*\((\d{4})\)"#)
        let nsText = text as NSString
        let matches = pattern?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? []
        let suggestions: [(String, Int)] = matches.compactMap { match in
            guard match.numberOfRanges >= 3,
                  let titleRange = Range(match.range(at: 1), in: text),
                  let yearRange = Range(match.range(at: 2), in: text),
                  let year = Int(text[yearRange]) else { return nil }
            return (String(text[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines), year)
        }
        return await withTaskGroup(of: MediaItem?.self) { group in
            for (title, year) in suggestions {
                group.addTask { await self.resolveThematicTitle(title, year: year, filter: filter) }
            }
            var results: [MediaItem] = []
            for await item in group { if let item { results.append(item) } }
            return results
        }
    }

    func resolveThematicTitle(_ title: String, year: Int, filter: MediaFilter) async -> MediaItem? {
        guard let results = try? await tmdb.search(query: title, filter: filter), !results.isEmpty else { return nil }
        let normalized = normalizeThematicTitle(title)
        if let exact = results.first(where: { normalizeThematicTitle($0.title) == normalized }) { return exact }
        if let yearMatch = results.first(where: { thematicReleaseYear(of: $0) == year }) { return yearMatch }
        let first = results[0]
        let firstNorm = normalizeThematicTitle(first.title)
        if firstNorm.contains(normalized) || normalized.contains(firstNorm) { return first }
        return nil
    }

    func normalizeThematicTitle(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9 ]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\b(the|a|an)\b"#, with: "", options: .regularExpression)
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }

    func thematicReleaseYear(of item: MediaItem) -> Int? {
        guard let date = item.releaseDate, date.count >= 4 else { return nil }
        return Int(date.prefix(4))
    }
}
