import Foundation

// MARK: - PickForMe Option Protocol

protocol PickForMeOption: Identifiable, Hashable {
    var title: String { get }
    var subtitle: String? { get }
    var isAnyOption: Bool { get }
}

extension PickForMeOption {
    var subtitle: String? { nil }
    var isAnyOption: Bool { false }
}

extension MediaFilter: PickForMeOption {}

// MARK: - PickForMe Answers

struct PickForMeAnswers: Hashable, Codable {
    var mediaFormat: PickForMeMediaFormat?
    var archetypes: Set<PickForMeArchetype> = []
    var secondaryArchetypes: Set<PickForMeArchetype> = []
    var genrePreferences: Set<PickForMeGenrePreference> = []
    var fictionPreference: PickForMeFictionPreference?
    var sourceMaterial: PickForMeSourceMaterial?
    var runtimeRange: PickForMeRuntimeRange = .unconstrained
    var releaseAge: PickForMeReleaseAge?
    var contentRatings: Set<PickForMeContentRating> = []
    var minimumRating: PickForMeMinimumRating?
    var dealBreakers: Set<PickForMeDealBreaker> = []
    var myServicesOnly: Bool? = nil

    var answeredQuestionCount: Int {
        var count = 0
        if mediaFormat != nil { count += 1 }
        if !archetypes.isEmpty { count += 1 }
        if !secondaryArchetypes.isEmpty { count += 1 }
        if !genrePreferences.isEmpty { count += 1 }
        if fictionPreference != nil { count += 1 }
        if sourceMaterial != nil { count += 1 }
        if runtimeRange.hasConstraint { count += 1 }
        if releaseAge != nil { count += 1 }
        if !contentRatings.isEmpty { count += 1 }
        if minimumRating != nil { count += 1 }
        if !dealBreakers.isEmpty { count += 1 }
        return count
    }

    var meaningfulQuestionCount: Int {
        var count = 0
        if mediaFormat != nil { count += 1 }
        if !archetypes.isEmpty && !archetypes.contains(.surprise) { count += 1 }
        if !secondaryArchetypes.isEmpty && !secondaryArchetypes.contains(where: \.isAnyOption) { count += 1 }
        if !genrePreferences.isEmpty && !genrePreferences.contains(.noPreference) { count += 1 }
        if let fictionPreference, fictionPreference != .noPreference { count += 1 }
        if let sourceMaterial, sourceMaterial != .noPreference { count += 1 }
        if !isSeriesOnly && runtimeRange.hasConstraint { count += 1 }
        if let releaseAge, releaseAge != .noPreference { count += 1 }
        if !contentRatings.isEmpty && !contentRatings.contains(.any) { count += 1 }
        if let minimumRating, minimumRating != .any { count += 1 }
        if !dealBreakers.isEmpty && !dealBreakers.contains(.none) { count += 1 }
        return count
    }

    var effectiveMediaFilter: MediaFilter {
        mediaFormat?.mediaFilter ?? .both
    }

    var isSeriesOnly: Bool {
        mediaFormat == .series
    }

    var wantsDocumentary: Bool {
        archetypes.contains(.documentary) || secondaryArchetypes.contains(.documentary)
    }

    var wantsHumanTriumph: Bool {
        archetypes.contains(.humanTriumph) || secondaryArchetypes.contains(.humanTriumph)
    }

    var wantsStrictHistorical: Bool {
        archetypes.contains(.historical) ||
        secondaryArchetypes.contains(.historical)
    }

    var wantsHistoryFlavor: Bool {
        genrePreferences.contains(.history)
    }

    var wantsHistorical: Bool {
        wantsStrictHistorical || wantsHistoryFlavor
    }

    var wantsWar: Bool {
        archetypes.contains(.war) ||
        secondaryArchetypes.contains(.war) ||
        genrePreferences.contains(.war)
    }

    var wantsSpeculative: Bool {
        archetypes.contains(.thoughtfulSciFi) ||
        archetypes.contains(.mindBending) ||
        secondaryArchetypes.contains(.thoughtfulSciFi) ||
        secondaryArchetypes.contains(.mindBending) ||
        genrePreferences.contains(.sciFi) ||
        genrePreferences.contains(.fantasy) ||
        genrePreferences.contains(.space)
    }

    var prefersAdultLeaningMood: Bool {
        contentRatings.contains(.r) ||
        contentRatings.contains(.nc17) ||
        archetypes.contains(.horror) ||
        archetypes.contains(.thriller) ||
        archetypes.contains(.war) ||
        archetypes.contains(.mindBending) ||
        archetypes.contains(.smartProblems) ||
        secondaryArchetypes.contains(.horror) ||
        secondaryArchetypes.contains(.thriller) ||
        secondaryArchetypes.contains(.war) ||
        secondaryArchetypes.contains(.mindBending) ||
        secondaryArchetypes.contains(.smartProblems)
    }

    var pickForMeThematicQuery: String? {
        var terms: [String] = []
        for archetype in archetypes where !archetype.isAnyOption {
            if let t = archetype.cerebrasConceptTerm { terms.append(t) }
        }
        for archetype in secondaryArchetypes where !archetype.isAnyOption {
            if let t = archetype.cerebrasConceptTerm { terms.append(t) }
        }
        for genre in genrePreferences where !genre.isAnyOption {
            if let t = genre.cerebrasConceptTerm { terms.append(t) }
        }
        guard !terms.isEmpty else { return nil }
        return terms.joined(separator: ", ")
    }

    var pickForMeGroqFullQuery: String? {
        var lines: [String] = []

        // genre_flavor goes first — anchors every suggestion around the required setting/genre
        let genreTerms = genrePreferences.compactMap { pref -> String? in
            guard !pref.isAnyOption else { return nil }
            if let term = pref.cerebrasConceptTerm {
                return "\(pref.title) (\(term))"
            }
            return pref.title
        }
        if !genreTerms.isEmpty {
            lines.append("genre_flavor: \(genreTerms.joined(separator: "; "))")
        }

        let primaryTitles = archetypes.compactMap { $0.isAnyOption ? nil : $0.title }
        if !primaryTitles.isEmpty {
            lines.append("mood: \(primaryTitles.joined(separator: ", "))")
        }

        let secondaryTitles = secondaryArchetypes.compactMap { $0.isAnyOption ? nil : $0.title }
        if !secondaryTitles.isEmpty {
            lines.append("secondary: \(secondaryTitles.joined(separator: ", "))")
        }

        if let fp = fictionPreference, !fp.isAnyOption {
            lines.append("fiction_preference: \(fp.title)")
        }

        if let r = releaseAge, !r.isAnyOption {
            let currentYear = Calendar.current.component(.year, from: Date())
            var releaseStr = r.title
            if let maxYears = r.maximumYearsOld {
                releaseStr += " — must be released in \(currentYear - maxYears) or later"
            } else if let minYears = r.minimumYearsOld {
                releaseStr += " — must be released before \(currentYear - minYears)"
            }
            lines.append("release_window: \(releaseStr)")
        }

        if let sm = sourceMaterial, !sm.isAnyOption {
            lines.append("source: \(sm.title)")
        }

        var avoidList: [String] = []
        for db in dealBreakers {
            switch db {
            case .horror: avoidList.append("horror")
            case .romanceHeavy: avoidList.append("romance-heavy")
            case .animation: avoidList.append("animated/anime")
            case .documentary: avoidList.append("documentary")
            case .war: avoidList.append("war films")
            case .superhero: avoidList.append("superhero")
            case .foreignLanguage: avoidList.append("non-English")
            case .graphicViolence: avoidList.append("graphic violence")
            case .sexualContent: avoidList.append("explicit sexual content")
            case .verySad: avoidList.append("very sad or emotionally devastating")
            case .sciFi: avoidList.append("science fiction or sci-fi")
            case .heavyFantasy: avoidList.append("heavy fantasy, magic, or supernatural worlds")
            case .none, .longRuntime: break
            }
        }
        if !avoidList.isEmpty {
            lines.append("avoid: \(avoidList.joined(separator: ", "))")
        }

        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    var summaryTags: [String] {
        var tags: [String] = []
        if let format = mediaFormat { tags.append(format.title) }
        let archetypeTags = archetypes.filter { $0 != .surprise && $0 != .noPreference }
            .map(\.title).sorted()
        tags.append(contentsOf: archetypeTags.prefix(3))
        if tags.count < 5 {
            let genreTags = genrePreferences.filter { $0 != .noPreference }
                .map(\.title).sorted()
            tags.append(contentsOf: genreTags.prefix(5 - tags.count))
        }
        return tags
    }

    var detailTags: [String] {
        var tags: [String] = []
        let secTags = secondaryArchetypes.filter { !$0.isAnyOption }.map(\.title).sorted()
        if !secTags.isEmpty { tags.append(contentsOf: secTags.prefix(2)) }
        if let fp = fictionPreference, fp != .noPreference { tags.append(fp.title) }
        if let sm = sourceMaterial, sm != .noPreference { tags.append(sm.title) }
        if let ra = releaseAge, ra != .noPreference { tags.append(ra.title) }
        if runtimeRange.hasConstraint { tags.append(runtimeRange.displayString) }
        if let mr = minimumRating, mr != .any { tags.append("Min \(mr.title)") }
        let db = dealBreakers.filter { !$0.isAnyOption }.map { "No \($0.title.lowercased())" }.sorted()
        if !db.isEmpty { tags.append(contentsOf: db.prefix(2)) }
        return tags
    }
}

struct PickForMeRecentSearch: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var answers: PickForMeAnswers
}

// MARK: - PickForMe Steps

enum PickForMeStep: CaseIterable {
    case format, archetype, secondaryArchetypes, genrePreferences, fictionPreference, sourceMaterial, runtime, releaseAge, ageRating, minimumRating, dealBreakers, myServicesOnly

    static func steps(for answers: PickForMeAnswers) -> [PickForMeStep] {
        var steps: [PickForMeStep] = [
            .format,
            .archetype
        ]

        if !answers.archetypes.contains(.surprise) {
            steps.append(.secondaryArchetypes)
        }

        steps.append(contentsOf: [
            .genrePreferences,
            .fictionPreference
        ])

        steps.append(.sourceMaterial)

        if !answers.isSeriesOnly {
            steps.append(.runtime)
        }

        steps.append(contentsOf: [
            .releaseAge,
            .ageRating
        ])

        steps.append(contentsOf: [
            .minimumRating,
            .dealBreakers
        ])

        steps.append(.myServicesOnly)

        return steps
    }

    var title: String {
        switch self {
        case .format: return "What do you want to watch?"
        case .archetype: return "What are you in the mood for?"
        case .secondaryArchetypes: return "Anything else sound good?"
        case .genrePreferences: return "Any genre flavors you want?"
        case .fictionPreference: return "Fiction or non-fiction?"
        case .sourceMaterial: return "Adaptations?"
        case .runtime: return "How much time do you have?"
        case .releaseAge: return "How recent should it be?"
        case .ageRating: return "What content rating are you comfortable with?"
        case .minimumRating: return "How highly rated should it be?"
        case .dealBreakers: return "Any deal breakers?"
        case .myServicesOnly: return "Limit to your streaming services?"
        }
    }

    var subtitle: String? {
        switch self {
        case .format: return "Choose one."
        case .archetype: return "Choose one. Documentary is a strict filter; Historical means stories about historical events."
        case .secondaryArchetypes: return "Fewer is better — 1 or 2 gives the most focused results. Documentary is strict; Historical means stories about historical events."
        case .genrePreferences: return "Hard requirement — every result must fit. Each extra flavor you add reduces the pool significantly. 1 is ideal."
        case .fictionPreference: return "Can be very restrictive — no preference works best unless you specifically care. Based on a true story includes historical fiction and biopics. Non-fiction is documentary-only."
        case .sourceMaterial: return "Strict filter. Only set this if you specifically want a book or game adaptation."
        case .runtime: return "Runtime filters out movies outside the time window you choose."
        case .releaseAge: return "Release age is a strict filter, not a ranking boost."
        case .ageRating: return "This is a maximum rating filter when data is available. Missing data is penalized."
        case .minimumRating: return "Strong rating preference. Uses IMDb when available."
        case .dealBreakers: return "Strict filters. Choose none if nothing applies."
        case .myServicesOnly: return "Filters discover API calls with TMDb's with_watch_providers parameter. Library pool items (watchlist, recs) with nil providerCache pass through unchanged. Services without a mapped TMDb ID are excluded from the API filter but the post-filter still uses providerCache for them."
        }
    }

    var userSubtitle: String? {
        switch self {
        case .format: return "Choose one."
        case .archetype: return "Pick the vibe you're after. Choose one."
        case .secondaryArchetypes: return "Optional extras — 1 or 2 gives the most focused results."
        case .genrePreferences: return "Limits results to a specific genre or setting. 1 is ideal."
        case .fictionPreference: return "Leave on no preference unless you specifically care."
        case .sourceMaterial: return "Only set this if you want a book or game adaptation."
        case .runtime: return "Filter by how long you want to watch."
        case .releaseAge: return "Choose how old the film or show can be."
        case .ageRating: return "Pick the maximum content rating you're comfortable with."
        case .minimumRating: return "Choose a minimum quality bar."
        case .dealBreakers: return "Things you don't want to see. Choose none if nothing applies."
        case .myServicesOnly: return "Only suggest items available on your streaming services. Make sure your services are configured correctly — you can edit them below."
        }
    }
}

// MARK: - PickForMe Option Enums

enum PickForMeMediaFormat: String, CaseIterable, Codable, PickForMeOption {
    case movies, series, both

    init(_ filter: MediaFilter) {
        switch filter {
        case .movie:
            self = .movies
        case .tv:
            self = .series
        case .both:
            self = .both
        }
    }

    var id: String { rawValue }
    var title: String {
        switch self {
        case .movies: return "Movies"
        case .series: return "Series"
        case .both: return "Both"
        }
    }
    var isAnyOption: Bool { self == .both }
    var mediaFilter: MediaFilter {
        switch self {
        case .movies: return .movie
        case .series: return .tv
        case .both: return .both
        }
    }
}

enum PickForMeArchetype: String, CaseIterable, Codable, PickForMeOption {
    case feelGood, comedy, mystery, thriller, smartProblems, mission, heist, adventure, characterRelationships, humanTriumph, documentary, historical, war, epicSpectacle, mindBending, horror, thoughtfulSciFi, surprise, noPreference
    var id: String { rawValue }
    var title: String {
        switch self {
        case .feelGood: return "Feel-Good"
        case .comedy: return "Comedy"
        case .mystery: return "Mystery"
        case .thriller: return "Thriller"
        case .smartProblems: return "Smart people solving problems"
        case .mission: return "Mission"
        case .heist: return "Heist"
        case .adventure: return "Adventure"
        case .characterRelationships: return "Character and Relationships"
        case .humanTriumph: return "Human Triumph"
        case .documentary: return "Documentary"
        case .historical: return "Historical"
        case .war: return "War"
        case .epicSpectacle: return "Epic / Spectacle"
        case .mindBending: return "Mind-Bending"
        case .horror: return "Horror"
        case .thoughtfulSciFi: return "Thought-Provoking Sci-Fi"
        case .surprise: return "Surprise me"
        case .noPreference: return "No preference"
        }
    }
    var subtitle: String? {
        switch self {
        case .feelGood: return "Uplifting, optimistic, and heartwarming."
        case .comedy: return "Built primarily to make you laugh."
        case .mystery: return "Driven by uncovering hidden information."
        case .thriller: return "Tension, danger, suspense, or pursuit."
        case .smartProblems: return "Experts, teams, investigations, planning, or persistence."
        case .mission: return "A specific objective, operation, rescue, or survival mission."
        case .heist: return "Sophisticated capers, cons, and elaborate schemes."
        case .adventure: return "Exploration, discovery, and excitement."
        case .characterRelationships: return "Relationships, family dynamics, and personal growth."
        case .humanTriumph: return "Overcoming hurdles, resilience, achievement, or against-the-odds stories."
        case .documentary: return "Nonfiction, real subjects, and factual storytelling."
        case .historical: return "Fiction or nonfiction about a historical event."
        case .war: return "War, combat, military conflict, or wartime survival."
        case .epicSpectacle: return "Scale, visuals, action, and world-building."
        case .mindBending: return "Twists, puzzles, unusual structure, or reality-questioning stories."
        case .horror: return "Fear, dread, terror, or psychological discomfort."
        case .thoughtfulSciFi: return "Idea-driven science fiction, ethics, technology, or consciousness."
        case .surprise: return "Let the app lean on your history and strong ratings."
        case .noPreference: return nil
        }
    }
    var isAnyOption: Bool { self == .surprise || self == .noPreference }

    // TMDb keyword terms to look up for targeted discovery alongside genre-based discovery.
    // Only populated for archetypes where genre sorting alone leaves good films buried
    // (e.g. heist films at 7.2 rating sit far below the top of the Crime genre list).
    // Empty means genre-based discovery is already sufficient.
    var discoveryKeywords: [String] {
        switch self {
        case .heist:                  return ["heist", "caper"]
        case .mystery:                return ["murder mystery", "whodunit"]
        case .mission:                return ["espionage", "spy"]
        case .mindBending:            return ["unreliable narrator", "mind-bending"]
        case .thoughtfulSciFi:        return ["dystopia", "artificial intelligence"]
        case .humanTriumph:           return ["underdog"]
        case .adventure:              return ["treasure hunt"]
        case .characterRelationships: return ["coming of age"]
        // Genre-based discovery is sufficient for these
        case .feelGood, .comedy, .thriller, .smartProblems,
             .documentary, .historical, .war, .epicSpectacle, .horror,
             .surprise, .noPreference:
            return []
        }
    }

    var thematicDiscoveryPhrase: String? {
        switch self {
        case .feelGood: return "uplifting and heartwarming films that leave you feeling good"
        case .mystery: return "films built around uncovering secrets, whodunits, and clever detective stories"
        case .thriller: return "psychological thrillers with tension, suspense, and high stakes"
        case .smartProblems: return "films about brilliant minds solving impossible problems or pulling off complex plans"
        case .mission: return "films with high-stakes missions, operations, and survival objectives"
        case .heist: return "heist films, capers, and elaborate con schemes"
        case .characterRelationships: return "character-driven films exploring complex relationships and personal growth"
        case .humanTriumph: return "inspiring underdog stories of resilience and against-the-odds achievement"
        case .epicSpectacle: return "epic films with spectacular scale, grand visuals, and ambitious world-building"
        case .mindBending: return "mind-bending films with unreliable narrators, reality-questioning twists, and non-linear structure"
        case .thoughtfulSciFi: return "thought-provoking science fiction exploring big ideas, ethics, or consciousness"
        case .comedy, .adventure, .war, .horror, .documentary, .historical, .surprise, .noPreference: return nil
        }
    }

    var cerebrasConceptTerm: String? {
        switch self {
        case .feelGood: return "uplifting heartwarming optimistic"
        case .mystery: return "mystery detective whodunit hidden secrets"
        case .thriller: return "psychological thriller suspense tension"
        case .smartProblems: return "intelligent problem-solving expert investigation"
        case .mission: return "high-stakes mission operation survival"
        case .heist: return "heist con caper elaborate scheme"
        case .characterRelationships: return "character study relationship drama personal growth"
        case .humanTriumph: return "underdog triumph resilience overcoming odds"
        case .epicSpectacle: return "epic spectacle grand scale ambitious"
        case .mindBending: return "mind-bending twist unreliable narrator complex narrative"
        case .thoughtfulSciFi: return "thought-provoking sci-fi ethics technology consciousness"
        case .comedy: return "comedy funny humorous light-hearted"
        case .adventure: return "adventure exploration journey discovery"
        case .war: return "war combat military conflict"
        case .horror: return "horror frightening scary dread"
        case .documentary, .historical, .surprise, .noPreference: return nil
        }
    }
}

enum PickForMeGenrePreference: String, CaseIterable, Codable, PickForMeOption {
    case space, fantasy, sciFi, action, history, crime, war, romance, animation, family, horror, comedy, noPreference
    var id: String { rawValue }
    var title: String {
        switch self {
        case .space: return "Space"
        case .fantasy: return "Fantasy"
        case .sciFi: return "Sci-Fi"
        case .action: return "Action"
        case .history: return "History"
        case .crime: return "Crime"
        case .war: return "War"
        case .romance: return "Romance"
        case .animation: return "Animation"
        case .family: return "Family"
        case .horror: return "Horror"
        case .comedy: return "Comedy"
        case .noPreference: return "No preference"
        }
    }
    var isAnyOption: Bool { self == .noPreference }

    var cerebrasConceptTerm: String? {
        switch self {
        case .space: return "set in outer space — spacecraft, astronauts, alien worlds, space stations, interstellar travel"
        case .fantasy: return "fantasy world — magic, mythical creatures, kingdoms, sorcery"
        case .sciFi: return "science fiction — future technology, AI, alternate worlds, scientific concepts"
        case .action: return "action-heavy — fights, chases, explosions, combat sequences"
        case .history: return "historical setting — real past eras, period drama, historical figures"
        case .crime: return "crime-focused — heists, gangs, detectives, criminal underworld"
        case .romance: return "romance-centered — love stories, relationships, romantic tension"
        case .horror: return "horror — scary, frightening, disturbing, dread"
        case .comedy: return "comedy — funny, humorous, light-hearted, laugh-out-loud"
        case .war: return "war — military combat, battlefield, wartime survival"
        case .animation: return "animated — cartoon, anime, or animated feature"
        case .family: return "family-friendly — suitable for all ages, wholesome"
        case .noPreference: return nil
        }
    }
}

enum PickForMeFictionPreference: String, CaseIterable, Codable, PickForMeOption {
    case fiction, basedOnTrueStory, nonFiction, noPreference
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fiction: return "Completely fictional"
        case .basedOnTrueStory: return "Based on a true story"
        case .nonFiction: return "Non-fiction / Documentary only"
        case .noPreference: return "No preference"
        }
    }
    var subtitle: String? {
        switch self {
        case .fiction: return "Made-up stories only — avoids documentaries and true-event content."
        case .basedOnTrueStory: return "Includes historical fiction, biopics, and documentaries."
        case .nonFiction: return "Strict filter — documentaries and non-fiction only."
        case .noPreference: return nil
        }
    }
    var userSubtitle: String? {
        switch self {
        case .fiction: return "Made-up stories only."
        case .basedOnTrueStory: return "Historical fiction, biopics, and documentaries."
        case .nonFiction: return "Documentaries and non-fiction only."
        case .noPreference: return nil
        }
    }
    var isAnyOption: Bool { self == .noPreference }
}

enum PickForMeSourceMaterial: String, CaseIterable, Codable, PickForMeOption {
    case book, game, noPreference
    var id: String { rawValue }
    var title: String {
        switch self {
        case .book: return "Based on a book"
        case .game: return "Based on a game"
        case .noPreference: return "No preference"
        }
    }
    var isAnyOption: Bool { self == .noPreference }
    var keywordIDs: [Int] {
        switch self {
        case .book: return [818]
        case .game: return [41645]
        case .noPreference: return []
        }
    }
}

struct PickForMeRuntimeRange: Hashable, Codable {
    var minMinutes: Int  // 0 = no minimum
    var maxMinutes: Int  // 0 = no maximum

    static let unconstrained = PickForMeRuntimeRange(minMinutes: 0, maxMinutes: 0)
    static let steps = [0, 30, 60, 90, 120, 150, 180, 210, 240]

    var hasConstraint: Bool { minMinutes > 0 || maxMinutes > 0 }

    func contains(_ minutes: Int) -> Bool {
        if minMinutes > 0 && minutes < minMinutes { return false }
        if maxMinutes > 0 && minutes > maxMinutes { return false }
        return true
    }

    var displayString: String {
        let minStr = minMinutes > 0 ? Self.formatMinutes(minMinutes) : nil
        let maxStr = maxMinutes > 0 ? Self.formatMinutes(maxMinutes) : nil
        switch (minStr, maxStr) {
        case (nil, nil): return "Any length"
        case (let min?, nil): return "\(min) or more"
        case (nil, let max?): return "Up to \(max)"
        case (let min?, let max?): return "\(min) – \(max)"
        }
    }

    static func formatMinutes(_ m: Int) -> String {
        guard m > 0 else { return "Any" }
        let h = m / 60, mins = m % 60
        if h == 0 { return "\(mins)m" }
        return mins == 0 ? "\(h)h" : "\(h)h \(mins)m"
    }
}

enum PickForMeReleaseAge: String, CaseIterable, Codable, PickForMeOption {
    case newReleases, lastFiveYears, olderThanFiveYears, lastTenYears, olderThanTenYears, lastFifteenYears, olderThanFifteenYears, lastTwentyFiveYears, olderThanTwentyFiveYears, noPreference
    var id: String { rawValue }
    var title: String {
        switch self {
        case .newReleases: return "New releases"
        case .lastFiveYears: return "Last 5 years"
        case .olderThanFiveYears: return "Older than 5 years"
        case .lastTenYears: return "Last 10 years"
        case .olderThanTenYears: return "Older than 10 years"
        case .lastFifteenYears: return "Last 15 years"
        case .olderThanFifteenYears: return "Older than 15 years"
        case .lastTwentyFiveYears: return "Last 25 years"
        case .olderThanTwentyFiveYears: return "Older than 25 years"
        case .noPreference: return "No preference"
        }
    }
    var isAnyOption: Bool { self == .noPreference }
    var minimumYearsOld: Int? {
        switch self {
        case .olderThanFiveYears: return 5
        case .olderThanTenYears: return 10
        case .olderThanFifteenYears: return 15
        case .olderThanTwentyFiveYears: return 25
        case .newReleases, .lastFiveYears, .lastTenYears, .lastFifteenYears, .lastTwentyFiveYears, .noPreference: return nil
        }
    }
    var maximumYearsOld: Int? {
        switch self {
        case .lastFiveYears: return 5
        case .lastTenYears: return 10
        case .lastFifteenYears: return 15
        case .lastTwentyFiveYears: return 25
        case .newReleases, .olderThanFiveYears, .olderThanTenYears, .olderThanFifteenYears, .olderThanTwentyFiveYears, .noPreference: return nil
        }
    }
}

enum PickForMeContentRating: String, CaseIterable, Codable, PickForMeOption {
    case g, pg, pg13, r, nc17, any
    var id: String { rawValue }
    var title: String {
        switch self {
        case .g: return "G / U"
        case .pg: return "PG"
        case .pg13: return "PG-13 / 12A"
        case .r: return "R / 15"
        case .nc17: return "NC-17 / 18"
        case .any: return "Any rating"
        }
    }
    var isAnyOption: Bool { self == .any }
    private var maturityRank: Int {
        switch self {
        case .g: return 0
        case .pg: return 1
        case .pg13: return 2
        case .r: return 3
        case .nc17: return 4
        case .any: return Int.max
        }
    }

    static func selectionAllows(_ selection: Set<PickForMeContentRating>, rating rawRating: String) -> Bool {
        guard !selection.contains(.any),
              let actualRank = rank(for: rawRating),
              let maximumAllowedRank = selection.map(\.maturityRank).max()
        else {
            return true
        }
        return actualRank <= maximumAllowedRank
    }

    static func selectionAllowsGoreQuestion(_ selection: Set<PickForMeContentRating>) -> Bool {
        selection.contains(.any) || selection.contains(.r) || selection.contains(.nc17)
    }

    private static func rank(for rawRating: String) -> Int? {
        let normalized = rawRating.uppercased().replacingOccurrences(of: "_", with: "-")
        switch normalized {
        case "G", "U", "TV-Y", "TV-G": return 0
        case "PG", "TV-Y7", "TV-PG": return 1
        case "PG-13", "12", "12A", "TV-14": return 2
        case "R", "15", "TV-MA": return 3
        case "NC-17", "18": return 4
        default: return nil
        }
    }
}

enum PickForMeMinimumRating: String, CaseIterable, Codable, PickForMeOption {
    case eight, sevenHalf, seven, sixHalf, any
    var id: String { rawValue }
    var title: String {
        switch self {
        case .eight: return "8.0+"
        case .sevenHalf: return "7.5+"
        case .seven: return "7.0+"
        case .sixHalf: return "6.5+"
        case .any: return "Any rating"
        }
    }
    var isAnyOption: Bool { self == .any }
    var minimumRating: Double? {
        switch self {
        case .eight: return 8.0
        case .sevenHalf: return 7.5
        case .seven: return 7.0
        case .sixHalf: return 6.5
        case .any: return nil
        }
    }
}

enum PickForMeDealBreaker: String, CaseIterable, Codable, PickForMeOption {
    case horror, romanceHeavy, animation, documentary, war, graphicViolence, sexualContent, superhero, verySad, foreignLanguage, longRuntime, sciFi, heavyFantasy, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .horror: return "Horror"
        case .romanceHeavy: return "Romance-heavy"
        case .animation: return "Animation"
        case .documentary: return "Documentary"
        case .war: return "War"
        case .graphicViolence: return "Graphic violence"
        case .sexualContent: return "Sexual content"
        case .superhero: return "Superhero"
        case .verySad: return "Very sad"
        case .foreignLanguage: return "Foreign language (not English)"
        case .longRuntime: return "Long runtime (180+ minutes)"
        case .sciFi: return "Sci-Fi"
        case .heavyFantasy: return "Heavy fantasy / supernatural"
        case .none: return "None"
        }
    }
    var requiresLateDescriptionPass: Bool {
        self == .graphicViolence || self == .sexualContent
    }
    var isAnyOption: Bool { self == .none }
}
