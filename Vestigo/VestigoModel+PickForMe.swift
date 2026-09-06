import SwiftUI
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

extension VestigoModel {

    func pickForMeRecommendations(for answers: PickForMeAnswers) async -> [MediaItem] {
        let effectiveFilter = answers.effectiveMediaFilter
        let watchProviderIDs: Set<Int>? = {
            guard answers.myServicesOnly == true, !settings.subscribedServiceNames.isEmpty else { return nil }
            let ids = KnownStreamingService.tmdbProviderIDs(for: settings.subscribedServiceNames)
            return ids.isEmpty ? nil : ids
        }()
        let watchRegion = settings.streamingRegion.rawValue
        let wantsNewReleaseResults = answers.releaseAge == .newReleases
        var sourceMaterialCandidateKeys: Set<MediaKey> = []
        var sourceMaterialItems: [MediaItem] = []

        // -- GROQ PATH (disabled — re-enable by setting useGroq = true) --
        // let useGroq = false
        // let thematicQuery = answers.pickForMeGroqFullQuery ?? answers.pickForMeThematicQuery
        // var thematicCandidates: [MediaItem] = []
        // var rerankScores: [MediaKey: Int] = [:]
        // if useGroq, let query = thematicQuery {
        //     thematicCandidates = await pickForMeThematicCandidates(query: query, filter: effectiveFilter)
        //     if thematicCandidates.count >= 5 {
        //         rerankScores = await pickForMeGroqRerank(candidates: thematicCandidates, query: query)
        //     }
        // }
        // -- END GROQ PATH --

        if let sourceMaterial = answers.sourceMaterial, sourceMaterial != .noPreference {
            do {
                let sm = try await tmdb.discoverSourceMaterial(sourceMaterial, filter: effectiveFilter)
                sourceMaterialCandidateKeys = Set(sm.map(\.key))
                sourceMaterialItems = sm
            } catch { }
        }

        // Run primary broad discovery + all archetype-specific genre combos in parallel
        let primaryGenreIDs = pickForMeDiscoveryGenreIDs(for: answers)
        let supplementalGroups = pickForMeSupplementalDiscoveryGenreIDs(for: answers)

        var discoveredItems: [MediaItem] = []
        await withTaskGroup(of: [MediaItem].self) { group in
            // Primary discovery — OR genres, 3 pages
            if !primaryGenreIDs.isEmpty {
                group.addTask { [weak self] in
                    guard let self else { return [] }
                    return (try? await self.tmdb.discoverPickForMe(
                        filter: effectiveFilter,
                        genreIDs: primaryGenreIDs,
                        runtimeRange: answers.runtimeRange,
                        minimumRating: 0,
                        includeAdult: !self.settings.hideAdultResults,
                        sortBy: "vote_average.desc",
                        watchProviderIDs: watchProviderIDs,
                        watchRegion: watchRegion
                    )) ?? []
                }
            }
            // Supplemental archetype combos — AND genres via discoverThematic (2 pages each)
            for genreGroup in supplementalGroups {
                let ids = genreGroup
                group.addTask { [weak self] in
                    guard let self else { return [] }
                    return (try? await self.tmdb.discoverThematic(
                        personIDs: [],
                        keywordIDs: [],
                        genreIDs: ids,
                        filter: effectiveFilter,
                        watchProviderIDs: watchProviderIDs,
                        watchRegion: watchRegion
                    )) ?? []
                }
            }
            // Keyword discovery for primary archetypes — finds archetype-specific films that
            // may not appear in the top pages of a genre-sorted list (e.g. heist films with
            // a 7.2 rating sit past page 3 of the Crime genre sorted by vote_average.desc)
            for archetype in answers.archetypes where !archetype.isAnyOption {
                for kw in archetype.discoveryKeywords {
                    let keyword = kw
                    group.addTask { [weak self] in
                        guard let self else { return [] }
                        let kwIDs = (try? await self.tmdb.keywordIDs(for: keyword)) ?? []
                        guard !kwIDs.isEmpty else { return [] }
                        return (try? await self.tmdb.discoverThematic(
                            personIDs: [],
                            keywordIDs: kwIDs,
                            genreIDs: [],
                            filter: effectiveFilter,
                            watchProviderIDs: watchProviderIDs,
                            watchRegion: watchRegion
                        )) ?? []
                    }
                }
            }
            for await items in group {
                discoveredItems.append(contentsOf: items)
            }
        }

        var pool = (
            recommendations +
            moreLikeLastWatched +
            moreLikeFavourite +
            fromTopGenre +
            seriesNext +
            library.watchlistItems
        )
        if wantsNewReleaseResults {
            pool.append(contentsOf: newReleases + trySomethingNewRecommendations)
        }
        pool.append(contentsOf: discoveredItems)
        pool.append(contentsOf: sourceMaterialItems)
        let uniqueCandidates = pool.uniqued()

        await loadPickForMeStrictFilterDetails(for: uniqueCandidates, answers: answers)

        // Load external ratings for the first 60 candidates (RT penalty + IMDb sort)
        await withTaskGroup(of: Void.self) { group in
            for item in uniqueCandidates.prefix(60) where externalRatingsCache[item.key] == nil {
                group.addTask { await self.loadExternalRatings(item) }
            }
        }

        let filtered = uniqueCandidates
            .uniqued()
            .filter { item in
                guard !library.isNeverShowAgain(item.key) else { return false }
                guard !settings.hideUpcomingFromRecommended || !item.isUpcoming else { return false }
                guard effectiveFilter == .both || item.kind.rawValue == effectiveFilter.rawValue else { return false }

                // Exclude obscure titles with very few votes — prevents tag-matched noise from surfacing
                if let count = item.voteCount, count < 200 { return false }

                if !pickForMeRuntimeAllows(item, runtimeRange: answers.runtimeRange) {
                    return false
                }

                if !pickForMeReleaseAgeAllows(item, releaseAge: answers.releaseAge) {
                    return false
                }

                if !pickForMeDocumentaryAllows(item, answers: answers) {
                    return false
                }

                if !pickForMeFictionAllows(item, answers: answers) {
                    return false
                }

                if !pickForMeHistoryAllows(item, answers: answers) {
                    return false
                }

                if !answers.contentRatings.isEmpty && !answers.contentRatings.contains(.any) {
                    if let detailRating = detailsCache[item.key]?.ageRating,
                       !detailRating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       !PickForMeContentRating.selectionAllows(answers.contentRatings, rating: detailRating) {
                        return false
                    }
                }

                if answers.dealBreakers.contains(where: { pickForMeFastDealBreakerMatches(item: item, dealBreaker: $0) }) {
                    return false
                }

                if let minimumRating = answers.minimumRating, let min = minimumRating.minimumRating {
                    let rating = ratingSortValue(for: item)
                    if rating > 0, rating < min - 0.5 {
                        return false
                    }
                }

                if !pickForMePrimaryArchetypeAllows(item, answers: answers) {
                    return false
                }

                if answers.myServicesOnly == true, !settings.subscribedServiceNames.isEmpty {
                    if let options = providerCache[item.key] {
                        let subscribed = settings.subscribedServiceNames
                        let available = options.contains { option in
                            let t = option.type.lowercased()
                            return ["subscription", "sub", "free"].contains(t) && option.isSubscribed(in: subscribed)
                        }
                        if !available { return false }
                    }
                }

                return true
            }

        let prepared = preparedResults(filtered, hideWatched: false)
        let visible = prepared.filter { item in
            if shouldHideAsShortFilm(item, enabled: true) {
                return false
            }

            if shouldHideAsSupplementalContent(item, enabled: settings.hideExtrasAndPromosFromRecommended) {
                return false
            }

            return true
        }

        let sorted = visible
            .sorted { lhs, rhs in
                let lhsScore = pickForMeScore(lhs, answers: answers, sourceMaterialCandidateKeys: sourceMaterialCandidateKeys)
                let rhsScore = pickForMeScore(rhs, answers: answers, sourceMaterialCandidateKeys: sourceMaterialCandidateKeys)

                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }

                let lhsRating = ratingSortValue(for: lhs)
                let rhsRating = ratingSortValue(for: rhs)
                if lhsRating != rhsRating {
                    return lhsRating > rhsRating
                }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        let lateFiltered = pickForMeApplyLateContentDealBreakers(to: sorted, answers: answers)

        return balancedPickForMeResults(lateFiltered, filter: effectiveFilter, limit: 120)
    }

    private func pickForMeDiscoveryGenreIDs(for answers: PickForMeAnswers) -> Set<Int> {
        var genreIDs: Set<Int> = []

        if answers.wantsStrictHistorical {
            genreIDs.formUnion(pickForMeHistoricalGenreIDs)
        }

        if answers.wantsHumanTriumph {
            genreIDs.insert(18)
        }

        for genrePreference in answers.genrePreferences {
            switch genrePreference {
            case .history:
                break
            case .war:
                genreIDs.formUnion(pickForMeWarGenreIDs)
            case .crime:
                genreIDs.insert(80)
            case .sciFi:
                genreIDs.formUnion([878, 10765])
            case .fantasy:
                genreIDs.formUnion([14, 10765])
            case .horror:
                genreIDs.insert(27)
            case .romance:
                genreIDs.insert(10749)
            case .animation:
                genreIDs.insert(16)
            case .family:
                genreIDs.formUnion([10751, 10762])
            case .action:
                genreIDs.insert(28)
            case .comedy:
                genreIDs.insert(35)
            case .space:
                genreIDs.formUnion([878, 10765])  // Sci-Fi — closest available TMDb genre for space
            case .noPreference:
                break
            }
        }

        return genreIDs
    }

    private func pickForMeSupplementalDiscoveryGenreIDs(for answers: PickForMeAnswers) -> [Set<Int>] {
        var genreIDs: [Set<Int>] = []

        func append(_ ids: Set<Int>) {
            guard !ids.isEmpty, !genreIDs.contains(ids) else { return }
            genreIDs.append(ids)
        }

        let archetypes = answers.archetypes.union(answers.secondaryArchetypes)
        for archetype in archetypes {
            switch archetype {
            case .feelGood:
                append([35, 10751])  // Comedy AND Family
                append([35])
            case .comedy:
                append([35])
            case .mystery:
                append([9648])
                append([9648, 53])   // Mystery AND Thriller
            case .thriller:
                append([53])
                append([53, 9648])   // Thriller AND Mystery
            case .smartProblems:
                append([18, 53])     // Drama AND Thriller
                append([18, 80])     // Drama AND Crime
            case .mission:
                append([28, 53])     // Action AND Thriller
                append([28])
            case .heist:
                append([80, 53])     // Crime AND Thriller — Ocean's Eleven, Heat
                append([53])         // Thriller alone — catches sophisticated capers not tagged Crime
                append([80])         // Crime alone — broader net
                append([35, 80])     // Comedy AND Crime — caper comedies
            case .adventure:
                append([12])
                append([12, 28])     // Adventure AND Action
            case .characterRelationships:
                append([18, 10749])  // Drama AND Romance
                append([18, 10751])  // Drama AND Family
                append([18])
            case .humanTriumph:
                append([18])
                append([18, 36])     // Drama AND History — biopics, real triumph stories
            case .documentary:
                append([99])
            case .historical:
                append([36])
                append([36, 18])     // History AND Drama
            case .war:
                append(pickForMeWarGenreIDs)
                append([10752, 18])  // War AND Drama
            case .epicSpectacle:
                append([12, 14])     // Adventure AND Fantasy
                append([12, 878])    // Adventure AND Sci-Fi
                append([28, 12])     // Action AND Adventure
            case .mindBending:
                append([9648, 878])  // Mystery AND Sci-Fi
                append([9648, 53])   // Mystery AND Thriller
                append([878, 53])    // Sci-Fi AND Thriller
            case .horror:
                append([27])
                append([27, 53])     // Horror AND Thriller
            case .thoughtfulSciFi:
                append([878, 18])    // Sci-Fi AND Drama
                append([878])
            case .surprise, .noPreference:
                break
            }
        }

        return Array(genreIDs.prefix(6))
    }

    private func balancedPickForMeResults(_ items: [MediaItem], filter: MediaFilter, limit: Int) -> [MediaItem] {
        guard filter == .both else { return items.prefixArray(limit) }

        let limitedItems = items.prefixArray(limit)
        let maximumPerKind = max(Int(ceil(Double(limitedItems.count) * 0.8)), 1)
        var counts: [MediaKind: Int] = [:]
        var balanced: [MediaItem] = []

        for item in items {
            guard balanced.count < limit else { break }
            let currentCount = counts[item.kind, default: 0]
            guard currentCount < maximumPerKind else { continue }

            balanced.append(item)
            counts[item.kind, default: 0] = currentCount + 1
        }

        return balanced
    }

}
