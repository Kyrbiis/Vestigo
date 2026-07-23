import Foundation

// MARK: - Date Parsing

enum DateParser {
    static func parse(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    static func tmdbDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Watchmode JSON

enum WatchmodeJSONValue: Decodable {
    case string(String)
    case number(Double)
    case object([String: WatchmodeJSONValue])
    case array([WatchmodeJSONValue])
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer() {
            if single.decodeNil() { self = .null; return }
            if let value = try? single.decode(String.self) { self = .string(value); return }
            if let value = try? single.decode(Double.self) { self = .number(value); return }
            if let value = try? single.decode(Bool.self) { self = .bool(value); return }
        }

        if let keyed = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var object: [String: WatchmodeJSONValue] = [:]
            for key in keyed.allKeys {
                object[key.stringValue] = try keyed.decode(WatchmodeJSONValue.self, forKey: key)
            }
            self = .object(object)
            return
        }

        var unkeyed = try decoder.unkeyedContainer()
        var array: [WatchmodeJSONValue] = []
        while !unkeyed.isAtEnd {
            array.append(try unkeyed.decode(WatchmodeJSONValue.self))
        }
        self = .array(array)
    }

    func firstPriceText() -> String? {
        switch self {
        case .string(let value): return Self.cleanedPriceString(value, keyHint: nil)
        case .number, .bool, .null: return nil
        case .array(let values): return Self.firstPriceText(in: values)
        case .object(let object): return Self.firstPriceText(in: object)
        }
    }

    private static func firstPriceText(in values: [WatchmodeJSONValue]) -> String? {
        for value in values { if let found = value.firstPriceText() { return found } }
        return nil
    }

    private static func firstPriceText(in object: [String: WatchmodeJSONValue]) -> String? {
        let preferredKeys = ["formattedPrice","priceFormatted","displayPrice","priceText","formatted",
                             "amount","value","cost","retailPrice","rentalPrice","purchasePrice","rentPrice","buyPrice","price"]
        for key in preferredKeys {
            if let value = object[key], let found = priceText(from: value, keyHint: key) { return found }
        }
        for pair in object.sorted(by: { $0.key < $1.key }) {
            let lower = pair.key.lowercased()
            let isPriceKey = lower.contains("price") || lower.contains("amount") || lower.contains("cost")
                || lower.contains("rental") || lower.contains("purchase") || lower.contains("rent") || lower.contains("buy")
            if isPriceKey, let found = priceText(from: pair.value, keyHint: pair.key) { return found }
        }
        for pair in object.sorted(by: { $0.key < $1.key }) {
            let lower = pair.key.lowercased()
            if lower == "type" || lower == "quality" || lower == "service" || lower == "addon"
                || lower == "link" || lower == "links" { continue }
            if let found = pair.value.firstPriceText() { return found }
        }
        return nil
    }

    private static func priceText(from value: WatchmodeJSONValue, keyHint: String?) -> String? {
        switch value {
        case .string(let text): return cleanedPriceString(text, keyHint: keyHint)
        case .number(let number):
            guard let keyHint else { return nil }
            let lower = keyHint.lowercased()
            guard lower.contains("price") || lower.contains("amount") || lower.contains("cost") else { return nil }
            return formattedCurrency(number)
        case .array(let values):
            for v in values { if let found = priceText(from: v, keyHint: keyHint) { return found } }
            return nil
        case .object(let obj): return firstPriceText(in: obj)
        case .bool, .null: return nil
        }
    }

    private static func cleanedPriceString(_ value: String, keyHint: String?) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let range = trimmed.range(of: #"\$\s*\d+(?:\.\d{1,2})?"#, options: .regularExpression) {
            return String(trimmed[range]).replacingOccurrences(of: " ", with: "")
        }
        let lower = trimmed.lowercased()
        if lower == "free" { return "Free" }
        if lower == "included" { return "Included" }
        let transient = ["subscription","flatrate","stream","rent","buy","purchase","addon","available"]
        if transient.contains(lower) { return nil }
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return trimmed.priceTextFromURL() }
        guard let keyHint else { return nil }
        let lowerKey = keyHint.lowercased()
        guard lowerKey.contains("price") || lowerKey.contains("amount") || lowerKey.contains("cost") else { return nil }
        let numericOnly = trimmed.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = Double(numericOnly) { return formattedCurrency(number) }
        return nil
    }

    private static func formattedCurrency(_ value: Double) -> String? {
        guard value > 0 else { return nil }
        let amount = value >= 100 && value.rounded() == value ? value / 100.0 : value
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount))
    }
}

struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
    init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
}

// MARK: - String Extensions

extension String {
    func priceTextFromURL() -> String? {
        guard let comps = URLComponents(string: self) else { return nil }
        let names = ["price","amount","cost","retailPrice","rentalPrice","purchasePrice","rentPrice","buyPrice"]
        for name in names {
            guard let value = comps.queryItems?.first(where: { $0.name == name })?.value else { continue }
            let cleaned = value.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let number = Double(cleaned), number > 0 else { continue }
            let amount = number >= 100 && number.rounded() == number ? number / 100.0 : number
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = "USD"
            return formatter.string(from: NSNumber(value: amount))
        }
        return nil
    }

    func containsAny(_ needles: [String]) -> Bool {
        needles.contains { contains($0) }
    }
}

// MARK: - Array Extensions

extension Array where Element: Hashable {
    func frequencySorted() -> [Element] {
        var counts: [Element: Int] = [:]
        for element in self { counts[element, default: 0] += 1 }
        return counts.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : String(describing: lhs.key) < String(describing: rhs.key)
        }.map(\.key)
    }
}

extension Array where Element == MediaItem {
    func uniqued() -> [MediaItem] {
        var seen = Set<MediaKey>()
        return filter { seen.insert($0.key).inserted }
    }

    func sortedBySearchRelevance(_ query: String) -> [MediaItem] {
        let q = query.lowercased()
        return sorted {
            let aExact = $0.title.lowercased() == q
            let bExact = $1.title.lowercased() == q
            if aExact != bExact { return aExact }
            let aPrefix = $0.title.lowercased().hasPrefix(q)
            let bPrefix = $1.title.lowercased().hasPrefix(q)
            if aPrefix != bPrefix { return aPrefix }
            return ($0.releaseDateValue ?? .distantPast) > ($1.releaseDateValue ?? .distantPast)
        }
    }

    func sortedBySimilarity(to seed: MediaItem) -> [MediaItem] {
        sorted { lhs, rhs in
            let lhsScore = lhs.similarityScore(to: seed)
            let rhsScore = rhs.similarityScore(to: seed)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return (lhs.releaseDateValue ?? .distantPast) > (rhs.releaseDateValue ?? .distantPast)
        }
    }

    func sorted(
        using option: SortOption,
        ratings: [MediaKey: Double],
        externalRatings: [MediaKey: ExternalRatings] = [:],
        ratingSource: RatingSource = .tmdb,
        direction: SortDirection = .descending
    ) -> [MediaItem] {
        func ratingValue(for item: MediaItem) -> Double {
            if ratingSource == .imdb, let imdbRating = externalRatings[item.key]?.imdbRating {
                return imdbRating
            }
            return -1
        }
        let result = sorted { a, b in
            switch option {
            case .releaseDate:
                let av = a.releaseDateValue ?? .distantPast
                let bv = b.releaseDateValue ?? .distantPast
                if av != bv { return av > bv }
            case .myRating:
                let av = ratings[a.key] ?? -1
                let bv = ratings[b.key] ?? -1
                if av != bv { return av > bv }
            case .tmdbRating:
                let av = ratingValue(for: a)
                let bv = ratingValue(for: b)
                if av != bv { return av > bv }
            }
            return (a.releaseDateValue ?? .distantPast) > (b.releaseDateValue ?? .distantPast)
        }
        return direction == .ascending ? result.reversed() : result
    }

    func sortedByCategoryRank() -> [MediaItem] {
        sorted { ($0.releaseDateValue ?? .distantPast) > ($1.releaseDateValue ?? .distantPast) }
    }

    func prefixArray(_ count: Int) -> [MediaItem] {
        Array(prefix(count))
    }
}

extension Array where Element == PersonSummary {
    func uniquedPeople(excluding excludedIDs: Set<Int> = []) -> [PersonSummary] {
        var seen = excludedIDs
        return filter { seen.insert($0.id).inserted }
    }
}
