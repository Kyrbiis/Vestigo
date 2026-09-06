import Foundation

extension MediaDetail {

    static func rankedSimilarItems(
        _ items: [MediaItem],
        source: MediaItem,
        sameFranchiseKeys: Set<MediaKey> = [],
        strongAPISimilarityKeys: Set<MediaKey> = [],
        mediumAPISimilarityKeys: Set<MediaKey> = [],
        sharedContributorKeys: Set<MediaKey> = [],
        externalRatings: [MediaKey: ExternalRatings] = [:]
    ) -> [MediaItem] {
        let sourceGenres = Set(source.genreIDs)
        let sourceLanguage = source.originalLanguage
        let sourceYear = source.releaseYearNumber
        let sourceVote = externalRatings[source.key]?.imdbRating ?? source.voteAverage
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

                // Dynamic quality floor: medium-API-only items must be within 2 points of the source's rating.
                // If the source is low-rated, the floor is low too — no artificial floor for low-quality browsing.
                let candidateRating = externalRatings[item.key]?.imdbRating ?? item.voteAverage
                if mediumAPISimilarity && !strongAPISimilarity && !sameFranchise && !sharedContributor
                    && sharedSpecificTokens.count < 2
                    && sourceVote > 0 && candidateRating > 0 && candidateRating < max(0, sourceVote - 2.0) {
                    return nil
                }

                var score = 0.0

                if sameFranchise {
                    score += 250.0
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
                        score += 5.0
                    } else if diff <= 3 {
                        score += 4.0
                    } else if diff <= 7 {
                        score += 2.5
                    } else if diff <= 15 {
                        score += 0.5
                    } else if diff <= 25, !sameFranchise {
                        score -= 1.5
                    } else if diff <= 40, !sameFranchise {
                        score -= 5.0
                    } else if diff <= 60, !sameFranchise {
                        score -= 10.0
                    } else if !sameFranchise {
                        score -= 18.0
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

                if sourceVote > 0, candidateRating > 0 {
                    let voteDelta = abs(sourceVote - candidateRating)
                    if voteDelta <= 0.5 {
                        score += 2.0
                    } else if voteDelta <= 1.0 {
                        score += 1.0
                    } else if voteDelta >= 2.0, !sameFranchise, !strongAPISimilarity {
                        // Penalise large quality gaps — scales with gap, capped at -4.5
                        score -= min((voteDelta - 1.0) * 2.0, 4.5)
                    }
                }

                if candidateRating >= 7.5 {
                    score += 2.0
                } else if candidateRating >= 6.5 {
                    score += 0.8
                } else if candidateRating >= 5.5 {
                    score -= 2.5
                } else if candidateRating > 0 {
                    score -= 5.0
                }

                if let voteCount = item.voteCount {
                    if voteCount >= 1_000 {
                        score += 1.4
                    } else if voteCount < 25, !sameFranchise {
                        score -= 3.0
                    } else if voteCount < 300, !sameFranchise, !strongAPISimilarity {
                        score -= 1.5
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

        let sorted = scoredItems
            .sorted { lhs, rhs in
                let lhsFranchise = sameFranchiseKeys.contains(lhs.item.key)
                let rhsFranchise = sameFranchiseKeys.contains(rhs.item.key)
                if lhsFranchise != rhsFranchise { return lhsFranchise }
                if lhsFranchise { return lhs.score > rhs.score }

                // For TMDb recommendations (strongAPI), score-sort so our thematic scoring
                // re-orders them — puts closer matches first even without franchise data.
                // For TMDb similar results (mediumAPI) and everything else, preserve TMDb's
                // input order since their similarity ordering is better than ours for that tier.
                let lhsStrong = strongAPISimilarityKeys.contains(lhs.item.key)
                let rhsStrong = strongAPISimilarityKeys.contains(rhs.item.key)
                if lhsStrong != rhsStrong { return lhsStrong }
                if lhsStrong { return lhs.score > rhs.score }

                return lhs.inputIndex < rhs.inputIndex
            }
            .map(\.item)
            .uniqued()

        // 10+ franchise members: franchise context dominates, drop non-franchise tail.
        // Fewer than 10: franchise floats to the top, non-franchise fills the rest.
        let franchiseOnly = sorted.filter { sameFranchiseKeys.contains($0.key) }
        return franchiseOnly.count >= 10 ? franchiseOnly : sorted
    }

    struct RecommendationGenreVector {
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

    static func genreVector(for item: MediaItem) -> RecommendationGenreVector {
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

    static func recommendationTokens(for item: MediaItem) -> Set<String> {
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

    struct SimilarityEvidence {
        let score: Double
        let strongSignalCount: Int
        let mediumSignalCount: Int

        var passesGate: Bool {
            strongSignalCount >= 1 || mediumSignalCount >= 3 || score >= 9.0
        }
    }

    static func relaxedSimilarityPass(
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

    static func similarityEvidenceScore(
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

    static func normalizedSimilarityText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func titleStem(_ value: String) -> String {
        normalizedSimilarityText(value)
            .replacingOccurrences(of: "\\b(the|a|an|of|from|part|chapter|season|movie|film|series)\\b", with: "", options: .regularExpression)
            .split(separator: " ")
            .prefix(3)
            .joined(separator: " ")
    }

    static func titleRelationshipScore(sourceTitle: String, itemTitle: String) -> Double {
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

    static func isSequelOrdinalToken(_ token: String) -> Bool {
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
}
