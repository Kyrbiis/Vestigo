import Foundation
import SwiftUI

struct TrailerVideo: Identifiable, Hashable {
    let id: String
    let key: String
    let name: String
    let site: String
    let type: String
    let official: Bool
    let publishedAt: String?

    var displayTitle: String {
        name.isEmpty ? "Play trailer" : name
    }

    private nonisolated var rank: Int {
        var score = 0
        if official { score += 30 }
        if type.localizedCaseInsensitiveCompare("Trailer") == .orderedSame { score += 20 }
        if name.localizedCaseInsensitiveContains("official") { score += 8 }
        if name.localizedCaseInsensitiveContains("trailer") { score += 6 }
        if name.localizedCaseInsensitiveContains("teaser") { score += 2 }
        return score
    }

    nonisolated init?(_ dto: TMDbVideoDTO) {
        let trimmedKey = dto.key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return nil }
        guard dto.site.localizedCaseInsensitiveCompare("YouTube") == .orderedSame else { return nil }
        guard ["Trailer", "Teaser"].contains(where: { dto.type.localizedCaseInsensitiveCompare($0) == .orderedSame }) else {
            return nil
        }
        // Reject YouTube Shorts mislabeled as Trailer/Teaser in TMDb
        let lowerName = dto.name.lowercased()
        guard !lowerName.contains("#short") else { return nil }
        guard lowerName.range(of: "\\bshorts?\\b", options: .regularExpression) == nil else { return nil }

        id = dto.id
        key = trimmedKey
        name = dto.name
        site = dto.site
        type = dto.type
        official = dto.official ?? false
        publishedAt = dto.publishedAt
    }

    nonisolated static func ranked(from videos: [TMDbVideoDTO]) -> [TrailerVideo] {
        videos
            .compactMap(TrailerVideo.init)
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank {
                    return lhs.rank > rhs.rank
                }

                return (lhs.publishedAt ?? "") > (rhs.publishedAt ?? "")
            }
    }
}
