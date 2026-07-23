import Foundation
import SwiftUI

// MARK: - MediaKind Extensions

extension MediaKind {
    var label: String { self == .movie ? "Movie" : (self == .tv ? "Series" : "Person") }
    var tmdbPath: String { self == .movie ? "movie" : (self == .tv ? "tv" : "person") }

    func displayLabel(runtime: Int?) -> String {
        if self == .movie, let runtime, runtime > 0, runtime <= 40 {
            return "Short film"
        }
        return label
    }
}

// MARK: - MediaItem Category Genre Extension

extension MediaItem {
    var categoryGenreIDs: Set<Int> {
        Set(genreIDs.compactMap { Self.categoryGenrePriorityMap[$0] })
    }

    private static let categoryGenrePriorityMap: [Int: Int] = [
        28: 28, 12: 12, 878: 878, 10765: 14, 14: 14, 18: 18, 27: 27, 16: 16,
        80: 80, 35: 35, 9648: 9648, 53: 53, 10749: 10749, 10751: 10751, 99: 99,
        36: 36, 10752: 10752, 10768: 10752, 37: 37, 10762: 10762, 10764: 10764,
        10767: 10767, 10759: 28
    ]
}

// MARK: - Credit Filtering

enum CreditFilterText {
    static let blockedTitlePrefixes: [String] = [
        "the making of", "making of", "behind the scenes", "inside ",
        "a look inside", "a closer look", "the story of", "the legacy of"
    ]
    static let blockedPhrases: [String] = [
        "making of", "behind the scenes", "behind-the-scenes", "bts", "blooper",
        "bloopers", "gag reel", "deleted scenes", "special features", "featurette",
        "documentary about", "documentary on", "premiere special", "red carpet",
        "award show", "awards show", "academy awards", "golden globes",
        "emmy awards", "screen actors guild awards", "mtv movie awards",
        "critics choice awards"
    ]
}

extension MediaItem {
    var shouldShowInPersonCredits: Bool {
        guard !title.isEmpty else { return false }
        guard kind != .person else { return false }
        guard !hasBlockedCreditTitle else { return false }
        guard !hasBlockedCreditPhrase else { return false }
        guard !hasSelfCreditRole else { return false }
        return true
    }

    private var normalizedCreditTitle: String { title.lowercased() }
    private var normalizedCreditOverview: String { overview.lowercased() }
    private var normalizedCreditRole: String { (creditRole ?? "").lowercased() }
    private var normalizedCreditCombinedText: String {
        normalizedCreditTitle + " " + normalizedCreditOverview + " " + normalizedCreditRole
    }

    private var hasBlockedCreditTitle: Bool {
        CreditFilterText.blockedTitlePrefixes.contains { normalizedCreditTitle.hasPrefix($0) }
    }

    private var hasBlockedCreditPhrase: Bool {
        let text = normalizedCreditCombinedText
        return CreditFilterText.blockedPhrases.contains { text.contains($0) }
    }

    private var hasSelfCreditRole: Bool {
        let role = normalizedCreditRole
        return role == "self" || role == "himself" || role == "herself" ||
               role == "themselves" || role.hasPrefix("self -")
    }
}

