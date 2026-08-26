import SwiftUI
import UniformTypeIdentifiers

struct WatchedImportEntry {
    let rawText: String
    let title: String
    let year: Int?
    let rating: Double?
    let isFavourite: Bool
    let mediaFilter: MediaFilter
    let watchedDate: Date?

    private static let mediaIdentifierTokens = ["m", "s"]

    enum ImportFormat {
        case automatic
        case commaSeparated
    }

    static func report(for text: String, format: ImportFormat = .automatic) -> WatchedImportReport {
        let rawEntries = splitEntries(text, format: format)
        var entries: [WatchedImportEntry] = []
        var malformed: [String] = []

        for rawText in rawEntries {
            if format == .commaSeparated && rawText.contains("\n") {
                malformed.append(rawText)
                continue
            }

            guard let entry = parseEntry(rawText) else {
                malformed.append(rawText)
                continue
            }

            entries.append(entry)
        }

        return WatchedImportReport(entries: entries, malformed: malformed)
    }

    static func parse(_ text: String) -> [WatchedImportEntry] {
        report(for: text).entries
    }

    private static func splitEntries(_ text: String, format: ImportFormat) -> [String] {
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let separator: Character = format == .commaSeparated
            ? ","
            : (normalizedText.contains("\n") ? "\n" : ",")

        return normalizedText
            .split(separator: separator, omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseEntry(_ rawText: String) -> WatchedImportEntry? {
        var tokens = rawText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        // Minimum: [title] [m/s]
        guard tokens.count >= 2 else { return nil }

        // Parse from the end: optional date → optional f → optional rating (0–5) → optional year (4-digit) → required m/s → title

        var watchedDate: Date? = nil
        if let lastToken = tokens.last, let parsed = parseFlexibleDate(lastToken) {
            watchedDate = parsed
            tokens.removeLast()
        }
        guard tokens.count >= 2 else { return nil }

        var isFavourite = false
        if tokens.last?.localizedCaseInsensitiveCompare("f") == .orderedSame {
            isFavourite = true
            tokens.removeLast()
        }
        guard tokens.count >= 2 else { return nil }

        var rating: Double? = nil
        if let lastToken = tokens.last, let parsed = Double(lastToken), parsed >= 0 && parsed <= 5 {
            rating = parsed
            tokens.removeLast()
        }
        guard tokens.count >= 2 else { return nil }

        var year: Int? = nil
        if let lastToken = tokens.last, let parsed = Int(lastToken), lastToken.count == 4 {
            year = parsed
            tokens.removeLast()
        }
        guard tokens.count >= 2 else { return nil }

        guard let lastToken = tokens.last?.lowercased(), mediaIdentifierTokens.contains(lastToken) else {
            return nil
        }
        let mediaFilter: MediaFilter = lastToken == "m" ? .movie : .tv
        tokens.removeLast()

        let title = tokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        return WatchedImportEntry(
            rawText: rawText,
            title: title,
            year: year,
            rating: rating,
            isFavourite: isFavourite,
            mediaFilter: mediaFilter,
            watchedDate: watchedDate
        )
    }

    // Accepts YYYY[-/.]MM[-/.]DD with any single-character separator mix
    static func parseFlexibleDate(_ token: String) -> Date? {
        let seps = CharacterSet(charactersIn: "-/.")
        let parts = token.components(separatedBy: seps)
        guard parts.count == 3,
              parts[0].count == 4,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              m >= 1, m <= 12, d >= 1, d <= 31 else { return nil }
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        return Calendar(identifier: .gregorian).date(from: comps)
    }

    var mediaIdentifierText: String {
        switch mediaFilter {
        case .movie: return "m"
        case .tv: return "s"
        case .both: return ""
        }
    }

    static func exportLine(for item: MediaItem, rating: Double?, isFavourite: Bool) -> String {
        // Format: [title] [m/s] [year] [rating?] [f?]
        var parts = [item.title]
        parts.append(item.kind == .tv ? "s" : "m")
        if let year = item.releaseYearInt { parts.append(String(year)) }
        if let rating { parts.append(rating.formatted(.number.precision(.fractionLength(0...1)))) }
        if isFavourite { parts.append("f") }
        return parts.joined(separator: " ")
    }

    static func warningMessage(for report: WatchedImportReport) -> String? {
        guard !report.malformed.isEmpty else { return nil }
        return "The following lines may be formatted incorrectly and could cause import errors:\n\(report.malformed.joined(separator: "\n"))\n\nDouble-check before pressing Continue."
    }
}

struct WatchedImportReport {
    let entries: [WatchedImportEntry]
    let malformed: [String]

    var hasWarnings: Bool {
        !malformed.isEmpty
    }
}


struct CloudLibrarySnapshot: Codable {
    let modifiedAt: Date
    let library: UserLibrary
    let settings: AppSettings
    let externalRatings: [MediaKey: ExternalRatings]
}

struct HomeFeedCache: Codable {
    let cachedAt: Date
    let filter: MediaFilter
    let trending: [MediaItem]
    let popular: [MediaItem]
    let newReleases: [MediaItem]
    let upcoming: [MediaItem]

    var hasContent: Bool {
        !trending.isEmpty || !popular.isEmpty || !newReleases.isEmpty || !upcoming.isEmpty
    }
}

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .commaSeparatedText] }
    var text: String
    init(text: String = "") { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? "" }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

// MARK: - Export Format

enum ExportFormat: String, CaseIterable, Identifiable {
    case text
    case csv

    var id: String { rawValue }
    var title: String {
        switch self {
        case .text: return ".txt"
        case .csv: return ".csv"
        }
    }
    var separator: String {
        switch self {
        case .text: return "\n"
        case .csv: return ", "
        }
    }
    var contentType: UTType {
        switch self {
        case .text: return .plainText
        case .csv: return .commaSeparatedText
        }
    }
    var filename: String {
        switch self {
        case .text: return "Vestigo Watched"
        case .csv: return "Vestigo Watched CSV"
        }
    }
}

extension WatchedImportEntry {
    static func normalizedTitle(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func matchScore(_ title: String, normalizedTitle query: String) -> Int {
        let normalized = normalizedTitle(title)
        if normalized == query { return 100 }
        if normalized.contains(query) { return 75 }
        if query.contains(normalized) { return 60 }
        return 0
    }

    // MARK: - Letterboxd CSV

    static func isLetterboxdCSV(_ text: String) -> Bool {
        let firstLine = text.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return firstLine.contains("Letterboxd URI") && firstLine.contains("Name")
    }

    static func parseLetterboxd(_ text: String) -> [WatchedImportEntry] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let headerLine = lines.first, !headerLine.isEmpty else { return [] }

        let headers = parseCSVRow(headerLine)
        guard let nameIdx = headers.firstIndex(of: "Name") else { return [] }
        let yearIdx = headers.firstIndex(of: "Year")
        let ratingIdx = headers.firstIndex(of: "Rating")
        let watchedDateIdx = headers.firstIndex(of: "Watched Date")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        var entries: [WatchedImportEntry] = []
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }
            let cols = parseCSVRow(line)
            guard cols.count > nameIdx else { continue }
            let title = cols[nameIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            let year: Int? = yearIdx.flatMap { idx in
                idx < cols.count ? Int(cols[idx]) : nil
            }
            let rating: Double? = ratingIdx.flatMap { idx in
                idx < cols.count ? Double(cols[idx]) : nil
            }
            let watchedDate: Date? = watchedDateIdx.flatMap { idx in
                idx < cols.count ? dateFormatter.date(from: cols[idx]) : nil
            }

            entries.append(WatchedImportEntry(
                rawText: line,
                title: title,
                year: year,
                rating: rating,
                isFavourite: false,
                mediaFilter: .both,
                watchedDate: watchedDate
            ))
        }
        return entries
    }

    private static func parseCSVRow(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current)
        return result
    }
}

struct ImportAmbiguity: Identifiable {
    let id = UUID()
    let entries: [WatchedImportEntry]
    let candidates: [MediaItem]
    var yearNotFound: Bool = false

    var primaryEntry: WatchedImportEntry { entries[0] }
    var occurrenceCount: Int { entries.count }
}

struct ImportResult {
    let notFound: [String]
    let ambiguous: [ImportAmbiguity]
}
