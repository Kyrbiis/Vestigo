import SwiftUI
import UniformTypeIdentifiers

struct WatchedImportEntry {
    let rawText: String
    let title: String
    let rating: Double
    let isFavourite: Bool
    let mediaFilter: MediaFilter

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
        guard tokens.count >= 2 else { return nil }

        // Format: [title] [m/s] [rating] [f?]
        // Parse from the end: optional f, then rating, then optional m/s, then title

        var isFavourite = false
        if tokens.last?.localizedCaseInsensitiveCompare("f") == .orderedSame {
            isFavourite = true
            tokens.removeLast()
        }

        guard let lastToken = tokens.last, let parsedRating = Double(lastToken), (0...5).contains(parsedRating) else {
            return nil
        }
        tokens.removeLast()

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
            rating: parsedRating,
            isFavourite: isFavourite,
            mediaFilter: mediaFilter
        )
    }

    var mediaIdentifierText: String {
        switch mediaFilter {
        case .movie: return "m"
        case .tv: return "s"
        case .both: return ""
        }
    }

    static func exportLine(for item: MediaItem, rating: Double?, isFavourite: Bool) -> String {
        // Format: [title] [m/s] [rating] [f?]
        var parts = [item.title]

        parts.append(item.kind == .tv ? "s" : "m")

        if let rating {
            parts.append(rating.formatted(.number.precision(.fractionLength(0...1))))
        }

        if isFavourite {
            parts.append("f")
        }

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
}

struct ImportAmbiguity: Identifiable {
    let id = UUID()
    let entries: [WatchedImportEntry]
    let candidates: [MediaItem]

    var primaryEntry: WatchedImportEntry { entries[0] }
    var occurrenceCount: Int { entries.count }
}

struct ImportResult {
    let notFound: [String]
    let ambiguous: [ImportAmbiguity]
}
