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

struct PickForMeAnswers: Hashable {
    var mediaFormat: PickForMeMediaFormat?
    var archetypes: Set<PickForMeArchetype> = []
    var secondaryArchetypes: Set<PickForMeArchetype> = []
    var genrePreferences: Set<PickForMeGenrePreference> = []
    var seriousness: PickForMeSeriousness?
    var realism: PickForMeRealism?
    var sourceMaterial: PickForMeSourceMaterial?
    var actionLevels: Set<PickForMeActionLevel> = []
    var engagement: PickForMeEngagement?
    var recommendationType: PickForMeRecommendationType?
    var runtime: PickForMeRuntime?
    var releaseAge: PickForMeReleaseAge?
    var contentRatings: Set<PickForMeContentRating> = []
    var minimumRating: PickForMeMinimumRating?
    var dealBreakers: Set<PickForMeDealBreaker> = []

    var answeredQuestionCount: Int {
        var count = 0
        if mediaFormat != nil { count += 1 }
        if !archetypes.isEmpty { count += 1 }
        if !secondaryArchetypes.isEmpty { count += 1 }
        if !genrePreferences.isEmpty { count += 1 }
        if realism != nil { count += 1 }
        if sourceMaterial != nil { count += 1 }
        if recommendationType != nil { count += 1 }
        if runtime != nil { count += 1 }
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
        if let realism, realism != .anything { count += 1 }
        if let sourceMaterial, sourceMaterial != .noPreference { count += 1 }
        if let recommendationType, recommendationType != .noPreference { count += 1 }
        if !isSeriesOnly, let runtime, runtime != .any { count += 1 }
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

    var shouldAskRealismQuestion: Bool {
        !archetypes.contains(.thoughtfulSciFi) &&
        !secondaryArchetypes.contains(.thoughtfulSciFi)
    }
}

// MARK: - PickForMe Steps

enum PickForMeStep: CaseIterable {
    case format, archetype, secondaryArchetypes, genrePreferences, seriousness, realism, sourceMaterial, action, engagement, recommendationType, runtime, releaseAge, ageRating, minimumRating, dealBreakers

    static func steps(for answers: PickForMeAnswers) -> [PickForMeStep] {
        var steps: [PickForMeStep] = [
            .format,
            .archetype
        ]

        if !answers.archetypes.contains(.surprise) {
            steps.append(.secondaryArchetypes)
        }

        steps.append(contentsOf: [
            .genrePreferences
        ])

        if answers.shouldAskRealismQuestion {
            steps.append(.realism)
        }

        steps.append(contentsOf: [
            .sourceMaterial,
            .recommendationType
        ])

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

        return steps
    }

    var title: String {
        switch self {
        case .format: return "What do you want to watch?"
        case .archetype: return "What are you in the mood for?"
        case .secondaryArchetypes: return "Anything else sound good?"
        case .genrePreferences: return "Any genre flavors you want?"
        case .seriousness: return "How serious should it be?"
        case .realism: return "How realistic should it be?"
        case .sourceMaterial: return "Should it be based on something?"
        case .action: return "How much action do you want?"
        case .engagement: return "How mentally engaging should it be?"
        case .recommendationType: return "What type of recommendation do you want?"
        case .runtime: return "How much time do you have?"
        case .releaseAge: return "How recent should it be?"
        case .ageRating: return "What content rating are you comfortable with?"
        case .minimumRating: return "How highly rated should it be?"
        case .dealBreakers: return "Any deal breakers?"
        }
    }

    var subtitle: String? {
        switch self {
        case .format: return "Choose one."
        case .archetype: return "Choose one. Documentary is a strict filter; Historical means stories about historical events."
        case .secondaryArchetypes: return "Choose any number, or choose no preference. Documentary is strict; Historical means stories about historical events."
        case .genrePreferences: return "These are light boosts. History only nudges older true-event stories upward."
        case .seriousness: return "This is a ranking preference, not a strict filter."
        case .realism: return "Real-world only is a strict filter. The other answers are ranking preferences."
        case .sourceMaterial: return "Strict filter. Choose no preference if the source does not matter."
        case .action: return "This is a ranking preference, not a strict filter."
        case .engagement: return "Easy viewing means relaxed. Fully focused means something more demanding."
        case .recommendationType: return "This changes ranking and candidate sources, not a hard filter."
        case .runtime: return "Runtime filters out movies outside the time window you choose."
        case .releaseAge: return "Release age is a strict filter, not a ranking boost."
        case .ageRating: return "This is a maximum rating filter when data is available. Missing data is penalized."
        case .minimumRating: return "Strong rating preference. Uses IMDb when available."
        case .dealBreakers: return "Strict filters. Choose none if nothing applies."
        }
    }
}

// MARK: - PickForMe Option Enums

enum PickForMeMediaFormat: String, CaseIterable, PickForMeOption {
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

enum PickForMeArchetype: String, CaseIterable, PickForMeOption {
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
        case .heist: return "A robbery, con, caper, theft, or elaborate scheme."
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
}

enum PickForMeSeriousness: String, CaseIterable, PickForMeOption {
    case lightFun, mostlyFun, balanced, serious, intense, noPreference
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lightFun: return "Light and fun"
        case .mostlyFun: return "Mostly fun"
        case .balanced: return "Balanced"
        case .serious: return "Serious"
        case .intense: return "Intense"
        case .noPreference: return "No preference"
        }
    }
    var isAnyOption: Bool { self == .noPreference }
}

enum PickForMeGenrePreference: String, CaseIterable, PickForMeOption {
    case space, fantasy, sciFi, history, crime, war, romance, animation, family, horror, noPreference
    var id: String { rawValue }
    var title: String {
        switch self {
        case .space: return "Space"
        case .fantasy: return "Fantasy"
        case .sciFi: return "Sci-Fi"
        case .history: return "History"
        case .crime: return "Crime"
        case .war: return "War"
        case .romance: return "Romance"
        case .animation: return "Animation"
        case .family: return "Family"
        case .horror: return "Horror"
        case .noPreference: return "No preference"
        }
    }
    var isAnyOption: Bool { self == .noPreference }
}

enum PickForMeRealism: String, CaseIterable, PickForMeOption {
    case realWorld, mostlyRealistic, someSpeculative, completelyFictional, anything
    var id: String { rawValue }
    var title: String {
        switch self {
        case .realWorld: return "Real-world only"
        case .mostlyRealistic: return "Mostly realistic"
        case .someSpeculative: return "Some sci-fi or fantasy"
        case .completelyFictional: return "Completely fictional"
        case .anything: return "No preference"
        }
    }
    var isAnyOption: Bool { self == .anything }
}

enum PickForMeSourceMaterial: String, CaseIterable, PickForMeOption {
    case trueStory, book, game, noPreference
    var id: String { rawValue }
    var title: String {
        switch self {
        case .trueStory: return "Based on a true story"
        case .book: return "Based on a book"
        case .game: return "Based on a game"
        case .noPreference: return "No preference"
        }
    }
    var isAnyOption: Bool { self == .noPreference }
    var keywordIDs: [Int] {
        switch self {
        case .trueStory: return [9672]
        case .book: return [818]
        case .game: return [41645]
        case .noPreference: return []
        }
    }
}

enum PickForMeActionLevel: String, CaseIterable, PickForMeOption {
    case none, little, moderate, lots, noPreference
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "None"
        case .little: return "A little"
        case .moderate: return "Moderate"
        case .lots: return "Lots"
        case .noPreference: return "No preference"
        }
    }
    var isAnyOption: Bool { self == .noPreference }
}

enum PickForMeEngagement: String, CaseIterable, PickForMeOption {
    case easy, moderate, focused, noPreference
    var id: String { rawValue }
    var title: String {
        switch self {
        case .easy: return "Easy viewing"
        case .moderate: return "Moderately engaging"
        case .focused: return "Fully focused"
        case .noPreference: return "No preference"
        }
    }
    var isAnyOption: Bool { self == .noPreference }
}

enum PickForMeRecommendationType: String, CaseIterable, PickForMeOption {
    case crowdPleaser, acclaimed, hiddenGem, noPreference
    var id: String { rawValue }
    var title: String {
        switch self {
        case .crowdPleaser: return "Popular crowd-pleaser"
        case .acclaimed: return "Critically acclaimed"
        case .hiddenGem: return "Hidden gem"
        case .noPreference: return "No preference"
        }
    }
    var subtitle: String? {
        switch self {
        case .crowdPleaser: return "Popular, widely watched, and broadly liked."
        case .acclaimed: return "Prioritises Rotten Tomatoes when available, then strong IMDb/TMDb ratings."
        case .hiddenGem: return "Less mainstream, but still well-rated."
        case .noPreference: return nil
        }
    }
    var isAnyOption: Bool { self == .noPreference }
}

enum PickForMeRuntime: String, CaseIterable, PickForMeOption {
    case underNinety, underTwoHours, underTwoAndHalfHours, any
    var id: String { rawValue }
    var title: String {
        switch self {
        case .underNinety: return "Under 90 minutes"
        case .underTwoHours: return "Under 2 hours"
        case .underTwoAndHalfHours: return "Under 2.5 hours"
        case .any: return "Any length"
        }
    }
    var isAnyOption: Bool { self == .any }
    var minimumMinutes: Int? { nil }
    var maximumMinutes: Int? {
        switch self {
        case .underNinety: return 89
        case .underTwoHours: return 119
        case .underTwoAndHalfHours: return 149
        case .any: return nil
        }
    }
    func contains(_ minutes: Int) -> Bool {
        guard let maximumMinutes else { return true }
        return minutes <= maximumMinutes
    }
}

enum PickForMeReleaseAge: String, CaseIterable, PickForMeOption {
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

enum PickForMeContentRating: String, CaseIterable, PickForMeOption {
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

enum PickForMeMinimumRating: String, CaseIterable, PickForMeOption {
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

enum PickForMeDealBreaker: String, CaseIterable, PickForMeOption {
    case horror, romanceHeavy, animation, documentary, war, sciFiFantasy, graphicViolence, sexualContent, superhero, verySad, foreignLanguage, longRuntime, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .horror: return "Horror"
        case .romanceHeavy: return "Romance-heavy"
        case .animation: return "Animation"
        case .documentary: return "Documentary"
        case .war: return "War"
        case .sciFiFantasy: return "Sci-fi or fantasy"
        case .graphicViolence: return "Graphic violence"
        case .sexualContent: return "Sexual content"
        case .superhero: return "Superhero"
        case .verySad: return "Very sad"
        case .foreignLanguage: return "Foreign language (not English)"
        case .longRuntime: return "Long runtime (180+ minutes)"
        case .none: return "None"
        }
    }
    var requiresLateDescriptionPass: Bool {
        self == .graphicViolence || self == .sexualContent
    }
    var isAnyOption: Bool { self == .none }
}
