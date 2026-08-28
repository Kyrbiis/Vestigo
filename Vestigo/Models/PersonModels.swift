import Foundation

struct PersonCreditBundle {
    let onScreen: [MediaItem]
    let behindCamera: [MediaItem]

    var hasBothKinds: Bool { !onScreen.isEmpty && !behindCamera.isEmpty }
    var all: [MediaItem] { (onScreen + behindCamera).uniqued() }
}

enum PersonCreditFilter: String, CaseIterable {
    case onScreen = "On Screen"
    case behindCamera = "Behind the Camera"
}

struct PersonSummary: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let role: String
    let profilePath: String?

    var profileURL: URL? {
        profilePath.flatMap { URL(string: "https://image.tmdb.org/t/p/w342\($0)") }
    }

    init(_ dto: PersonDTO, fallbackRole: String = "") {
        id = dto.id
        name = dto.name
        role = dto.character ?? dto.job ?? fallbackRole
        profilePath = dto.profilePath
    }

    init(_ dto: TMDbPersonSearchDTO, fallbackRole: String = "Person") {
        id = dto.id
        name = dto.name
        role = fallbackRole
        profilePath = dto.profilePath
    }

    var extraPreviewText: String? {
        if !role.isEmpty {
            return "Known for \(role.lowercased())"
        }
        return nil
    }
}

struct PersonDetail: Codable, Hashable {
    let id: Int
    let biography: String
    let birthday: String?
    let deathday: String?
    let placeOfBirth: String?
    let knownForDepartment: String?
    let imdbID: String?

    nonisolated init(
        id: Int,
        biography: String,
        birthday: String? = nil,
        deathday: String? = nil,
        placeOfBirth: String? = nil,
        knownForDepartment: String? = nil,
        imdbID: String? = nil
    ) {
        self.id = id
        self.biography = biography
        self.birthday = birthday
        self.deathday = deathday
        self.placeOfBirth = placeOfBirth
        self.knownForDepartment = knownForDepartment
        self.imdbID = imdbID
    }

    init(response: TMDbPersonDetailResponse) {
        id = response.id
        biography = response.biography ?? ""
        birthday = response.birthday
        deathday = response.deathday
        placeOfBirth = response.placeOfBirth
        knownForDepartment = response.knownForDepartment
        imdbID = response.imdbID
    }

    var lifespanText: String? {
        let birthYear = birthday?.prefix(4)
        let deathYear = deathday?.prefix(4)

        if let birthYear, let deathYear {
            return "\(birthYear)–\(deathYear)"
        }

        if let birthYear {
            return "\(birthYear)–present"
        }

        return nil
    }

    var shortBiography: String? {
        let trimmed = biography.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let sentenceEndings: [Character] = [".", "!", "?"]
        if let firstSentenceEnd = trimmed.firstIndex(where: { sentenceEndings.contains($0) }) {
            let end = trimmed.index(after: firstSentenceEnd)
            return String(trimmed[..<end])
        }
        return String(trimmed.prefix(180))
    }

    var detailBiography: String? {
        let trimmed = biography.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= 700 { return trimmed }
        return String(trimmed.prefix(700)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    var fullBiography: String? {
        let trimmed = biography.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var tinyBiography: String? {
        guard let shortBiography else { return nil }
        let trimmed = shortBiography.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= 95 { return trimmed }
        return String(trimmed.prefix(95)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    var compactMetadataText: String? {
        var parts: [String] = []
        if let lifespanText { parts.append(lifespanText) }
        if let knownForDepartment, !knownForDepartment.isEmpty { parts.append(knownForDepartment) }
        if let placeOfBirth, !placeOfBirth.isEmpty { parts.append(placeOfBirth) }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}
