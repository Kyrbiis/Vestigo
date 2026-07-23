import Foundation

struct ExternalRatings: Codable, Hashable {
    let imdbID: String?
    let imdbRating: Double?
    let imdbVotes: String?
    let rottenTomatoesRating: Int?
    let rottenTomatoesText: String?

    static let empty = ExternalRatings(
        imdbID: nil,
        imdbRating: nil,
        imdbVotes: nil,
        rottenTomatoesRating: nil,
        rottenTomatoesText: nil
    )

    init(
        imdbID: String?,
        imdbRating: Double?,
        imdbVotes: String?,
        rottenTomatoesRating: Int?,
        rottenTomatoesText: String?
    ) {
        self.imdbID = imdbID
        self.imdbRating = imdbRating
        self.imdbVotes = imdbVotes
        self.rottenTomatoesRating = rottenTomatoesRating
        self.rottenTomatoesText = rottenTomatoesText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: RatingsCodingKey.self)
        imdbID = Self.decodeString(from: container, keys: ["imdbID", "imdbId", "imdb_id", "imdbid"])
        imdbRating = Self.decodeDouble(from: container, keys: ["imdbRating", "imdb_rating", "imdb", "imdbScore", "imdb_score"])
        imdbVotes = Self.decodeString(from: container, keys: ["imdbVotes", "imdb_votes", "imdbVoteCount", "imdb_vote_count"])
        rottenTomatoesRating = Self.decodeInt(from: container, keys: ["rottenTomatoesRating", "rotten_tomatoes_rating", "tomatometer", "rtRating", "rt_rating"])
        rottenTomatoesText = Self.decodeString(from: container, keys: ["rottenTomatoesText", "rotten_tomatoes_text", "rottenTomatoes", "rotten_tomatoes", "rtText", "rt_text"])
    }

    var hasAnyRating: Bool {
        imdbRating != nil || rottenTomatoesRating != nil || rottenTomatoesText != nil
    }

    var imdbVoteCountValue: Int? {
        guard let imdbVotes else { return nil }
        let digitsOnly = imdbVotes.filter(\.isNumber)
        return Int(digitsOnly)
    }

    var rottenTomatoesDisplayText: String? {
        if let rottenTomatoesText, !rottenTomatoesText.isEmpty {
            return "Rotten Tomatoes: \(rottenTomatoesText)"
        }

        if let rottenTomatoesRating {
            return "Rotten Tomatoes: \(rottenTomatoesRating)%"
        }

        return nil
    }

    private struct RatingsCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    private static func decodeString(from container: KeyedDecodingContainer<RatingsCodingKey>, keys: [String]) -> String? {
        for key in keys {
            guard let codingKey = RatingsCodingKey(stringValue: key) else { continue }
            if let value = try? container.decode(String.self, forKey: codingKey), !value.isEmpty, value != "N/A" {
                return value
            }
            if let value = try? container.decode(Double.self, forKey: codingKey) {
                return value.formatted(.number.precision(.fractionLength(1)))
            }
            if let value = try? container.decode(Int.self, forKey: codingKey) {
                return String(value)
            }
        }

        return nil
    }

    private static func decodeDouble(from container: KeyedDecodingContainer<RatingsCodingKey>, keys: [String]) -> Double? {
        for key in keys {
            guard let codingKey = RatingsCodingKey(stringValue: key) else { continue }
            if let value = try? container.decode(Double.self, forKey: codingKey) {
                return value
            }
            if let value = try? container.decode(Int.self, forKey: codingKey) {
                return Double(value)
            }
            if let text = try? container.decode(String.self, forKey: codingKey) {
                let cleaned = text.replacingOccurrences(of: "/10", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                if let value = Double(cleaned), value > 0 {
                    return value
                }
            }
        }

        return nil
    }

    private static func decodeInt(from container: KeyedDecodingContainer<RatingsCodingKey>, keys: [String]) -> Int? {
        for key in keys {
            guard let codingKey = RatingsCodingKey(stringValue: key) else { continue }
            if let value = try? container.decode(Int.self, forKey: codingKey) {
                return value
            }
            if let value = try? container.decode(Double.self, forKey: codingKey) {
                return Int(value.rounded())
            }
            if let text = try? container.decode(String.self, forKey: codingKey) {
                let cleaned = text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                if let value = Int(cleaned) {
                    return value
                }
            }
        }

        return nil
    }
}
