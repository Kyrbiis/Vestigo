import SwiftUI

struct MediaItem: Identifiable, Codable, Hashable {
    let id: Int
    let kind: MediaKind
    let title: String
    let overview: String
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let voteAverage: Double
    let voteCount: Int?
    let genreIDs: [Int]
    let creditRole: String?
    let runtime: Int?
    let originalLanguage: String?

    nonisolated init(
        id: Int,
        kind: MediaKind,
        title: String,
        overview: String,
        posterPath: String?,
        backdropPath: String?,
        releaseDate: String?,
        voteAverage: Double,
        voteCount: Int? = nil,
        genreIDs: [Int],
        creditRole: String?,
        runtime: Int?,
        originalLanguage: String?
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.releaseDate = releaseDate
        self.voteAverage = voteAverage
        self.voteCount = voteCount
        self.genreIDs = genreIDs
        self.creditRole = creditRole
        self.runtime = runtime
        self.originalLanguage = originalLanguage
    }

    init(_ dto: TMDbMediaDTO) {
        id = dto.id
        if dto.mediaType == "tv" || (dto.name != nil && dto.title == nil) { kind = .tv }
        else if dto.mediaType == "person" { kind = .person }
        else { kind = .movie }
        title = dto.title ?? dto.name ?? ""
        overview = dto.overview ?? ""
        posterPath = dto.posterPath
        backdropPath = dto.backdropPath
        releaseDate = dto.releaseDate ?? dto.firstAirDate
        voteAverage = dto.voteAverage ?? 0
        voteCount = dto.voteCount
        genreIDs = dto.genreIDs ?? []
        creditRole = dto.character ?? dto.job
        runtime = nil
        originalLanguage = dto.originalLanguage
    }

    var key: MediaKey { MediaKey(id: id, kind: kind) }
    var posterURL: URL? { posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w500\($0)") } }

    func posterURL(displayWidth: CGFloat) -> URL? {
        let size: String
        switch displayWidth {
        case ..<100: size = "w185"
        case ..<220: size = "w342"
        default:     size = "w500"
        }
        return posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/\(size)\($0)") }
    }
    var releaseDateValue: Date? { DateParser.parse(releaseDate) }
    var releaseYearText: String { releaseDateValue.map { String(Calendar.current.component(.year, from: $0)) } ?? "TBA" }
    var releaseYearInt: Int? { Int(releaseYearText) }
    var releaseDateReadable: String { releaseDateValue?.formatted(.dateTime.month(.abbreviated).day().year()) ?? "TBA" }
    var isUpcoming: Bool { (releaseDateValue ?? .distantPast) > .now }
    var genreGradient: LinearGradient { GenreDefinition.gradient(for: genreIDs.first) }

    func similarityScore(to seed: MediaItem) -> Int {
        var score = 0
        if kind == seed.kind { score += 12 }
        let sharedGenres = Set(genreIDs).intersection(Set(seed.genreIDs)).count
        score += sharedGenres * 10
        if originalLanguage == seed.originalLanguage { score += 5 }
        if let seedYear = seed.releaseDateValue.map({ Calendar.current.component(.year, from: $0) }),
           let itemYear = releaseDateValue.map({ Calendar.current.component(.year, from: $0) }) {
            let yearGap = abs(seedYear - itemYear)
            if yearGap <= 2 { score += 6 } else if yearGap <= 5 { score += 4 } else if yearGap <= 10 { score += 2 }
        }
        return score
    }

    func withRuntime(_ runtime: Int?) -> MediaItem {
        MediaItem(
            id: id,
            kind: kind,
            title: title,
            overview: overview,
            posterPath: posterPath,
            backdropPath: backdropPath,
            releaseDate: releaseDate,
            voteAverage: voteAverage,
            voteCount: voteCount,
            genreIDs: genreIDs,
            creditRole: creditRole,
            runtime: runtime,
            originalLanguage: originalLanguage
        )
    }
}

struct MediaKey: Codable, nonisolated Hashable, Identifiable {
    let id: Int
    let kind: MediaKind
    var stableID: String { "\(kind.rawValue)-\(id)" }
}

// MARK: - MediaItem

// Try to find the MediaItem type and add the displayKindLabel computed property.
// If MediaItem is defined elsewhere, this is a placeholder for the property to add there.

extension MediaItem {
    /// Returns a user-visible label for the kind, mapping short movies to "Short film".
    var displayKindLabel: String {
        kind.displayLabel(runtime: runtime)
    }

    var shouldShowInDiscovery: Bool {
        let normalizedTitle = title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOverview = overview
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let normalizedReleaseDate = (releaseDate ?? "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedTitle.isEmpty else { return false }
        guard voteAverage > 0 || isRecentOrUpcomingRelease else { return false }
        guard let releaseDate, let releaseYear = Int(releaseDate.prefix(4)), releaseYear > 1870 else { return false }
        if normalizedReleaseDate == "tba" || normalizedReleaseDate == "date tba" { return false }
        if normalizedReleaseDate.contains("tba") { return false }
        if normalizedTitle.hasPrefix("untitled") { return false }
        if normalizedTitle == "tba" || normalizedTitle == "plot tba" { return false }
        if normalizedOverview == "plot tba" || normalizedOverview == "tba" { return false }
        if normalizedOverview == "plot unknown" || normalizedOverview == "no plot available" { return false }
        if normalizedTitle.contains(" tba") { return false }
        return true
    }

    var releaseYearNumber: Int? {
        if let releaseDate, releaseDate.count >= 4 {
            return Int(releaseDate.prefix(4))
        }

        return Int(releaseYearText.prefix(4))
    }

    var isRecentOrUpcomingRelease: Bool {
        guard let date = releaseDateValue else { return false }
        if date > .now { return true }
        let daysSinceRelease = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? .max
        return daysSinceRelease <= 7
    }
}

