import SwiftUI
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

extension VestigoModel {

    func pickForMeRuntimeAllows(_ item: MediaItem, runtimeRange: PickForMeRuntimeRange) -> Bool {
        guard item.kind == .movie else { return true }
        guard runtimeRange.hasConstraint else { return true }
        guard let minutes = detailsCache[item.key]?.runtime ?? item.runtime else { return true }

        return runtimeRange.contains(minutes)
    }

    func loadPickForMeStrictFilterDetails(for items: [MediaItem], answers: PickForMeAnswers) async {
        await withTaskGroup(of: Void.self) { group in
            for item in items.prefix(120) where detailsCache[item.key] == nil {
                group.addTask { [weak self] in
                    guard let self else { return }
                    do {
                        let detail = try await self.tmdb.detail(for: item, regionCode: self.settings.streamingRegion.rawValue)
                        await MainActor.run { self.detailsCache[item.key] = detail }
                    } catch { }
                }
            }
        }
    }

    func pickForMeReleaseAgeAllows(_ item: MediaItem, releaseAge: PickForMeReleaseAge?) -> Bool {
        guard let releaseAge, releaseAge != .noPreference else { return true }
        guard let releaseDate = item.releaseDateValue else { return false }
        let now = Date()
        guard releaseDate <= now else { return false }

        if releaseAge == .newReleases {
            guard let cutoffDate = Calendar.current.date(byAdding: .month, value: -6, to: now) else {
                return false
            }
            return releaseDate >= cutoffDate
        }

        let yearsOld = Calendar.current.dateComponents([.year], from: releaseDate, to: now).year ?? 0

        if let maximumYearsOld = releaseAge.maximumYearsOld {
            return yearsOld <= maximumYearsOld
        }

        if let minimumYearsOld = releaseAge.minimumYearsOld {
            return yearsOld > minimumYearsOld
        }

        return true
    }

    func pickForMeDocumentaryAllows(_ item: MediaItem, answers: PickForMeAnswers) -> Bool {
        guard answers.wantsDocumentary else { return true }
        return item.genreIDs.contains(99)
    }

    func pickForMeSourceMaterialAllows(_ item: MediaItem, sourceMaterial: PickForMeSourceMaterial?, sourceMaterialCandidateKeys: Set<MediaKey>) -> Bool {
        guard let sourceMaterial, sourceMaterial != .noPreference else { return true }
        if sourceMaterialCandidateKeys.contains(item.key) { return true }

        let text = pickForMeSearchableText(for: item)
        return pickForMeSourceMaterialTextMatches(text, sourceMaterial: sourceMaterial)
    }

    func pickForMeSourceMaterialScore(item: MediaItem, text: String, sourceMaterial: PickForMeSourceMaterial, sourceMaterialCandidateKeys: Set<MediaKey>) -> Double {
        guard sourceMaterial != .noPreference else { return 0 }
        if sourceMaterialCandidateKeys.contains(item.key) || pickForMeSourceMaterialTextMatches(text, sourceMaterial: sourceMaterial) {
            return 18.0
        }

        return -1.5
    }

    func pickForMeSourceMaterialTextMatches(_ text: String, sourceMaterial: PickForMeSourceMaterial) -> Bool {
        switch sourceMaterial {
        case .book:
            return text.containsAny(["based on the novel", "based on a novel", "based on the book", "based on a book", "adapted from the novel", "adapted from a novel", "book by", "novel by"])
        case .game:
            return text.containsAny(["based on the video game", "based on a video game", "video game", "videogame", "game series", "computer game"])
        case .noPreference:
            return true
        }
    }

    func pickForMeFictionAllows(_ item: MediaItem, answers: PickForMeAnswers) -> Bool {
        guard let pref = answers.fictionPreference, !pref.isAnyOption else { return true }
        let genres = Set(item.genreIDs)
        let text = pickForMeSearchableText(for: item)

        switch pref {
        case .nonFiction:
            return genres.contains(99) || pickForMeIsNonfictionOrTrueEvent(genres: genres, text: text)
        case .basedOnTrueStory:
            return pickForMeIsNonfictionOrTrueEvent(genres: genres, text: text)
        case .fiction, .noPreference:
            return true
        }
    }

    func pickForMeHistoryAllows(_ item: MediaItem, answers: PickForMeAnswers) -> Bool {
        guard answers.wantsStrictHistorical else { return true }

        let historicalScore = pickForMeHistoricalEventScore(genres: Set(item.genreIDs), text: pickForMeSearchableText(for: item))
        return historicalScore > 0
    }

    func pickForMeScore(_ item: MediaItem, answers: PickForMeAnswers, sourceMaterialCandidateKeys: Set<MediaKey>) -> Double {
        let primaryAlignment = pickForMePrimaryArchetypeAlignmentScore(item, answers: answers)
        var score = primaryAlignment * 15.0  // was 13.0 — compensates for removed Groq +20 bonus
        let genreIDs = Set(item.genreIDs)
        let text = pickForMeSearchableText(for: item)

        if library.isNotInterested(item.key) {
            score -= 40.0
        }

        if library.isNeverShowAgain(item.key) {
            score -= 250.0
        }

        score += pickForMePrimaryArchetypeSoftGateAdjustment(primaryAlignment, answers: answers)

        let primaryArchetypeScores = answers.archetypes.map { archetype in
            pickForMeArchetypeScore(item: item, archetype: archetype)
        }

        for (archetype, archetypeScore) in zip(answers.archetypes, primaryArchetypeScores) {
            score += archetypeScore * (archetype == .surprise ? 0.65 : 1.0)
        }

        for secondaryArchetype in answers.secondaryArchetypes where !secondaryArchetype.isAnyOption {
            score += pickForMeArchetypeScore(item: item, archetype: secondaryArchetype) * 0.42
        }

        score += pickForMeArchetypeCombinationBonus(primaryScores: primaryArchetypeScores)

        for genrePreference in answers.genrePreferences where !genrePreference.isAnyOption {
            score += pickForMeGenrePreferenceScore(genres: genreIDs, text: text, genrePreference: genrePreference)
        }

        if let sourceMaterial = answers.sourceMaterial {
            score += pickForMeSourceMaterialScore(item: item, text: text, sourceMaterial: sourceMaterial, sourceMaterialCandidateKeys: sourceMaterialCandidateKeys)
        }

        score += pickForMeAnswerFulfillmentScore(
            item: item,
            genres: genreIDs,
            text: text,
            answers: answers,
            sourceMaterialCandidateKeys: sourceMaterialCandidateKeys
        )

        if let minimumRating = answers.minimumRating {
            score += pickForMeMinimumRatingScore(for: item, minimumRating: minimumRating)
        }

        score -= pickForMeRottenTomatoesPenalty(for: item)

        if item.genreIDs.contains(99) && !answers.wantsDocumentary {
            score -= pickForMeDocumentaryDownweight(for: answers)
        }

        score += pickForMeAnimationAdultThemeAdjustment(genres: genreIDs, answers: answers)
        score += pickForMeChildAnimationSettingsAdjustment(item: item, genres: genreIDs, answers: answers)

        score -= pickForMeArchetypeMismatchPenalty(genres: genreIDs, text: text, answers: answers)

        if answers.wantsHistorical && !genreIDs.intersection(pickForMeWarGenreIDs).isEmpty && !answers.wantsWar {
            score -= pickForMeHistoricalWarDownweight(for: answers)
        }

        if shouldPenalizeMissingContentRating(item, answers: answers) {
            score -= 1.5
        }

        score += max(ratingSortValue(for: item), 0) * 0.25

        if library.isInWatchlist(item.key) {
            score += 0.5
        }

        if recommendations.contains(where: { $0.key == item.key }) ||
            moreLikeLastWatched.contains(where: { $0.key == item.key }) ||
            moreLikeFavourite.contains(where: { $0.key == item.key }) {
            score += 0.3
        }

        score += pickForMePersonalizationScore(for: item) * 0.22  // was 0.18 — library signal more important without Groq

        // -- GROQ SCORE BONUSES (disabled with Groq path) --
        // if thematicCandidateKeys.contains(item.key) { score += 20.0 }
        // if let rank = rerankScores[item.key] { score += max(0.0, 16.0 - Double(rank - 1) * 1.5) }
        // -- END GROQ BONUSES --

        return score
    }

    func pickForMePrimaryArchetypeAllows(_ item: MediaItem, answers: PickForMeAnswers) -> Bool {
        guard pickForMeHasDominantPrimaryArchetype(answers) else { return true }
        return pickForMePrimaryArchetypeAlignmentScore(item, answers: answers) >= 3.2
    }

    func pickForMePrimaryArchetypeSoftGateAdjustment(_ alignment: Double, answers: PickForMeAnswers) -> Double {
        guard pickForMeHasDominantPrimaryArchetype(answers) else { return 0 }

        if alignment >= 6.5 {
            return 18.0  // was 14.0
        }

        if alignment >= 4.5 {
            return 8.0   // was 6.0
        }

        if alignment >= 3.2 {
            return -14.0
        }

        return -240.0
    }

    func pickForMePrimaryArchetypeAlignmentScore(_ item: MediaItem, answers: PickForMeAnswers) -> Double {
        let primaryArchetypes = answers.archetypes.filter { archetype in
            !archetype.isAnyOption && archetype != .surprise
        }

        guard !primaryArchetypes.isEmpty else { return 0 }
        return primaryArchetypes.map { pickForMeArchetypeScore(item: item, archetype: $0) }.max() ?? 0
    }

    func pickForMeHasDominantPrimaryArchetype(_ answers: PickForMeAnswers) -> Bool {
        answers.archetypes.contains { archetype in
            !archetype.isAnyOption && archetype != .surprise
        }
    }

    func pickForMeAnswerFulfillmentScore(item: MediaItem, genres: Set<Int>, text: String, answers: PickForMeAnswers, sourceMaterialCandidateKeys: Set<MediaKey>) -> Double {
        var score = 0.0

        for secondaryArchetype in answers.secondaryArchetypes where !secondaryArchetype.isAnyOption {
            let match = pickForMeArchetypeScore(item: item, archetype: secondaryArchetype)
            if match >= 4.0 {
                score += 4.0
            } else if match >= 2.0 {
                score += 1.5
            }
        }

        for genrePreference in answers.genrePreferences where !genrePreference.isAnyOption {
            if pickForMeGenrePreferenceScore(genres: genres, text: text, genrePreference: genrePreference) > 0 {
                score += 2.5
            }
        }

        if let sourceMaterial = answers.sourceMaterial, sourceMaterial != .noPreference {
            if sourceMaterialCandidateKeys.contains(item.key) || pickForMeSourceMaterialTextMatches(text, sourceMaterial: sourceMaterial) {
                score += 5.0
            }
        }

        if let minimumRating = answers.minimumRating, let minimum = minimumRating.minimumRating, ratingSortValue(for: item) >= minimum {
            score += 5.0
        }

        if !answers.contentRatings.isEmpty && !answers.contentRatings.contains(.any) {
            score += 1.0
        }

        if answers.runtimeRange.hasConstraint {
            score += 1.0
        }

        if answers.releaseAge != nil && answers.releaseAge != .noPreference {
            score += 1.0
        }

        return score
    }

    func cachedArchetypeInference(for item: MediaItem) -> ArchetypeInference? {
        guard let detail = detailsCache[item.key], !detail.keywordNames.isEmpty else { return nil }
        if let cached = archetypeInferenceCache[item.key] { return cached }
        let input = ArchetypeInferenceInput(
            genreIDs: item.genreIDs,
            keywordNames: detail.keywordNames,
            networkNames: detail.networkNames,
            numberOfSeasons: detail.seasons.isEmpty ? nil : detail.seasons.count,
            runtime: detail.runtime,
            isInCollection: detail.tmdbCollectionID != nil,
            isTV: item.kind == .tv
        )
        let inference = ArchetypeInferenceEngine.infer(from: input)
        archetypeInferenceCache[item.key] = inference
        return inference
    }

    func pickForMeArchetypeScore(item: MediaItem, archetype: PickForMeArchetype) -> Double {
        let genres = Set(item.genreIDs)
        let text = pickForMeSearchableText(for: item)
        let inferenceBonus = (cachedArchetypeInference(for: item)?.confidence(for: archetype) ?? 0) * 5.0

        let base: Double
        switch archetype {
        case .feelGood:
            base = pickForMeKeywordScore(text, ["optimistic", "heartwarming", "friendship", "family", "personal growth", "inspiring", "uplifting", "feel-good", "new beginning"]) * 1.8 +
                (genres.intersection([35, 10751, 18, 12]).isEmpty ? 0 : 4.2) -
                (genres.intersection([27, 10752]).isEmpty ? 0 : 1.8)
        case .comedy:
            base = pickForMeKeywordScore(text, ["satire", "buddy comedy", "workplace comedy", "funny", "comedian", "laugh"]) * 1.7 +
                (genres.contains(35) ? 5.0 : 0)
        case .mystery:
            base = pickForMeKeywordScore(text, ["detective", "investigation", "conspiracy", "murder mystery", "whodunnit", "clue", "secret"]) * 2.0 +
                (genres.intersection([9648, 53, 80]).isEmpty ? 0 : 4.6)
        case .thriller:
            base = pickForMeKeywordScore(text, ["danger", "survival", "suspense", "pursuit", "fugitive", "threat", "uncertainty", "crime"]) * 1.8 +
                (genres.intersection([53, 80, 28]).isEmpty ? 0 : 4.5)
        case .smartProblems:
            let kwScore = pickForMeKeywordScore(text, ["investigation", "journalist", "scientist", "engineer", "rescue mission", "courtroom", "legal", "historical event", "based on true", "expert", "team", "strategic", "intelligence"]) * 2.0
            var s = kwScore
            let hasGenreMatch = !genres.intersection([18, 53, 36]).isEmpty
            // Genre alone (no keyword signal) gives reduced credit — drama is too broad otherwise
            s += hasGenreMatch ? (kwScore > 0 ? 4.0 : 1.5) : 0
            if genres.contains(14) || genres.contains(27) { s -= 2.5 }
            if genres.contains(35) && !genres.contains(18) { s -= 1.2 }
            base = s
        case .mission:
            base = pickForMeKeywordScore(text, ["mission", "operation", "rescue", "espionage", "military objective", "survival objective", "special operations", "spy", "objective"]) * 2.0 +
                (genres.intersection([53, 28, 10752, 80, 36]).isEmpty ? 0 : 4.2)
        case .heist:
            let caperSignals = ["heist", "caper", "con artist", "con man", "con woman", "con game", "grifter", "confidence trick", "casino", "infiltrat", "scheme", "mastermind", "getaway", "elaborate", "jewel"]
            let bruteSignals = ["robbery", "theft", "steal", "thief", "extraction"]
            let caperCount = caperSignals.filter { text.contains($0) }.count
            let bruteCount = bruteSignals.filter { text.contains($0) }.count
            let caperScore = Double(caperCount) * 4.5
            let bruteScore = Double(bruteCount) * 0.8
            // GenreBase only meaningful when there are actual heist-related signals in the text;
            // without signals, Crime/Thriller alone isn't enough to score well as a heist film.
            let genreBase = genres.intersection([80, 53]).isEmpty ? 0.0 :
                (caperCount > 0 ? 5.5 : (bruteCount > 0 ? 4.0 : 3.5))
            base = caperScore + bruteScore + genreBase
        case .adventure:
            base = pickForMeKeywordScore(text, ["treasure", "expedition", "exploration", "archaeology", "quest", "journey", "travel"]) * 2.0 +
                (genres.intersection([12, 28, 10759]).isEmpty ? 0 : 4.4)
        case .characterRelationships:
            base = pickForMeKeywordScore(text, ["family", "friendship", "relationship", "relationships", "coming of age", "personal growth", "love"]) * 1.7 +
                (genres.intersection([18, 35, 10749]).isEmpty ? 0 : 4.0)
        case .humanTriumph:
            base = pickForMeKeywordScore(text, pickForMeHumanTriumphSignals) * 2.1 +
                (genres.intersection([18, 36]).isEmpty ? 0 : 3.2) -
                (genres.intersection([27, 878, 14]).isEmpty ? 0 : 2.0)
        case .documentary:
            base = pickForMeKeywordScore(text, ["documentary", "docuseries", "true story", "real-life", "real life", "interview", "archive", "behind the scenes"]) * 2.1 +
                (genres.contains(99) ? 6.0 : 0)
        case .historical:
            base = pickForMeHistoricalEventScore(genres: genres, text: text) * 1.65
        case .war:
            base = pickForMeKeywordScore(text, pickForMeWarDealBreakerSignals) * 2.1 +
                (genres.intersection(pickForMeWarGenreIDs).isEmpty ? 0 : 6.0)
        case .epicSpectacle:
            var s = pickForMeKeywordScore(text, pickForMeEpicSpectacleSignals) * 2.4
            if genres.contains(878) || genres.contains(10752) || genres.contains(10768) { s += 4.8 }
            if genres.contains(12) || genres.contains(14) { s += 3.4 }
            if genres.contains(28) { s += text.containsAny(pickForMeEpicSpectacleSignals) ? 2.4 : 0.8 }
            base = s
        case .mindBending:
            base = pickForMeKeywordScore(text, ["memory", "nonlinear", "alternate reality", "twist", "puzzle", "mind-bending", "reality", "dream", "subconscious", "perception", "illusion", "layers"]) * 2.1 +
                (genres.intersection([9648, 878, 53]).isEmpty ? 0 : 4.0)
        case .horror:
            base = pickForMeKeywordScore(text, ["supernatural", "monster", "possession", "slasher", "psychological horror", "terror", "dread", "haunted"]) * 2.0 +
                (genres.contains(27) ? 5.0 : 0)
        case .thoughtfulSciFi:
            base = pickForMeKeywordScore(text, ["artificial intelligence", "ethics", "future society", "technology", "consciousness", "philosophical", "experiment"]) * 2.1 +
                (genres.intersection([878, 18]).isEmpty ? 0 : 4.1) -
                (genres.intersection([28, 10752]).isEmpty ? 0 : 1.0)
        case .surprise:
            return ratingSortValue(for: item) + (library.isInWatchlist(item.key) ? 2.0 : 0)
        case .noPreference:
            return 0
        }
        return base + inferenceBonus
    }

    func pickForMeArchetypeCombinationBonus(primaryScores: [Double]) -> Double {
        let strongMatches = primaryScores.filter { $0 >= 3.5 }.count
        guard strongMatches >= 2 else { return 0 }
        return Double(strongMatches - 1) * 2.4
    }

    func pickForMeGenrePreferenceScore(genres: Set<Int>, text: String, genrePreference: PickForMeGenrePreference) -> Double {
        switch genrePreference {
        case .space:
            return genres.contains(878) || text.containsAny(["space", "planet", "astronaut", "galaxy"]) ? 1.4 : 0
        case .fantasy:
            return genres.contains(14) || text.containsAny(["magic", "fantasy", "kingdom"]) ? 1.2 : 0
        case .sciFi:
            return genres.contains(878) || genres.contains(10765) ? 1.25 : 0
        case .history:
            let historicalScore = pickForMeHistoricalEventScore(genres: genres, text: text)
            return historicalScore > 0 ? 1.0 + min(historicalScore * 0.35, 2.2) : 0
        case .crime:
            return genres.contains(80) || text.containsAny(["crime", "detective", "police"]) ? 1.15 : 0
        case .war:
            return genres.contains(10752) || genres.contains(10768) || text.contains("war") ? 1.15 : 0
        case .romance:
            return genres.contains(10749) ? 1.0 : 0
        case .animation:
            return genres.contains(16) ? 1.0 : 0
        case .family:
            return genres.contains(10751) || genres.contains(10762) ? 1.0 : 0
        case .horror:
            return genres.contains(27) ? 1.1 : 0
        case .action:
            return genres.contains(28) || text.containsAny(["action", "chase", "explosive", "combat", "fight"]) ? 1.3 : 0
        case .comedy:
            return genres.contains(35) || text.containsAny(["comedy", "comedic", "humorous", "funny"]) ? 1.2 : 0
        case .noPreference:
            return 0
        }
    }

    func pickForMeIsSpeculative(genres: Set<Int>, text: String) -> Bool {
        !genres.intersection([878, 14, 10765]).isEmpty || text.containsAny(["superhero", "magic", "alien", "monster"])
    }

    func pickForMeIsNonfictionOrTrueEvent(genres: Set<Int>, text: String) -> Bool {
        genres.contains(99) || pickForMeHistoricalEventScore(genres: genres, text: text) > 0
    }

    func pickForMeMinimumRatingScore(for item: MediaItem, minimumRating: PickForMeMinimumRating) -> Double {
        guard let minimum = minimumRating.minimumRating else { return 0 }
        let rating = ratingSortValue(for: item)

        if rating >= minimum {
            return 8.0 + min((rating - minimum) * 4.5, 13.0)
        }

        if rating >= minimum - 0.4 {
            return -12.0
        }

        if rating >= minimum - 0.8 {
            return -28.0
        }

        return -55.0
    }

    func pickForMeRottenTomatoesPenalty(for item: MediaItem) -> Double {
        guard let rt = externalRatingsCache[item.key]?.rottenTomatoesRating else { return 0 }
        if rt < 20 { return 18.0 }
        if rt < 30 { return 12.0 }
        if rt < 40 { return 6.0 }
        if rt < 50 { return 2.5 }
        return 0
    }

    private func shouldPenalizeMissingContentRating(_ item: MediaItem, answers: PickForMeAnswers) -> Bool {
        guard !answers.contentRatings.isEmpty, !answers.contentRatings.contains(.any) else { return false }
        guard let rawRating = detailsCache[item.key]?.ageRating else { return true }
        return rawRating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func pickForMeDocumentaryDownweight(for answers: PickForMeAnswers) -> Double {
        if answers.dealBreakers.contains(.documentary) {
            return 250.0
        }

        if answers.wantsHistorical {
            return 10.0
        }

        if answers.fictionPreference == .nonFiction || answers.fictionPreference == .basedOnTrueStory {
            return 5.0
        }

        return 8.0
    }

    func pickForMeHistoricalWarDownweight(for answers: PickForMeAnswers) -> Double {
        if answers.archetypes.contains(.mission) || answers.secondaryArchetypes.contains(.mission) {
            return 8.0
        }
        return 14.0
    }

    func pickForMeAnimationAdultThemeAdjustment(genres: Set<Int>, answers: PickForMeAnswers) -> Double {
        guard genres.contains(16), answers.prefersAdultLeaningMood, !answers.genrePreferences.contains(.animation) else {
            return 0
        }

        return -2.0
    }

    func pickForMeChildAnimationSettingsAdjustment(item: MediaItem, genres: Set<Int>, answers: PickForMeAnswers) -> Double {
        guard settings.hideLowestAgeRatings, genres.contains(16), !answers.genrePreferences.contains(.animation) else {
            return 0
        }

        let hasFamilyGenre = genres.contains(10751) || genres.contains(10762)
        let hasLowestAgeRating = detailsCache[item.key]?.ageRating.map(Self.isLowestAgeRating) ?? false

        return hasFamilyGenre || hasLowestAgeRating ? -3.0 : 0
    }

    func pickForMeArchetypeMismatchPenalty(genres: Set<Int>, text: String, answers: PickForMeAnswers) -> Double {
        var penalty = 0.0

        if answers.wantsHumanTriumph {
            let triumphSignalCount = pickForMeKeywordScore(text, pickForMeHumanTriumphSignals)
            let hasTriumphGenreShape = !genres.intersection([18, 36]).isEmpty && genres.isDisjoint(with: [27, 878, 14])

            if triumphSignalCount == 0 && !hasTriumphGenreShape {
                penalty += 9.0
            }

            if triumphSignalCount == 0 && !genres.intersection([80, 9648]).isEmpty {
                penalty += 10.0
            }

            if !genres.intersection([27, 878, 14]).isEmpty {
                penalty += 8.0
            }

            let actionOrWarGenres = Set([53, 28]).union(pickForMeWarGenreIDs)
            if !genres.intersection(actionOrWarGenres).isEmpty && !text.containsAny(pickForMeHumanTriumphSignals) {
                penalty += 8.0
            }
        }

        // Children's/family animation (Pixar, Disney kids, etc.) is a poor fit for deeper archetypes.
        // Adult animation (Ghost in the Shell, Paprika, Waking Life) is fine and should not be penalized.
        // Family/Kids genre (10751, 10762) combined with Animation (16) reliably identifies children's content.
        let isChildrenAnimation = genres.contains(16) && !genres.intersection([10751, 10762]).isEmpty

        // Thoughtful SciFi: kids animation almost never fits
        if answers.archetypes.contains(.thoughtfulSciFi) || answers.secondaryArchetypes.contains(.thoughtfulSciFi) {
            if isChildrenAnimation {
                penalty += 12.0
            }
            let isHighAction = !genres.intersection([28, 10752]).isEmpty && !genres.contains(18) && !genres.contains(9648)
            if isHighAction && !text.containsAny(["artificial intelligence", "consciousness", "ethics", "philosophical", "society", "human nature", "future of"]) {
                penalty += 4.0
            }
        }

        // Mind-Bending: kids animation and superhero blockbusters without specific mind-bending signals
        if answers.archetypes.contains(.mindBending) || answers.secondaryArchetypes.contains(.mindBending) {
            if isChildrenAnimation {
                penalty += 8.0
            }
            // Action + Adventure without Mystery genre and no specific mind-bending text → likely a superhero blockbuster.
            // "reality" and "mind" excluded — appear in nearly every blockbuster ("his will on all of reality", "Mind Stone").
            if genres.contains(28) && genres.contains(12) && !genres.contains(9648) &&
                !text.containsAny(["nonlinear", "alternate reality", "illusion", "paradox", "consciousness", "surreal", "mind-bending", "time loop", "unreliable"]) {
                penalty += 7.0
            }
        }

        // Smart Problems: romance content and kids animation without intellectual signals don't fit
        if answers.archetypes.contains(.smartProblems) || answers.secondaryArchetypes.contains(.smartProblems) {
            if genres.contains(10749) {
                penalty += 5.0
            }
            if text.containsAny(["forbidden love", "telenovela", "second chance at love", "love triangle", "star-crossed lovers"]) {
                penalty += 4.0
            }
            if isChildrenAnimation && !text.containsAny(["investigat", "scientist", "engineer", "journalist", "legal", "court", "expert"]) {
                penalty += 4.5
            }
        }

        return penalty
    }

    func pickForMePersonalizationScore(for item: MediaItem) -> Double {
        let itemGenres = Set(item.genreIDs)
        guard !itemGenres.isEmpty else { return 0 }

        let highlyRatedItems = library.ratings.compactMap { key, rating in
            rating >= 4 ? library.items[key] : nil
        }

        let favouriteScore = pickForMeGenreOverlapScore(itemGenres: itemGenres, sourceItems: library.favouriteItems, weight: 0.85, cap: 3.4)
        let highlyRatedScore = pickForMeGenreOverlapScore(itemGenres: itemGenres, sourceItems: highlyRatedItems, weight: 0.7, cap: 3.0)
        let watchedScore = pickForMeGenreOverlapScore(itemGenres: itemGenres, sourceItems: library.watchedItems, weight: 0.22, cap: 2.0)
        return favouriteScore + highlyRatedScore + watchedScore
    }

    func pickForMeGenreOverlapScore(itemGenres: Set<Int>, sourceItems: [MediaItem], weight: Double, cap: Double) -> Double {
        let overlapCount = sourceItems.uniqued().reduce(0) { partialResult, other in
            partialResult + (itemGenres.isDisjoint(with: Set(other.genreIDs)) ? 0 : 1)
        }

        return min(Double(overlapCount) * weight, cap)
    }

    func pickForMeFastDealBreakerMatches(item: MediaItem, dealBreaker: PickForMeDealBreaker) -> Bool {
        guard !dealBreaker.requiresLateDescriptionPass else { return false }
        return pickForMeDealBreakerMatches(item: item, dealBreaker: dealBreaker)
    }

    func pickForMeApplyLateContentDealBreakers(to items: [MediaItem], answers: PickForMeAnswers) -> [MediaItem] {
        let lateDealBreakers = answers.dealBreakers.filter(\.requiresLateDescriptionPass)
        guard !lateDealBreakers.isEmpty else { return items }

        return items.filter { item in
            !lateDealBreakers.contains { dealBreaker in
                pickForMeLateContentDealBreakerMatches(item: item, dealBreaker: dealBreaker)
            }
        }
    }

    func pickForMeLateContentDealBreakerMatches(item: MediaItem, dealBreaker: PickForMeDealBreaker) -> Bool {
        let description = item.overview.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return false }

        switch dealBreaker {
        case .graphicViolence:
            let strongGraphicSignals = ["gore", "gory", "blood-soaked", "gruesome", "massacre", "torture", "dismember", "slasher"]
            let violenceSignals = ["bloody", "brutal", "violent", "violence", "killing", "killings", "murder spree"]
            return description.containsAny(strongGraphicSignals) || pickForMeKeywordScore(description, violenceSignals) >= 2
        case .sexualContent:
            let explicitSexualSignals = ["erotic", "sex worker", "prostitute", "brothel", "stripper", "nude", "nudity", "pornographic"]
            let sexualSignals = ["sexual", "sex", "seduction", "seduces", "affair", "lust"]
            return description.containsAny(explicitSexualSignals) || pickForMeKeywordScore(description, sexualSignals) >= 2
        default:
            return false
        }
    }

    func pickForMeDealBreakerMatches(item: MediaItem, dealBreaker: PickForMeDealBreaker) -> Bool {
        guard dealBreaker != .none else { return false }

        let genres = Set(item.genreIDs)
        let text = pickForMeSearchableText(for: item)

        switch dealBreaker {
        case .horror:
            return genres.contains(27) || text.containsAny(["horror", "slasher", "haunted", "demon"])
        case .romanceHeavy:
            return genres.contains(10749) && genres.intersection([28, 12, 878, 9648, 53]).isEmpty
        case .animation:
            return genres.contains(16)
        case .documentary:
            return genres.contains(99) ||
                text.containsAny(["documentary", "docuseries", "nonfiction", "non-fiction", "concert", "live in", "live at", "world tour", "tour film", "live performance", "behind the scenes"]) ||
                (genres.contains(10402) && text.containsAny(["live", "tour", "concert", "performance"]))
        case .war:
            return !genres.intersection(pickForMeWarGenreIDs).isEmpty || text.containsAny(pickForMeWarDealBreakerSignals)
        case .graphicViolence, .sexualContent:
            return false
        case .superhero:
            return text.containsAny(["superhero", "super hero", "marvel", "dc comics", "batman", "superman", "spider-man", "spider man", "avengers", "x-men", "comic book", "mutant", "wolverine", "iron man", "captain america", "thor", "supervillain", "super villain", "gotham", "kryptonite", "professor x", "black widow", "black panther", "deadpool", "aquaman", "wonder woman", "justice league", "guardians of the galaxy", "ant-man", "doctor strange"])
        case .verySad:
            return text.containsAny(["grief", "tragedy", "terminal", "mourning", "devastating", "death of"])
        case .foreignLanguage:
            return item.originalLanguage != nil && item.originalLanguage != "en"
        case .sciFi:
            return genres.intersection([878, 10765]).count > 0 || text.containsAny(["sci-fi", "science fiction", "dystopian future", "space station", "artificial intelligence", "robot uprising", "cyberpunk"])
        case .heavyFantasy:
            return genres.contains(14) || text.containsAny(["magic", "sorcery", "wizard", "witch", "dragon", "elf", "dwarf", "hobbit", "enchanted", "dark lord", "mystical realm", "mythical creature"])
        case .none:
            return false
        }
    }

    func pickForMeKeywordScore(_ text: String, _ keywords: [String]) -> Double {
        Double(keywords.filter { text.contains($0) }.count)
    }

    func pickForMeHistoricalYearScore(_ text: String) -> Double {
        guard let currentYear = Calendar.current.dateComponents([.year], from: Date()).year else { return 0 }
        let historicalCutoffYear = currentYear - 20
        let pattern = #"\b(1[5-9][0-9]{2}|20[0-9]{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)

        for match in matches {
            guard let yearRange = Range(match.range, in: text),
                  let year = Int(text[yearRange]),
                  year <= historicalCutoffYear else {
                continue
            }

            return year <= 1975 ? 2.8 : 1.6
        }

        return 0
    }

    func pickForMeHistoricalEventScore(genres: Set<Int>, text: String) -> Double {
        let trueEventSignalCount = pickForMeKeywordScore(text, pickForMeHistoricalTrueEventSignals)
        let historicalContextSignalCount = pickForMeKeywordScore(text, pickForMeHistoricalContextSignals)
        let historicalYearScore = pickForMeHistoricalYearScore(text)
        let nonHistoricalDocumentarySignalCount = pickForMeKeywordScore(text, pickForMeNonHistoricalDocumentarySignals)
        let hasHistoricalGenre = !genres.intersection(pickForMeHistoricalGenreIDs).isEmpty
        let isDocumentary = genres.contains(99)

        let hasHistoricalYearEvidence = historicalYearScore > 0 && (trueEventSignalCount > 0 || hasHistoricalGenre)

        if historicalContextSignalCount > 0 || hasHistoricalYearEvidence {
            let keywordScore = trueEventSignalCount * 1.2 + historicalContextSignalCount * 3.4 + (hasHistoricalYearEvidence ? historicalYearScore : 0)
            let genreBonus = hasHistoricalGenre ? 3.4 : 0
            let documentaryPenalty = isDocumentary && nonHistoricalDocumentarySignalCount > 0 ? 5.0 : 0
            let generalDocumentaryPenalty = isDocumentary ? 1.8 : 0
            return keywordScore + genreBonus - documentaryPenalty - generalDocumentaryPenalty
        }

        if hasHistoricalGenre {
            let genreBonus = genres.contains(36) ? 4.0 : 3.2
            let trueEventBonus = min(trueEventSignalCount * 1.2, 2.4)
            let documentaryPenalty = isDocumentary ? 2.5 : 0
            return genreBonus + trueEventBonus - documentaryPenalty
        }

        if isDocumentary {
            return -4.0
        }

        return nonHistoricalDocumentarySignalCount > 0 ? -1.5 : 0
    }

    func pickForMeSearchableText(for item: MediaItem) -> String {
        "\(item.title) \(item.overview)".lowercased()
    }

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

    private func resolveThematicTitles(from text: String, filter: MediaFilter) async -> [MediaItem] {
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

    private func resolveThematicTitle(_ title: String, year: Int, filter: MediaFilter) async -> MediaItem? {
        guard let results = try? await tmdb.search(query: title, filter: filter), !results.isEmpty else { return nil }
        let normalized = normalizeThematicTitle(title)
        if let exact = results.first(where: { normalizeThematicTitle($0.title) == normalized }) { return exact }
        if let yearMatch = results.first(where: { thematicReleaseYear(of: $0) == year }) { return yearMatch }
        let first = results[0]
        let firstNorm = normalizeThematicTitle(first.title)
        if firstNorm.contains(normalized) || normalized.contains(firstNorm) { return first }
        return nil
    }

    private func normalizeThematicTitle(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9 ]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\b(the|a|an)\b"#, with: "", options: .regularExpression)
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func thematicReleaseYear(of item: MediaItem) -> Int? {
        guard let date = item.releaseDate, date.count >= 4 else { return nil }
        return Int(date.prefix(4))
    }

}
