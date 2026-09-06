import Foundation
import SwiftUI

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
    case horror, romanceHeavy, animation, documentary, war, graphicViolence, sexualContent, superhero, verySad, foreignLanguage, sciFi, heavyFantasy, none
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
