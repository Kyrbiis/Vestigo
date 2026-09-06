import SwiftUI
import Foundation

extension VestigoModel {

    private enum ImportMatchOutcome {
        case found(MediaItem)
        case ambiguous([MediaItem])
        case ambiguousYearNotFound([MediaItem])
        case notFound
    }

    func importWatchedText(_ text: String, format: WatchedImportEntry.ImportFormat = .automatic) async -> ImportResult {
        let entries = WatchedImportEntry.report(for: text, format: format).entries
        return await importEntries(entries)
    }

    func importLetterboxdText(_ text: String) async -> ImportResult {
        let entries = WatchedImportEntry.parseLetterboxd(text)
        return await importEntries(entries)
    }

    func importEntries(_ entries: [WatchedImportEntry]) async -> ImportResult {
        guard !entries.isEmpty else { return ImportResult(notFound: [], ambiguous: []) }

        // Local library index — used only as fallback when TMDb finds nothing
        var localIndex: [String: MediaItem] = [:]
        for item in library.watchedItems {
            let key = WatchedImportEntry.normalizedTitle(item.title) + ":" + (item.kind == .tv ? "s" : "m")
            localIndex[key] = item
        }

        // Group entries by (normalizedTitle:mediaFilter) key — deduplicates network searches
        var entryGroups: [String: [WatchedImportEntry]] = [:]
        var keyOrder: [String] = []
        for entry in entries {
            let norm = WatchedImportEntry.normalizedTitle(entry.title)
            let typeKey = entry.mediaFilter == .movie ? "m" : "s"
            let key = norm + ":" + typeKey
            if entryGroups[key] == nil { keyOrder.append(key) }
            entryGroups[key, default: []].append(entry)
        }

        // Always search TMDb so ambiguous titles always surface the disambiguation popup,
        // even if the title was previously imported and is already in the library.
        var searchOutcomes: [String: ImportMatchOutcome] = [:]
        await withTaskGroup(of: (String, ImportMatchOutcome).self) { group in
            for key in keyOrder {
                let entry = entryGroups[key]![0]
                group.addTask { (key, (try? await self.findImportMatch(for: entry)) ?? .notFound) }
            }
            for await (key, outcome) in group {
                searchOutcomes[key] = outcome
            }
        }

        var notFound: [String] = []
        var ambiguous: [ImportAmbiguity] = []
        for key in keyOrder {
            let groupEntries = entryGroups[key]!
            let primaryEntry = groupEntries[0]
            // Fall back to the local library item only when TMDb finds nothing at all
            let tmdbOutcome = searchOutcomes[key] ?? .notFound
            let outcome: ImportMatchOutcome
            if case .notFound = tmdbOutcome, let local = localIndex[key] {
                outcome = .found(local)
            } else {
                outcome = tmdbOutcome
            }
            switch outcome {
            case .found(let match):
                library.markWatched(match)
                library.recordWatchOrderChange(for: match)
                library.setWatchedDateIfUnset(for: match.key, date: primaryEntry.watchedDate ?? .now)
                if let rating = primaryEntry.rating { library.ratings[match.key] = rating }
                if primaryEntry.isFavourite { library.favouriteKeys.insert(match.key) }
                generateDynamicCollections(from: match)
            case .ambiguous(let candidates):
                ambiguous.append(ImportAmbiguity(entries: groupEntries, candidates: candidates))
            case .ambiguousYearNotFound(let candidates):
                ambiguous.append(ImportAmbiguity(entries: groupEntries, candidates: candidates, yearNotFound: true))
            case .notFound:
                notFound.append(contentsOf: groupEntries.map(\.rawText))
            }
        }

        saveLocalSoon()
        scheduleRecommendationsRefresh()
        return ImportResult(notFound: notFound, ambiguous: ambiguous)
    }

    func commitAmbiguousImport(_ ambiguity: ImportAmbiguity, choices: [MediaItem]) {
        for (index, choice) in choices.enumerated() {
            library.markWatched(choice)
            library.recordWatchOrderChange(for: choice)
            let entry = ambiguity.entries[min(index, ambiguity.entries.count - 1)]
            library.setWatchedDateIfUnset(for: choice.key, date: entry.watchedDate ?? .now)
            if let rating = entry.rating { library.ratings[choice.key] = rating }
            if entry.isFavourite { library.favouriteKeys.insert(choice.key) }
            generateDynamicCollections(from: choice)
        }
        saveLocalSoon()
        scheduleRecommendationsRefresh()
    }

    func prepareExport(format: ExportFormat = .text) {
        let entries = library.watchedItems
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { item in
                WatchedImportEntry.exportLine(
                    for: item,
                    rating: library.ratings[item.key],
                    isFavourite: library.isFavourite(item)
                )
            }

        exportDocument = ExportDocument(text: entries.joined(separator: format.separator))
        exportFormat = format
        showExporter = true
    }

    private func findImportMatch(for entry: WatchedImportEntry) async throws -> ImportMatchOutcome {
        let filter = entry.mediaFilter
        let results = try await tmdb.search(query: entry.title, filter: filter, includeAdult: !settings.hideAdultResults)
        let normalizedTitle = WatchedImportEntry.normalizedTitle(entry.title)

        let filtered = results.filter { $0.kind == .movie || $0.kind == .tv }
        var exactMatches = filtered.filter {
            WatchedImportEntry.matchScore($0.title, normalizedTitle: normalizedTitle) == 100
        }

        if let year = entry.year {
            let yearFiltered = exactMatches.filter { $0.releaseYearInt == year }
            if !yearFiltered.isEmpty {
                exactMatches = yearFiltered
            } else if !exactMatches.isEmpty {
                // Exact title matches exist but none have this year — show popup with year hint
                return .ambiguousYearNotFound(exactMatches)
            }
            // No exact title matches — fall through to partial match + year logic below
        }

        if exactMatches.count > 1 { return .ambiguous(exactMatches) }
        if let one = exactMatches.first { return .found(one) }

        // No exact title match — prefer results with a matching year (handles spelling diffs)
        if let year = entry.year {
            let yearMatches = filtered.filter { $0.releaseYearInt == year }
            if yearMatches.count == 1 { return .found(yearMatches[0]) }
            if yearMatches.count > 1 { return .ambiguous(yearMatches) }
            // Year provided but no result matches it at all
            if !filtered.isEmpty { return .ambiguousYearNotFound(filtered) }
        }

        let best = filtered.sorted { lhs, rhs in
            let l = WatchedImportEntry.matchScore(lhs.title, normalizedTitle: normalizedTitle)
            let r = WatchedImportEntry.matchScore(rhs.title, normalizedTitle: normalizedTitle)
            return l != r ? l > r : lhs.voteAverage > rhs.voteAverage
        }.first

        return best.map { .found($0) } ?? .notFound
    }

    func clearAllData() {
        library = UserLibrary()
        settings = AppSettings()

        searchFilter = settings.defaultSearchFilter
        mediaFilter = settings.defaultHomeFilter
        searchFiltersExpanded = false
        expandedSearchFilterSections.removeAll()
        selectedRuntimeFilters.removeAll()
        selectedDateFilters.removeAll()
        minimumTMDbRatingFilter = nil

        searchText = ""
        searchResults = []
        searchPeopleResults = []

        selectedItem = nil
        selectedPerson = nil
        homePath.removeAll()
        searchPath.removeAll()

        saveLocal()
        Task { await loadHome() }
    }

}
