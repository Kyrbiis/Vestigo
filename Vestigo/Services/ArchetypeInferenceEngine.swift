import Foundation

// MARK: - Input

struct ArchetypeInferenceInput {
    let genreIDs: [Int]
    let keywordNames: [String]
    let networkNames: [String]
    let numberOfSeasons: Int?
    let runtime: Int?
    let releaseYear: Int?
    let isInCollection: Bool
    let isTV: Bool

    init(genreIDs: [Int], keywordNames: [String], networkNames: [String] = [], numberOfSeasons: Int? = nil, runtime: Int? = nil, releaseYear: Int? = nil, isInCollection: Bool = false, isTV: Bool = false) {
        self.genreIDs = genreIDs
        self.keywordNames = keywordNames
        self.networkNames = networkNames
        self.numberOfSeasons = numberOfSeasons
        self.runtime = runtime
        self.releaseYear = releaseYear
        self.isInCollection = isInCollection
        self.isTV = isTV
    }
}

// MARK: - Output

struct ArchetypeInference {
    let scores: [PickForMeArchetype: Double]

    func confidence(for archetype: PickForMeArchetype) -> Double {
        scores[archetype] ?? 0.0
    }

    func topArchetypes(threshold: Double = 0.35) -> [PickForMeArchetype] {
        scores
            .filter { $0.value >= threshold }
            .sorted { $0.value > $1.value }
            .map(\.key)
    }

    // Returns the boost multiplier to apply to a Pick For Me score (0 = no match, up to ~2.0)
    func pickForMeBoost(for archetypes: Set<PickForMeArchetype>) -> Double {
        guard !archetypes.contains(.surprise), !archetypes.contains(.noPreference) else { return 1.0 }
        let best = archetypes.compactMap { scores[$0] }.max() ?? 0
        return 1.0 + best
    }
}

// MARK: - Engine

enum ArchetypeInferenceEngine {

    static func infer(from input: ArchetypeInferenceInput) -> ArchetypeInference {
        let kwds = input.keywordNames.map { $0.lowercased() }
        let nets = input.networkNames.map { $0.lowercased() }
        let genres = Set(input.genreIDs)

        var scores: [PickForMeArchetype: Double] = [:]
        for archetype in PickForMeArchetype.allCases {
            guard archetype != .surprise, archetype != .noPreference else { continue }
            let raw = rawScore(archetype, genres: genres, kwds: kwds, nets: nets, input: input)
            scores[archetype] = sigmoid(raw)
        }
        return ArchetypeInference(scores: scores)
    }

    // MARK: - Normalization
    // raw / (raw + C) — C=4 gives 0.5 at raw=4, 0.75 at raw=12
    private static func sigmoid(_ raw: Double, C: Double = 4.0) -> Double {
        guard raw > 0 else { return 0 }
        return min(raw / (raw + C), 1.0)
    }

    // MARK: - Signal helpers

    private static func has(_ kwds: [String], _ fragment: String) -> Bool {
        kwds.contains { $0.contains(fragment) }
    }

    private static func w(_ kwds: [String], _ fragment: String, weight: Double) -> Double {
        has(kwds, fragment) ? weight : 0
    }

    // MARK: - Dispatch

    private static func rawScore(
        _ archetype: PickForMeArchetype,
        genres: Set<Int>,
        kwds: [String],
        nets: [String],
        input: ArchetypeInferenceInput
    ) -> Double {
        switch archetype {
        case .feelGood:             return feelGoodScore(genres: genres, kwds: kwds)
        case .comedy:               return comedyScore(genres: genres, kwds: kwds)
        case .mystery:              return mysteryScore(genres: genres, kwds: kwds)
        case .thriller:             return thrillerScore(genres: genres, kwds: kwds)
        case .smartProblems:        return smartProblemsScore(kwds: kwds)
        case .mission:              return missionScore(kwds: kwds)
        case .heist:                return heistScore(kwds: kwds)
        case .adventure:            return adventureScore(genres: genres, kwds: kwds)
        case .characterRelationships: return characterRelationshipsScore(genres: genres, kwds: kwds)
        case .humanTriumph:         return humanTriumphScore(kwds: kwds)
        case .documentary:          return documentaryScore(genres: genres, kwds: kwds)
        case .historical:           return historicalScore(genres: genres, kwds: kwds)
        case .war:                  return warScore(genres: genres, kwds: kwds)
        case .epicSpectacle:        return epicSpectacleScore(genres: genres, kwds: kwds, input: input)
        case .mindBending:          return mindBendingScore(kwds: kwds)
        case .horror:               return horrorScore(genres: genres, kwds: kwds)
        case .thoughtfulSciFi:      return thoughtfulSciFiScore(genres: genres, kwds: kwds)
        case .surprise, .noPreference: return 0
        }
    }

    // MARK: - Per-archetype raw scores

    private static func feelGoodScore(genres: Set<Int>, kwds: [String]) -> Double {
        var s = 0.0
        if genres.contains(35)    { s += 1.5 }  // Comedy
        if genres.contains(10751) { s += 2.0 }  // Family
        if genres.contains(16)    { s += 1.0 }  // Animation
        s += w(kwds, "feel-good",    weight: 4.0)
        s += w(kwds, "uplifting",    weight: 3.5)
        s += w(kwds, "heartwarming", weight: 3.5)
        s += w(kwds, "wholesome",    weight: 3.0)
        s += w(kwds, "inspirational",weight: 2.0)
        s += w(kwds, "optimistic",   weight: 1.5)
        s += w(kwds, "lighthearted", weight: 2.0)
        s += w(kwds, "joyful",       weight: 1.5)
        s += w(kwds, "charming",     weight: 1.0)
        return s
    }

    private static func comedyScore(genres: Set<Int>, kwds: [String]) -> Double {
        var s = 0.0
        if genres.contains(35) { s += 5.5 }  // Comedy (primary genre signal)
        s += w(kwds, "satire",      weight: 1.5)
        s += w(kwds, "parody",      weight: 1.5)
        s += w(kwds, "slapstick",   weight: 1.5)
        s += w(kwds, "dark comedy", weight: 1.0)
        s += w(kwds, "black comedy",weight: 1.0)
        s += w(kwds, "spoof",       weight: 1.0)
        s += w(kwds, "mockumentary",weight: 2.0)
        return s
    }

    private static func mysteryScore(genres: Set<Int>, kwds: [String]) -> Double {
        var s = 0.0
        if genres.contains(9648) { s += 4.0 }  // Mystery
        s += w(kwds, "whodunit",              weight: 4.5)
        s += w(kwds, "murder mystery",        weight: 4.5)
        s += w(kwds, "detective",             weight: 3.0)
        s += w(kwds, "mystery",               weight: 2.5)
        s += w(kwds, "murder investigation",  weight: 3.0)
        s += w(kwds, "crime investigation",   weight: 2.5)
        s += w(kwds, "sleuth",                weight: 2.5)
        s += w(kwds, "investigation",         weight: 1.5)
        s += w(kwds, "missing person",        weight: 1.5)
        return s
    }

    private static func thrillerScore(genres: Set<Int>, kwds: [String]) -> Double {
        var s = 0.0
        if genres.contains(53) { s += 4.5 }  // Thriller
        s += w(kwds, "psychological thriller", weight: 3.0)
        s += w(kwds, "cat and mouse",          weight: 2.5)
        s += w(kwds, "thriller",               weight: 2.0)
        s += w(kwds, "suspense",               weight: 2.0)
        s += w(kwds, "serial killer",          weight: 2.0)
        s += w(kwds, "stalker",                weight: 1.5)
        s += w(kwds, "paranoia",               weight: 1.5)
        return s
    }

    private static func smartProblemsScore(kwds: [String]) -> Double {
        var s = 0.0
        s += w(kwds, "chess",            weight: 3.5)
        s += w(kwds, "cryptography",     weight: 3.5)
        s += w(kwds, "codebreaker",      weight: 3.5)
        s += w(kwds, "mathematician",    weight: 3.5)
        s += w(kwds, "hacker",           weight: 2.5)
        s += w(kwds, "artificial intelligence", weight: 2.5)
        s += w(kwds, "genius",           weight: 2.0)
        s += w(kwds, "puzzle",           weight: 2.0)
        s += w(kwds, "problem solving",  weight: 2.5)
        s += w(kwds, "intellectual",     weight: 2.0)
        s += w(kwds, "scientist",        weight: 1.5)
        s += w(kwds, "competition",      weight: 1.0)
        s += w(kwds, "strategy",         weight: 1.0)
        return s
    }

    private static func missionScore(kwds: [String]) -> Double {
        var s = 0.0
        s += w(kwds, "espionage",       weight: 4.5)
        s += w(kwds, "secret agent",    weight: 4.0)
        s += w(kwds, "spy",             weight: 3.5)
        s += w(kwds, "covert",          weight: 3.0)
        s += w(kwds, "undercover",      weight: 3.0)
        s += w(kwds, "counterterrorism",weight: 3.0)
        s += w(kwds, "infiltration",    weight: 3.0)
        s += w(kwds, "operative",       weight: 2.5)
        s += w(kwds, "rescue mission",  weight: 3.0)
        s += w(kwds, "special forces",  weight: 2.5)
        s += w(kwds, "mission",         weight: 1.0)
        return s
    }

    private static func heistScore(kwds: [String]) -> Double {
        var s = 0.0
        s += w(kwds, "heist",             weight: 7.0)
        s += w(kwds, "caper",             weight: 6.5)
        s += w(kwds, "con artist",        weight: 6.0)
        s += w(kwds, "confidence trick",  weight: 6.0)
        s += w(kwds, "con game",          weight: 5.5)
        s += w(kwds, "grifter",           weight: 5.5)
        s += w(kwds, "jewel thief",       weight: 5.0)
        s += w(kwds, "elaborate plan",    weight: 3.5)
        s += w(kwds, "scam",              weight: 3.0)
        s += w(kwds, "bank robbery",      weight: 2.5)
        s += w(kwds, "robbery",           weight: 1.2)
        s += w(kwds, "theft",             weight: 0.8)
        return s
    }

    private static func adventureScore(genres: Set<Int>, kwds: [String]) -> Double {
        var s = 0.0
        if genres.contains(12) { s += 3.5 }  // Adventure
        s += w(kwds, "quest",          weight: 2.5)
        s += w(kwds, "treasure hunt",  weight: 2.5)
        s += w(kwds, "expedition",     weight: 2.5)
        s += w(kwds, "exploration",    weight: 2.0)
        s += w(kwds, "road trip",      weight: 2.0)
        s += w(kwds, "journey",        weight: 1.5)
        return s
    }

    private static func characterRelationshipsScore(genres: Set<Int>, kwds: [String]) -> Double {
        var s = 0.0
        if genres.contains(10749) { s += 2.5 }  // Romance
        if genres.contains(18)    { s += 1.5 }  // Drama
        if genres.contains(10751) { s += 1.0 }  // Family
        s += w(kwds, "family drama",  weight: 3.5)
        s += w(kwds, "love story",    weight: 2.5)
        s += w(kwds, "relationship",  weight: 2.0)
        s += w(kwds, "friendship",    weight: 2.0)
        s += w(kwds, "marriage",      weight: 2.0)
        s += w(kwds, "divorce",       weight: 2.0)
        s += w(kwds, "coming of age", weight: 2.0)
        s += w(kwds, "grief",         weight: 1.5)
        s += w(kwds, "siblings",      weight: 1.5)
        s += w(kwds, "parent",        weight: 1.0)
        return s
    }

    private static func humanTriumphScore(kwds: [String]) -> Double {
        var s = 0.0
        s += w(kwds, "underdog",         weight: 4.0)
        s += w(kwds, "redemption",       weight: 3.5)
        s += w(kwds, "against all odds", weight: 3.5)
        s += w(kwds, "triumph",          weight: 3.0)
        s += w(kwds, "perseverance",     weight: 3.0)
        s += w(kwds, "overcoming",       weight: 2.5)
        s += w(kwds, "comeback",         weight: 2.5)
        s += w(kwds, "survival",         weight: 2.0)
        s += w(kwds, "determination",    weight: 2.0)
        s += w(kwds, "based on true story", weight: 1.0)
        s += w(kwds, "true story",       weight: 0.8)
        return s
    }

    private static func documentaryScore(genres: Set<Int>, kwds: [String]) -> Double {
        var s = 0.0
        if genres.contains(99) { s += 8.0 }  // Documentary
        s += w(kwds, "documentary",        weight: 3.0)
        s += w(kwds, "docuseries",         weight: 3.0)
        s += w(kwds, "docudrama",          weight: 2.5)
        s += w(kwds, "nature documentary", weight: 3.0)
        s += w(kwds, "true crime",         weight: 1.5)
        return s
    }

    private static func historicalScore(genres: Set<Int>, kwds: [String]) -> Double {
        var s = 0.0
        if genres.contains(36) { s += 4.0 }  // History
        s += w(kwds, "period drama",       weight: 3.5)
        s += w(kwds, "historical fiction", weight: 3.0)
        s += w(kwds, "historical",         weight: 2.0)
        s += w(kwds, "medieval",           weight: 2.0)
        s += w(kwds, "19th century",       weight: 2.0)
        s += w(kwds, "18th century",       weight: 2.0)
        s += w(kwds, "ancient",            weight: 1.5)
        s += w(kwds, "biography",          weight: 1.5)
        return s
    }

    private static func warScore(genres: Set<Int>, kwds: [String]) -> Double {
        var s = 0.0
        if genres.contains(10752) { s += 6.5 }  // War
        s += w(kwds, "world war",   weight: 3.0)
        s += w(kwds, "warfare",     weight: 2.5)
        s += w(kwds, "battlefield", weight: 2.5)
        s += w(kwds, "combat",      weight: 2.5)
        s += w(kwds, "soldier",     weight: 2.0)
        s += w(kwds, "war film",    weight: 3.0)
        s += w(kwds, "vietnam",     weight: 2.0)
        s += w(kwds, "military",    weight: 1.5)
        return s
    }

    private static func epicSpectacleScore(genres: Set<Int>, kwds: [String], input: ArchetypeInferenceInput) -> Double {
        var s = 0.0
        if genres.contains(14)  { s += 2.5 }  // Fantasy
        if genres.contains(12)  { s += 2.0 }  // Adventure
        if genres.contains(878) { s += 1.0 }  // SciFi
        if genres.contains(28)  { s += 0.5 }  // Action
        s += w(kwds, "epic",          weight: 2.5)
        s += w(kwds, "world-building",weight: 2.5)
        s += w(kwds, "mythology",     weight: 2.0)
        s += w(kwds, "blockbuster",   weight: 1.5)
        s += w(kwds, "legend",        weight: 1.0)
        // Franchise / long runtime signals epic scale
        if input.isInCollection                           { s += 2.0 }
        if let runtime = input.runtime, runtime >= 150   { s += 1.5 }
        if let seasons = input.numberOfSeasons, seasons >= 4 { s += 1.0 }
        return s
    }

    private static func mindBendingScore(kwds: [String]) -> Double {
        var s = 0.0
        s += w(kwds, "mind-bending",      weight: 5.0)
        s += w(kwds, "mindf",             weight: 5.0)
        s += w(kwds, "unreliable narrator",weight: 4.5)
        s += w(kwds, "non-linear",        weight: 4.0)
        s += w(kwds, "nonlinear",         weight: 4.0)
        s += w(kwds, "meta-fiction",      weight: 4.0)
        s += w(kwds, "twist ending",      weight: 3.5)
        s += w(kwds, "plot twist",        weight: 3.0)
        s += w(kwds, "time loop",         weight: 3.5)
        s += w(kwds, "alternate reality", weight: 3.0)
        s += w(kwds, "surreal",           weight: 3.5)
        s += w(kwds, "psychological",     weight: 1.5)
        s += w(kwds, "amnesia",           weight: 2.0)
        s += w(kwds, "dream",             weight: 1.0)
        return s
    }

    private static func horrorScore(genres: Set<Int>, kwds: [String]) -> Double {
        var s = 0.0
        if genres.contains(27) { s += 7.0 }  // Horror (very strong primary signal)
        s += w(kwds, "psychological horror", weight: 2.5)
        s += w(kwds, "haunted",              weight: 2.0)
        s += w(kwds, "slasher",              weight: 2.5)
        s += w(kwds, "supernatural",         weight: 1.5)
        s += w(kwds, "ghost",                weight: 1.5)
        s += w(kwds, "zombie",               weight: 2.0)
        s += w(kwds, "demon",                weight: 1.5)
        s += w(kwds, "monster",              weight: 1.0)
        s += w(kwds, "dread",                weight: 1.5)
        return s
    }

    private static func thoughtfulSciFiScore(genres: Set<Int>, kwds: [String]) -> Double {
        var s = 0.0
        if genres.contains(878) { s += 2.5 }  // SciFi
        s += w(kwds, "transhumanism",       weight: 4.0)
        s += w(kwds, "existential",         weight: 3.5)
        s += w(kwds, "philosophical",       weight: 3.5)
        s += w(kwds, "dystopia",            weight: 3.5)
        s += w(kwds, "consciousness",       weight: 3.0)
        s += w(kwds, "artificial intelligence", weight: 3.0)
        s += w(kwds, "social commentary",   weight: 2.5)
        s += w(kwds, "android",             weight: 2.5)
        s += w(kwds, "genetic engineering", weight: 2.5)
        s += w(kwds, "surveillance",        weight: 2.0)
        s += w(kwds, "post-apocalyptic",    weight: 2.0)
        s += w(kwds, "climate change",      weight: 2.0)
        s += w(kwds, "space exploration",   weight: 2.0)
        s += w(kwds, "ethics",              weight: 2.0)
        return s
    }
}
