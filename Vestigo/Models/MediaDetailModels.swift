import Foundation

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

struct RelatedMediaSection: Identifiable, Hashable {
    let kind: RelatedMediaKind
    let items: [RelatedMediaItem]

    var id: String { kind.rawValue }
    var title: String { kind.title }

    static func sections(from items: [RelatedMediaItem]) -> [RelatedMediaSection] {
        RelatedMediaKind.allCases.compactMap { kind in
            let sectionItems = uniqueItems(items.filter { $0.kind == kind })

            guard !sectionItems.isEmpty else { return nil }
            return RelatedMediaSection(kind: kind, items: Array(sectionItems.prefix(12)))
        }
    }

    private static func uniqueItems(_ items: [RelatedMediaItem]) -> [RelatedMediaItem] {
        var seenIDs: Set<String> = []
        return items.filter { item in
            seenIDs.insert(item.id).inserted
        }
    }
}

enum RelatedMediaKind: String, CaseIterable, Hashable {
    case original

    var title: String {
        switch self {
        case .original:
            return "Original media"
        }
    }
}

struct RelatedMediaItem: Identifiable, Hashable {
    let id: String
    let kind: RelatedMediaKind
    let title: String
    let description: String
    let imageURL: String?
    let linkURL: URL

    var imageURLValue: URL? {
        guard var value = imageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if value.hasPrefix("http://") {
            value = "https://" + value.dropFirst("http://".count)
        }

        if let commonsURL = Self.commonsThumbnailURL(from: value) {
            return commonsURL
        }

        if let url = URL(string: value) {
            return url
        }

        var allowedCharacters = CharacterSet.urlQueryAllowed
        allowedCharacters.insert(charactersIn: ":/")
        return value
            .addingPercentEncoding(withAllowedCharacters: allowedCharacters)
            .flatMap(URL.init(string:))
    }

    private static func commonsThumbnailURL(from value: String) -> URL? {
        let markers = [
            "/wiki/Special:FilePath/",
            "/wiki/Special:Redirect/file/"
        ]

        guard let marker = markers.first(where: { value.contains($0) }),
              let range = value.range(of: marker) else {
            return nil
        }

        let rawFilename = value[range.upperBound...]
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? ""
        let decodedFilename = rawFilename.removingPercentEncoding ?? rawFilename
        guard !decodedFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "commons.wikimedia.org"
        components.path = "/wiki/Special:Redirect/file/\(decodedFilename)"
        components.queryItems = [
            URLQueryItem(name: "width", value: "264")
        ]
        return components.url
    }

    init?(binding: WikidataRelatedMediaBinding) {
        guard let kind = RelatedMediaKind(rawValue: binding.relation.value) else { return nil }

        let title = binding.itemLabel.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !title.hasPrefix("Q") else { return nil }

        let linkString = binding.article?.value ?? binding.item.value
        guard let linkURL = URL(string: linkString) else { return nil }

        self.id = "\(kind.rawValue)-\(binding.item.value)"
        self.kind = kind
        self.title = title
        self.description = binding.itemDescription?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.imageURL = binding.image?.value
        self.linkURL = linkURL
    }
}

struct MediaDetail: Hashable {
    let director: PersonSummary?
    let creator: PersonSummary?
    let cast: [PersonSummary]
    let castAndKeyCrew: [PersonSummary]
    let seasons: [SeasonInfo]
    let similar: [MediaItem]
    let firstAirDate: String?
    let lastAirDate: String?
    let status: String?
    let runtime: Int?
    let ageRating: String?
    let tmdbCollectionID: Int?
    let keywordIDs: [Int]
    let trailers: [TrailerVideo]
    let imdbID: String?
    let tmdbProviders: [StreamingOption]
    let sameFranchiseKeys: Set<MediaKey>
    let strongAPISimilarityKeys: Set<MediaKey>
    let mediumAPISimilarityKeys: Set<MediaKey>
    let sharedContributorKeys: Set<MediaKey>

    init(response: TMDbDetailResponse, fallback: MediaItem) {
        let crewList: [PersonDTO] = response.credits?.crew ?? []
        let castList: [PersonDTO] = response.credits?.cast ?? []
        tmdbCollectionID = response.belongsToCollection?.id
        firstAirDate = response.firstAirDate
        lastAirDate = response.lastAirDate
        status = response.status
        runtime = response.runtime
        ageRating = response.usAgeRating
        let allKeywords: [TMDbKeyword] = response.keywords?.keywords ?? response.keywords?.results ?? []
        keywordIDs = allKeywords.map(\.id)
        trailers = TrailerVideo.ranked(from: response.videos?.results ?? [])
        imdbID = response.externalIDs?.imdbID
        tmdbProviders = response.watchProviders?.usStreamingOptions ?? []
        sameFranchiseKeys = []
        sharedContributorKeys = []

        let directorDTO = crewList.first { dto in
            dto.job == "Director"
        }
        director = directorDTO.map { dto in
            PersonSummary(dto, fallbackRole: "Director")
        }

        let creatorDTO = response.createdBy?.first
        creator = creatorDTO.map { dto in
            PersonSummary(dto, fallbackRole: "Creator")
        }

        let mappedCast: [PersonSummary] = castList.map { dto in
            PersonSummary(dto)
        }
        cast = mappedCast

        let keyCrewJobs: Set<String> = [
            "Director",
            "Creator",
            "Executive Producer",
            "Producer",
            "Writer",
            "Screenplay",
            "Story"
        ]

        let filteredCrewDTOs: [PersonDTO] = crewList.filter { dto in
            guard let job = dto.job else { return false }
            return keyCrewJobs.contains(job)
        }

        let mappedKeyCrew: [PersonSummary] = filteredCrewDTOs.map { dto in
            PersonSummary(dto)
        }

        let castIDs = Set(mappedCast.map { person in
            person.id
        })
        let uniqueKeyCrew = mappedKeyCrew.uniquedPeople(excluding: castIDs)
        castAndKeyCrew = mappedCast + uniqueKeyCrew

        let rawSeasons: [SeasonDTO] = response.seasons ?? []
        let normalSeasons = rawSeasons.filter { season in
            (season.seasonNumber ?? 0) > 0
        }
        seasons = normalSeasons.map { season in
            let number = season.seasonNumber ?? 1
            let name = season.name ?? "Season \(number)"
            let airDate = season.airDate
            let episodes: [EpisodeInfo] = (season.episodes ?? []).map { episode in
                let episodeNumber = episode.episodeNumber ?? 1
                return EpisodeInfo(
                    number: episodeNumber,
                    title: episode.name ?? "Episode \(episodeNumber)",
                    airDate: episode.airDate,
                    runtime: episode.runtime,
                    stillPath: episode.stillPath
                )
            }
            let count = season.episodeCount ?? episodes.count
            return SeasonInfo(number: number, name: name, airDate: airDate, episodeCount: count, episodes: episodes)
        }

        let recommendationItems: [MediaItem] = (response.recommendations?.results ?? []).map { MediaItem($0) }
        let similarItems: [MediaItem] = (response.similar?.results ?? []).map { MediaItem($0) }
        let strongAPISimilarityKeys = Set(recommendationItems.map(\.key))
        let mediumAPISimilarityKeys = Set(similarItems.map(\.key)).subtracting(strongAPISimilarityKeys)
        self.strongAPISimilarityKeys = strongAPISimilarityKeys
        self.mediumAPISimilarityKeys = mediumAPISimilarityKeys
        let mappedSimilar: [MediaItem] = recommendationItems + similarItems
        similar = Self.rankedSimilarItems(
            mappedSimilar.uniqued().filter { $0.shouldShowInDiscovery && !$0.isUpcoming && $0.key != fallback.key },
            source: fallback,
            strongAPISimilarityKeys: strongAPISimilarityKeys,
            mediumAPISimilarityKeys: mediumAPISimilarityKeys
        )
    }

    func addingSimilarCandidates(
        _ candidates: [MediaItem],
        source: MediaItem,
        sameFranchiseKeys: Set<MediaKey> = [],
        strongAPISimilarityKeys: Set<MediaKey> = [],
        mediumAPISimilarityKeys: Set<MediaKey> = [],
        sharedContributorKeys: Set<MediaKey> = []
    ) -> MediaDetail {
        let mergedSameFranchiseKeys = self.sameFranchiseKeys.union(sameFranchiseKeys)
        let mergedStrongAPISimilarityKeys = self.strongAPISimilarityKeys.union(strongAPISimilarityKeys)
        let mergedMediumAPISimilarityKeys = self.mediumAPISimilarityKeys.union(mediumAPISimilarityKeys)
        let mergedSharedContributorKeys = self.sharedContributorKeys.union(sharedContributorKeys)

        return MediaDetail(
            director: director,
            creator: creator,
            cast: cast,
            castAndKeyCrew: castAndKeyCrew,
            seasons: seasons,
            similar: Self.rankedSimilarItems(
                (similar + candidates).uniqued().filter { $0.shouldShowInDiscovery && !$0.isUpcoming && $0.key != source.key },
                source: source,
                sameFranchiseKeys: mergedSameFranchiseKeys,
                strongAPISimilarityKeys: mergedStrongAPISimilarityKeys,
                mediumAPISimilarityKeys: mergedMediumAPISimilarityKeys,
                sharedContributorKeys: mergedSharedContributorKeys
            ),
            firstAirDate: firstAirDate,
            lastAirDate: lastAirDate,
            status: status,
            runtime: runtime,
            ageRating: ageRating,
            tmdbCollectionID: tmdbCollectionID,
            keywordIDs: keywordIDs,
            trailers: trailers,
            imdbID: imdbID,
            tmdbProviders: tmdbProviders,
            sameFranchiseKeys: mergedSameFranchiseKeys,
            strongAPISimilarityKeys: mergedStrongAPISimilarityKeys,
            mediumAPISimilarityKeys: mergedMediumAPISimilarityKeys,
            sharedContributorKeys: mergedSharedContributorKeys
        )
    }

    var primaryTrailer: TrailerVideo? {
        trailers.first
    }

    private init(director: PersonSummary?, creator: PersonSummary?, cast: [PersonSummary], castAndKeyCrew: [PersonSummary], seasons: [SeasonInfo], similar: [MediaItem], firstAirDate: String?, lastAirDate: String?, status: String?, runtime: Int?, ageRating: String?, tmdbCollectionID: Int?, keywordIDs: [Int], trailers: [TrailerVideo], imdbID: String?, tmdbProviders: [StreamingOption], sameFranchiseKeys: Set<MediaKey>, strongAPISimilarityKeys: Set<MediaKey>, mediumAPISimilarityKeys: Set<MediaKey>, sharedContributorKeys: Set<MediaKey>) {
        self.director = director
        self.creator = creator
        self.cast = cast
        self.castAndKeyCrew = castAndKeyCrew
        self.seasons = seasons
        self.similar = similar
        self.firstAirDate = firstAirDate
        self.lastAirDate = lastAirDate
        self.status = status
        self.runtime = runtime
        self.ageRating = ageRating
        self.tmdbCollectionID = tmdbCollectionID
        self.keywordIDs = keywordIDs
        self.trailers = trailers
        self.imdbID = imdbID
        self.tmdbProviders = tmdbProviders
        self.sameFranchiseKeys = sameFranchiseKeys
        self.strongAPISimilarityKeys = strongAPISimilarityKeys
        self.mediumAPISimilarityKeys = mediumAPISimilarityKeys
        self.sharedContributorKeys = sharedContributorKeys
    }

    static func rankedSimilarItems(
        _ items: [MediaItem],
        source: MediaItem,
        sameFranchiseKeys: Set<MediaKey> = [],
        strongAPISimilarityKeys: Set<MediaKey> = [],
        mediumAPISimilarityKeys: Set<MediaKey> = [],
        sharedContributorKeys: Set<MediaKey> = []
    ) -> [MediaItem] {
        let sourceGenres = Set(source.genreIDs)
        let sourceLanguage = source.originalLanguage
        let sourceYear = source.releaseYearNumber
        let sourceVote = source.voteAverage
        let sourceTokens = recommendationTokens(for: source)
        let sourceTone = genreVector(for: source)

        let scoredItems = items.enumerated()
            .compactMap { entry -> (item: MediaItem, score: Double, inputIndex: Int)? in
                let inputIndex = entry.offset
                let item = entry.element
                let sameFranchise = sameFranchiseKeys.contains(item.key)
                let strongAPISimilarity = strongAPISimilarityKeys.contains(item.key)
                let mediumAPISimilarity = mediumAPISimilarityKeys.contains(item.key)
                let sharedContributor = sharedContributorKeys.contains(item.key)
                let isTVSource = source.kind == .tv
                let isCrossKindForTVSource = isTVSource && item.kind != source.kind
                let itemGenres = Set(item.genreIDs)
                let sharedGenres = sourceGenres.intersection(itemGenres)
                let sharedSpecificTokens = sourceTokens.intersection(recommendationTokens(for: item))
                let titleScore = titleRelationshipScore(sourceTitle: source.title, itemTitle: item.title)
                let evidence = similarityEvidenceScore(
                    source: source,
                    item: item,
                    sharedSpecificTokens: sharedSpecificTokens,
                    sourceGenres: sourceGenres,
                    itemGenres: itemGenres
                )

                let hasSourceEvidence = sameFranchise || strongAPISimilarity || mediumAPISimilarity || sharedContributor
                let hasHumanEvidence = evidence.passesGate || sharedSpecificTokens.count >= 2 || titleScore >= 18
                guard hasSourceEvidence || hasHumanEvidence else {
                    return nil
                }

                if isCrossKindForTVSource && !sameFranchise && !strongAPISimilarity {
                    return nil
                }

                var score = 0.0

                if sameFranchise {
                    score += 80.0
                }

                if strongAPISimilarity {
                    score += 32.0
                }

                if mediumAPISimilarity {
                    score += isTVSource ? 6.0 : 13.0
                }

                if sharedContributor {
                    score += isTVSource ? 2.0 : 8.0
                }

                let strongGenreOverlap = sharedGenres.filter { !moreLikeThisWeakSimilarityGenreIDs.contains($0) }.count
                let weakGenreOverlap = sharedGenres.filter { moreLikeThisWeakSimilarityGenreIDs.contains($0) }.count
                score += Double(strongGenreOverlap) * 5.5
                score += Double(weakGenreOverlap) * 1.2
                score += isTVSource && !sameFranchise && !strongAPISimilarity ? min(titleScore, 8.0) : titleScore
                score += evidence.score
                score += min(Double(sharedSpecificTokens.count) * (isTVSource ? 1.6 : 3.0), isTVSource ? 8.0 : 18.0)

                let toneSimilarity = sourceTone.similarity(to: genreVector(for: item))
                score += toneSimilarity * 7.0

                if let sourceYear, let itemYear = item.releaseYearNumber {
                    let diff = abs(sourceYear - itemYear)
                    if diff == 0 {
                        score += 4.0
                    } else if diff <= 3 {
                        score += 3.0
                    } else if diff <= 7 {
                        score += 1.6
                    } else if diff > 25, !sameFranchise {
                        score -= 1.4
                    }
                }

                if source.kind == item.kind {
                    score += 3.0
                } else if sameFranchise || strongAPISimilarity {
                    score += 0.8
                } else {
                    score -= 2.0
                }

                if item.originalLanguage == sourceLanguage {
                    score += 2.0
                } else if !sameFranchise && !strongAPISimilarity {
                    score -= 1.2
                }

                if sourceVote > 0, item.voteAverage > 0 {
                    let voteDelta = abs(sourceVote - item.voteAverage)
                    if voteDelta <= 0.5 {
                        score += 2.0
                    } else if voteDelta <= 1.0 {
                        score += 1.0
                    }
                }

                if item.voteAverage >= 7.5 {
                    score += 2.0
                } else if item.voteAverage >= 6.5 {
                    score += 0.8
                } else if item.voteAverage > 0 {
                    score -= 2.5
                }

                if let voteCount = item.voteCount {
                    if voteCount >= 1_000 {
                        score += 1.4
                    } else if voteCount < 25, !sameFranchise {
                        score -= 3.0
                    }
                }

                if sourceGenres.isDisjoint(with: itemGenres), !sameFranchise, !strongAPISimilarity, sharedSpecificTokens.isEmpty {
                    score -= 10.0
                }

                let minimumScore = isTVSource && !mediumAPISimilarity ? 14.0 : 11.0
                if !sameFranchise && !strongAPISimilarity && score < minimumScore {
                    return nil
                }

                return (item, score, inputIndex)
            }

        return scoredItems
            .sorted { lhs, rhs in
                let lhsFranchise = sameFranchiseKeys.contains(lhs.item.key)
                let rhsFranchise = sameFranchiseKeys.contains(rhs.item.key)
                if lhsFranchise != rhsFranchise { return lhsFranchise }

                if lhsFranchise && rhsFranchise, lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }

                return lhs.inputIndex < rhs.inputIndex
            }
            .map(\.item)
            .uniqued()
    }

    private struct RecommendationGenreVector {
        let action: Double
        let comedy: Double
        let horror: Double
        let mystery: Double
        let romance: Double
        let speculative: Double
        let family: Double
        let documentary: Double
        let crime: Double
        let prestigeDrama: Double

        func similarity(to other: RecommendationGenreVector) -> Double {
            let lhs = [action, comedy, horror, mystery, romance, speculative, family, documentary, crime, prestigeDrama]
            let rhs = [other.action, other.comedy, other.horror, other.mystery, other.romance, other.speculative, other.family, other.documentary, other.crime, other.prestigeDrama]
            let dot = zip(lhs, rhs).reduce(0.0) { $0 + ($1.0 * $1.1) }
            let lhsMagnitude = sqrt(lhs.reduce(0.0) { $0 + ($1 * $1) })
            let rhsMagnitude = sqrt(rhs.reduce(0.0) { $0 + ($1 * $1) })
            guard lhsMagnitude > 0, rhsMagnitude > 0 else { return 0 }
            return dot / (lhsMagnitude * rhsMagnitude)
        }
    }

    private static func genreVector(for item: MediaItem) -> RecommendationGenreVector {
        let genres = Set(item.genreIDs)

        func has(_ ids: Set<Int>) -> Double {
            genres.isDisjoint(with: ids) ? 0.0 : 1.0
        }

        return RecommendationGenreVector(
            action: has([28, 12, 53, 10752, 10759]),
            comedy: has([35]),
            horror: has([27]),
            mystery: has([9648]),
            romance: has([10749]),
            speculative: has([878, 14, 10765]),
            family: has([16, 10751, 10762]),
            documentary: has([99]),
            crime: has([80]),
            prestigeDrama: has([18, 36])
        )
    }

    private static func recommendationTokens(for item: MediaItem) -> Set<String> {
        let combinedText = item.title + " " + item.overview
        let normalizedText = normalizedSimilarityText(combinedText)
        let tokenParts: [Substring] = normalizedText.split(separator: " ")
        var tokens = Set<String>()

        for tokenPart in tokenParts {
            let token = String(tokenPart)
            guard token.count >= 6 else { continue }
            guard token.rangeOfCharacter(from: .decimalDigits) == nil else { continue }
            tokens.insert(token)
        }

        return tokens
    }

    private struct SimilarityEvidence {
        let score: Double
        let strongSignalCount: Int
        let mediumSignalCount: Int

        var passesGate: Bool {
            strongSignalCount >= 1 || mediumSignalCount >= 3 || score >= 9.0
        }
    }

    private static func relaxedSimilarityPass(
        titleScore: Double,
        evidence: SimilarityEvidence,
        sharedSpecificTokenCount: Int,
        mediumAPISimilarity: Bool
    ) -> Bool {
        if titleScore >= 12 {
            return true
        }

        if evidence.strongSignalCount >= 1 {
            return true
        }

        if evidence.mediumSignalCount >= 2, sharedSpecificTokenCount >= 1 {
            return true
        }

        if sharedSpecificTokenCount >= 2, evidence.score >= 5.0 {
            return true
        }

        if mediumAPISimilarity && sharedSpecificTokenCount >= 1 {
            return true
        }

        return false
    }

    private static func similarityEvidenceScore(
        source: MediaItem,
        item: MediaItem,
        sharedSpecificTokens: Set<String>,
        sourceGenres: Set<Int>,
        itemGenres: Set<Int>
    ) -> SimilarityEvidence {
        var score = 0.0
        var strong = 0
        var medium = 0

        let titleScore = titleRelationshipScore(sourceTitle: source.title, itemTitle: item.title)
        if titleScore >= 36 {
            score += titleScore
            strong += 1
        } else if titleScore >= 18 {
            score += titleScore
            medium += 1
        }

        if sharedSpecificTokens.count >= 3 {
            score += Double(sharedSpecificTokens.count) * 4.0
            strong += 1
        } else if sharedSpecificTokens.count >= 1 {
            score += Double(sharedSpecificTokens.count) * 2.2
            medium += 1
        }

        let strongGenreOverlap = sourceGenres.intersection(itemGenres).filter { !moreLikeThisWeakSimilarityGenreIDs.contains($0) }.count
        if strongGenreOverlap >= 1 {
            score += Double(strongGenreOverlap) * 2.6
            medium += 1
        }

        let weakGenreOverlap = sourceGenres.intersection(itemGenres).filter { moreLikeThisWeakSimilarityGenreIDs.contains($0) }.count
        if weakGenreOverlap >= 2, medium >= 1 || strong >= 1 {
            score += min(Double(weakGenreOverlap) * 0.8, 1.6)
        }

        return SimilarityEvidence(score: score, strongSignalCount: strong, mediumSignalCount: medium)
    }

    private static func normalizedSimilarityText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func titleStem(_ value: String) -> String {
        normalizedSimilarityText(value)
            .replacingOccurrences(of: "\\b(the|a|an|of|from|part|chapter|season|movie|film|series)\\b", with: "", options: .regularExpression)
            .split(separator: " ")
            .prefix(3)
            .joined(separator: " ")
    }

    private static func titleRelationshipScore(sourceTitle: String, itemTitle: String) -> Double {
        let source = normalizedSimilarityText(sourceTitle)
        let item = normalizedSimilarityText(itemTitle)
        guard !source.isEmpty, !item.isEmpty else { return 0 }
        if source == item { return 42 }

        if item.hasPrefix(source + " ") {
            let suffix = item.dropFirst(source.count).trimmingCharacters(in: .whitespacesAndNewlines)
            let firstToken = suffix.split(separator: " ").first.map(String.init) ?? ""

            if isSequelOrdinalToken(firstToken) {
                return 92
            }

            if suffix.hasPrefix("part ") || suffix.hasPrefix("chapter ") || suffix.hasPrefix("vol ") || suffix.hasPrefix("volume ") {
                return 78
            }

            return 38
        }

        let sourceStem = titleStem(sourceTitle)
        let itemStem = titleStem(itemTitle)
        if !sourceStem.isEmpty && sourceStem == itemStem { return 36 }
        let sourceStemTokens = sourceStem.split(separator: " ")
        let itemStemTokens = itemStem.split(separator: " ")
        let shorterStem = sourceStem.count <= itemStem.count ? sourceStem : itemStem
        let hasMeaningfulContainedStem = shorterStem.count >= 8 && sourceStemTokens.count >= 2 && itemStemTokens.count >= 2
        if hasMeaningfulContainedStem && (itemStem.contains(sourceStem) || sourceStem.contains(itemStem)) { return 18 }
        return 0
    }

    private static func isSequelOrdinalToken(_ token: String) -> Bool {
        if let number = Int(token), number > 1 {
            return true
        }

        guard token.range(of: #"^[ivxlcdm]+$"#, options: .regularExpression) != nil else {
            return false
        }

        var previous = 0
        var total = 0

        for character in token.reversed() {
            let value: Int
            switch character {
            case "i": value = 1
            case "v": value = 5
            case "x": value = 10
            case "l": value = 50
            case "c": value = 100
            case "d": value = 500
            case "m": value = 1000
            default: return false
            }

            if value < previous {
                total -= value
            } else {
                total += value
                previous = value
            }
        }

        return total > 1
    }

    var yearRangeText: String {
        guard let startYear = firstAirDate?.prefix(4), !startYear.isEmpty else {
            return "Unknown"
        }

        let normalizedStatus = status?.lowercased() ?? ""

        if normalizedStatus.contains("returning") ||
            normalizedStatus.contains("planned") ||
            normalizedStatus.contains("production") {
            return "\(startYear)–present"
        }

        if let endYear = lastAirDate?.prefix(4), !endYear.isEmpty, endYear != startYear {
            return "\(startYear)–\(endYear)"
        }

        return String(startYear)
    }
}
