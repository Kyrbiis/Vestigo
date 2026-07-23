import Foundation

// MARK: - Search Filter

enum SearchFilter: String, CaseIterable, Identifiable, Codable, Hashable {
    case all
    case movie
    case tv
    case people

    static var allCases: [SearchFilter] {
        [.movie, .tv, .all, .people]
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Both"
        case .movie: return "Movies"
        case .tv: return "Series"
        case .people: return "People"
        }
    }

    var mediaFilter: MediaFilter? {
        switch self {
        case .all: return .both
        case .movie: return .movie
        case .tv: return .tv
        case .people: return nil
        }
    }
}

enum SearchFilterSection: String, CaseIterable, Identifiable {
    case runtime
    case rating
    case date

    var id: String { rawValue }

    var title: String {
        switch self {
        case .runtime: return "Runtime"
        case .rating: return "Rating"
        case .date: return "Date"
        }
    }
}

enum SearchRuntimeFilter: String, CaseIterable, Identifiable {
    case underOneHour
    case oneToOneAndHalf
    case oneAndHalfToTwo
    case twoToTwoAndHalf
    case twoAndHalfToThree
    case overThree

    var id: String { rawValue }

    var title: String {
        switch self {
        case .underOneHour: return "<1hr"
        case .oneToOneAndHalf: return "1–1.5hr"
        case .oneAndHalfToTwo: return "1.5–2hr"
        case .twoToTwoAndHalf: return "2–2.5hr"
        case .twoAndHalfToThree: return "2.5–3hr"
        case .overThree: return ">3hr"
        }
    }

    func contains(_ runtime: Int) -> Bool {
        switch self {
        case .underOneHour:
            return runtime < 60
        case .oneToOneAndHalf:
            return runtime >= 60 && runtime < 90
        case .oneAndHalfToTwo:
            return runtime >= 90 && runtime < 120
        case .twoToTwoAndHalf:
            return runtime >= 120 && runtime < 150
        case .twoAndHalfToThree:
            return runtime >= 150 && runtime < 180
        case .overThree:
            return runtime >= 180
        }
    }
}

enum SearchRatingFilter: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5
    case six = 6
    case seven = 7
    case eight = 8
    case nine = 9

    var id: Int { rawValue }
    var minimumRating: Double { Double(rawValue) }
    var title: String { "IMDb \(rawValue)+" }
}

enum SearchDateFilter: String, CaseIterable, Identifiable {
    case lastYear
    case lastTenYears
    case lastTwentyYears
    case lastThirtyYears
    case lastFortyYears
    case olderThanFortyYears

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lastYear: return "Last year"
        case .lastTenYears: return "Last 10 years"
        case .lastTwentyYears: return "Last 20 years"
        case .lastThirtyYears: return "Last 30 years"
        case .lastFortyYears: return "Last 40 years"
        case .olderThanFortyYears: return "Older than 40 years"
        }
    }

    func contains(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        let tenYearsAgo = calendar.date(byAdding: .year, value: -10, to: now) ?? now
        let twentyYearsAgo = calendar.date(byAdding: .year, value: -20, to: now) ?? now
        let thirtyYearsAgo = calendar.date(byAdding: .year, value: -30, to: now) ?? now
        let fortyYearsAgo = calendar.date(byAdding: .year, value: -40, to: now) ?? now

        switch self {
        case .lastYear:
            return date >= oneYearAgo
        case .lastTenYears:
            return date >= tenYearsAgo
        case .lastTwentyYears:
            return date >= twentyYearsAgo
        case .lastThirtyYears:
            return date >= thirtyYearsAgo
        case .lastFortyYears:
            return date >= fortyYearsAgo
        case .olderThanFortyYears:
            return date < fortyYearsAgo
        }
    }
}
