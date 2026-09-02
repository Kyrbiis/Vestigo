import SwiftUI

// MARK: - App Tabs

enum AppTab: String, CaseIterable, Identifiable {
    case home, search, watchlist, collections, friends
    var id: String { rawValue }
}

extension AppTab {
    var title: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .watchlist: return "Watchlist"
        case .collections: return "Collections"
        case .friends: return "Friends"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house"
        case .search: return "magnifyingglass"
        case .watchlist: return "bookmark"
        case .collections: return "rectangle.stack"
        case .friends: return "person.2"
        }
    }
    var sortIndex: Int {
        switch self {
        case .home: return 0
        case .search: return 1
        case .watchlist: return 2
        case .collections: return 3
        case .friends: return 4
        }
    }
}

enum TabTransitionDirection { case forward, backward }

// MARK: - Media Filter

enum MediaFilter: String, Codable, CaseIterable, Identifiable {
    case both, movie, tv
    var id: String { rawValue }
}

extension MediaFilter {
    var title: String { self == .both ? "Both" : (self == .movie ? "Movies" : "Series") }
    var tmdbPath: String { self == .both ? "all" : (self == .movie ? "movie" : "tv") }
}

// MARK: - Sort & View

enum ViewMode: String, Codable { case tile, list }

enum SortOption: String, CaseIterable, Identifiable {
    case releaseDate, myRating, tmdbRating
    var id: String { rawValue }
}

enum SortDirection: String, CaseIterable, Codable, Hashable {
    case ascending, descending
    var iconName: String { self == .ascending ? "arrow.up" : "arrow.down" }
    var accessibilityLabel: String { self == .ascending ? "Ascending" : "Descending" }
    mutating func toggle() {
        self = (self == .ascending) ? .descending : .ascending
    }
}

enum GenreSort: String, Codable, CaseIterable, Identifiable {
    case tmdbRating, releaseDate
    var id: String { rawValue }
    var title: String { self == .tmdbRating ? "IMDb rating" : "Released" }
    var tmdbSort: String { self == .tmdbRating ? "popularity.desc" : "primary_release_date.desc" }
}

enum SwipeContext: Equatable { case none, watchlist, collection(UUID) }

// MARK: - Appearance

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AccentChoice: String, Codable, CaseIterable, Identifiable {
    case blue, purple, green, orange
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .green: return .green
        case .orange: return .orange
        }
    }
}

// MARK: - Home

enum HomeSectionKind: Hashable {
    case trending
    case popular
    case newReleases
    case upcoming
}

// MARK: - Streaming Region

enum StreamingRegion: String, Codable, CaseIterable, Identifiable {
    case us = "US"
    case gb = "GB"
    case ca = "CA"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .us: return "US"
        case .gb: return "UK"
        case .ca: return "Canada"
        }
    }
}

// MARK: - Ratings & People

enum RatingSource: String, Codable, CaseIterable, Identifiable, Hashable {
    case tmdb
    case imdb

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tmdb: return "TMDb"
        case .imdb: return "IMDb"
        }
    }
}

enum PersonKnownForSort: String, CaseIterable, Identifiable {
    case rating
    case date

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rating: return "Rating"
        case .date: return "Date"
        }
    }
}

// MARK: - Media Kind

enum MediaKind: String, Codable, Hashable { case movie, tv, person }

// MARK: - Runtime Filter

enum RuntimeSearchFilter: String, Codable, CaseIterable, Identifiable {
    case any
    case underOneHour
    case oneToNinety
    case ninetyToTwoHours
    case twoToTwoAndHalf
    case twoAndHalfToThree
    case overThreeHours

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any runtime"
        case .underOneHour: return "<1hr"
        case .oneToNinety: return "1–1.5hr"
        case .ninetyToTwoHours: return "1.5–2hr"
        case .twoToTwoAndHalf: return "2–2.5hr"
        case .twoAndHalfToThree: return "2.5–3hr"
        case .overThreeHours: return ">3hr"
        }
    }

    var minimumMinutes: Int? {
        switch self {
        case .any: return nil
        case .underOneHour: return nil
        case .oneToNinety: return 60
        case .ninetyToTwoHours: return 90
        case .twoToTwoAndHalf: return 120
        case .twoAndHalfToThree: return 150
        case .overThreeHours: return 180
        }
    }

    var maximumMinutes: Int? {
        switch self {
        case .any: return nil
        case .underOneHour: return 59
        case .oneToNinety: return 89
        case .ninetyToTwoHours: return 119
        case .twoToTwoAndHalf: return 149
        case .twoAndHalfToThree: return 179
        case .overThreeHours: return nil
        }
    }

    var isActive: Bool { self != .any }
}
