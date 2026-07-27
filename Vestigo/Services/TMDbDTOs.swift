import Foundation

struct TMDbListResponse: Decodable { let results: [TMDbMediaDTO] }

struct TMDbPersonSearchResponse: Decodable {
    let results: [TMDbPersonSearchDTO]
}

struct TMDbPersonSearchDTO: Decodable {
    let id: Int
    let name: String
    let knownForDepartment: String?
    let profilePath: String?
    let popularity: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, popularity
        case knownForDepartment = "known_for_department"
        case profilePath = "profile_path"
    }
}


struct TMDbPersonCreditsResponse: Decodable {
    let cast: [TMDbMediaDTO]
    let crew: [TMDbMediaDTO]
}

struct TMDbPersonDetailResponse: Decodable {
    let id: Int
    let biography: String?
    let birthday: String?
    let deathday: String?
    let placeOfBirth: String?
    let knownForDepartment: String?
    let imdbID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case biography
        case birthday
        case deathday
        case placeOfBirth = "place_of_birth"
        case knownForDepartment = "known_for_department"
        case imdbID = "imdb_id"
    }
}

struct TMDbMediaDTO: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let character: String?
    let job: String?
    let mediaType: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let voteCount: Int?
    let genreIDs: [Int]?
    let originalLanguage: String?
    let birthday: String?
    let deathday: String?
    let placeOfBirth: String?
    let knownForDepartment: String?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview, character, job
        case mediaType = "media_type"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case genreIDs = "genre_ids"
        case originalLanguage = "original_language"
        case birthday
        case deathday
        case placeOfBirth = "place_of_birth"
        case knownForDepartment = "known_for_department"
    }
}

struct TMDbGenreDTO: Decodable {
    let id: Int
    let name: String?
}

struct TMDbStandaloneMediaDTO: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let voteCount: Int?
    let genres: [TMDbGenreDTO]?
    let runtime: Int?
    let originalLanguage: String?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview, genres, runtime
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case originalLanguage = "original_language"
    }
}

struct TMDbCollectionReference: Codable, Hashable {
    let id: Int?
    let name: String?
}

struct TMDbDetailResponse: Decodable {
    let runtime: Int?
    let numberOfSeasons: Int?
    let numberOfEpisodes: Int?
    let seasons: [SeasonDTO]?
    let firstAirDate: String?
    let lastAirDate: String?
    let status: String?
    let createdBy: [PersonDTO]?
    let credits: CreditsDTO?
    let similar: TMDbListResponse?
    let recommendations: TMDbListResponse?
    let releaseDates: TMDbReleaseDatesResponse?
    let contentRatings: TMDbContentRatingsResponse?
    let belongsToCollection: TMDbCollectionReference?
    let keywords: TMDbKeywordsResponse?
    let videos: TMDbVideosResponse?
    let externalIDs: TMDbExternalIDsResponse?
    let watchProviders: TMDbWatchProvidersResponse?
    let networks: [TMDbNetworkDTO]?

    enum CodingKeys: String, CodingKey {
        case runtime
        case numberOfSeasons = "number_of_seasons"
        case numberOfEpisodes = "number_of_episodes"
        case seasons
        case firstAirDate = "first_air_date"
        case lastAirDate = "last_air_date"
        case status
        case createdBy = "created_by"
        case credits
        case similar
        case recommendations
        case releaseDates = "release_dates"
        case contentRatings = "content_ratings"
        case belongsToCollection = "belongs_to_collection"
        case keywords
        case videos
        case externalIDs = "external_ids"
        case watchProviders = "watch/providers"
        case networks
    }

    init(
        runtime: Int?,
        numberOfSeasons: Int?,
        numberOfEpisodes: Int?,
        seasons: [SeasonDTO]?,
        firstAirDate: String?,
        lastAirDate: String?,
        status: String?,
        createdBy: [PersonDTO]?,
        credits: CreditsDTO?,
        similar: TMDbListResponse?,
        recommendations: TMDbListResponse?,
        releaseDates: TMDbReleaseDatesResponse?,
        contentRatings: TMDbContentRatingsResponse?,
        belongsToCollection: TMDbCollectionReference?,
        keywords: TMDbKeywordsResponse?,
        videos: TMDbVideosResponse?,
        externalIDs: TMDbExternalIDsResponse?,
        watchProviders: TMDbWatchProvidersResponse?,
        networks: [TMDbNetworkDTO]? = nil
    ) {
        self.runtime = runtime
        self.numberOfSeasons = numberOfSeasons
        self.numberOfEpisodes = numberOfEpisodes
        self.seasons = seasons
        self.firstAirDate = firstAirDate
        self.lastAirDate = lastAirDate
        self.status = status
        self.createdBy = createdBy
        self.credits = credits
        self.similar = similar
        self.recommendations = recommendations
        self.releaseDates = releaseDates
        self.contentRatings = contentRatings
        self.belongsToCollection = belongsToCollection
        self.keywords = keywords
        self.videos = videos
        self.externalIDs = externalIDs
        self.watchProviders = watchProviders
        self.networks = networks
    }

    func replacingSeasons(_ hydratedSeasons: [SeasonDTO]) -> TMDbDetailResponse {
        TMDbDetailResponse(
            runtime: runtime,
            numberOfSeasons: numberOfSeasons,
            numberOfEpisodes: numberOfEpisodes,
            seasons: hydratedSeasons,
            firstAirDate: firstAirDate,
            lastAirDate: lastAirDate,
            status: status,
            createdBy: createdBy,
            credits: credits,
            similar: similar,
            recommendations: recommendations,
            releaseDates: releaseDates,
            contentRatings: contentRatings,
            belongsToCollection: belongsToCollection,
            keywords: keywords,
            videos: videos,
            externalIDs: externalIDs,
            watchProviders: watchProviders,
            networks: networks
        )
    }
    
    var usAgeRating: String? {
        if let movieRating = releaseDates?.results
            .first(where: { $0.iso31661 == "US" })?
            .releaseDates
            .compactMap({ $0.certification?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return movieRating
        }
        
        if let tvRating = contentRatings?.results
            .first(where: { $0.iso31661 == "US" })?
            .rating?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !tvRating.isEmpty {
            return tvRating
        }
        
        return nil
    }
}

struct TMDbNetworkDTO: Decodable {
    let id: Int
    let name: String
}

struct TMDbKeywordsResponse: Decodable {
    let keywords: [TMDbKeyword]?
    let results: [TMDbKeyword]?

    var keywordIDs: [Int] {
        (keywords ?? results ?? []).map(\.id)
    }

    var keywordNames: [String] {
        (keywords ?? results ?? []).map(\.name)
    }
}

struct TMDbKeyword: Decodable, Hashable {
    let id: Int
    let name: String
}

struct TMDbVideosResponse: Decodable {
    let results: [TMDbVideoDTO]
}

struct TMDbVideoDTO: Decodable, Hashable {
    let id: String
    let key: String
    let name: String
    let site: String
    let type: String
    let official: Bool?
    let publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, key, name, site, type, official
        case publishedAt = "published_at"
    }
}

struct TMDbExternalIDsResponse: Decodable, Hashable {
    let imdbID: String?

    enum CodingKeys: String, CodingKey {
        case imdbID = "imdb_id"
    }
}

struct TMDbWatchProvidersResponse: Decodable, Hashable {
    let results: [String: TMDbWatchProviderRegion]

    var usStreamingOptions: [StreamingOption] {
        guard let region = results["US"] ?? results["us"] else { return [] }

        let groups: [(type: String, price: String, providers: [TMDbWatchProvider])] = [
            ("subscription", "Included", region.flatrate ?? []),
            ("free", "Free", region.free ?? []),
            ("rent", "", region.rent ?? []),
            ("buy", "", region.buy ?? [])
        ]

        return groups.flatMap { group in
            group.providers.map { provider in
                StreamingOption(
                    serviceName: provider.providerName,
                    type: group.type,
                    priceText: group.price,
                    qualityText: "",
                    openURL: region.link
                )
            }
        }
    }
}

struct TMDbWatchProviderRegion: Decodable, Hashable {
    let link: String?
    let flatrate: [TMDbWatchProvider]?
    let free: [TMDbWatchProvider]?
    let rent: [TMDbWatchProvider]?
    let buy: [TMDbWatchProvider]?
}

struct TMDbWatchProvider: Decodable, Hashable {
    let providerName: String

    enum CodingKeys: String, CodingKey {
        case providerName = "provider_name"
    }
}

struct TMDbReleaseDatesResponse: Decodable {
    let results: [TMDbReleaseDatesCountry]
}

struct TMDbReleaseDatesCountry: Decodable {
    let iso31661: String
    let releaseDates: [TMDbReleaseDate]
    
    enum CodingKeys: String, CodingKey {
        case iso31661 = "iso_3166_1"
        case releaseDates = "release_dates"
    }
}

struct TMDbReleaseDate: Decodable {
    let certification: String?
}

struct TMDbContentRatingsResponse: Decodable {
    let results: [TMDbContentRating]
}

struct TMDbContentRating: Decodable {
    let iso31661: String
    let rating: String?
    
    enum CodingKeys: String, CodingKey {
        case iso31661 = "iso_3166_1"
        case rating
    }
}

struct SeasonDTO: Decodable {
    let seasonNumber: Int?
    let name: String?
    let airDate: String?
    let episodeCount: Int?
    let episodes: [EpisodeDTO]?
    
    enum CodingKeys: String, CodingKey {
        case seasonNumber = "season_number"
        case name
        case airDate = "air_date"
        case episodeCount = "episode_count"
        case episodes
    }
    
    init(seasonNumber: Int?, name: String?, airDate: String?, episodeCount: Int?, episodes: [EpisodeDTO]?) {
        self.seasonNumber = seasonNumber
        self.name = name
        self.airDate = airDate
        self.episodeCount = episodeCount
        self.episodes = episodes
    }
    
    func mergingEpisodes(from hydratedSeason: SeasonDTO) -> SeasonDTO {
        SeasonDTO(
            seasonNumber: seasonNumber ?? hydratedSeason.seasonNumber,
            name: name ?? hydratedSeason.name,
            airDate: airDate ?? hydratedSeason.airDate,
            episodeCount: episodeCount ?? hydratedSeason.episodeCount ?? hydratedSeason.episodes?.count,
            episodes: hydratedSeason.episodes ?? episodes
        )
    }
}

struct EpisodeDTO: Decodable {
    let episodeNumber: Int?
    let name: String?
    let airDate: String?
    let runtime: Int?
    let stillPath: String?
    
    enum CodingKeys: String, CodingKey {
        case episodeNumber = "episode_number"
        case name
        case airDate = "air_date"
        case runtime
        case stillPath = "still_path"
    }
}
struct CreditsDTO: Decodable { let cast: [PersonDTO]?; let crew: [PersonDTO]? }
struct PersonDTO: Decodable {
    let id: Int
    let name: String
    let job: String?
    let character: String?
    let profilePath: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, job, character
        case profilePath = "profile_path"
    }
}
struct TMDbProviderResponse: Decodable { let results: [String: TMDbProviderRegion] }
struct TMDbProviderRegion: Decodable { let flatrate: [TMDbProvider]?; let free: [TMDbProvider]?; let rent: [TMDbProvider]?; let buy: [TMDbProvider]? }
struct TMDbProvider: Decodable { let providerName: String; enum CodingKeys: String, CodingKey { case providerName = "provider_name" } }

struct WatchmodeShowResponse: Decodable {
    let title: String?
    let tmdbId: String?
    let releaseYear: Int?
    let firstAirYear: Int?
    let streamingOptions: [String: [WatchmodeOption]]?
    
    enum CodingKeys: String, CodingKey {
        case title
        case tmdbId
        case releaseYear
        case firstAirYear
        case streamingOptions
    }
    
    var matchYear: Int? {
        releaseYear ?? firstAirYear
    }
    
    var normalizedTitle: String {
        (title ?? "").normalizedForMatching
    }
    
    var usOptions: [StreamingOption] {
        let options = streamingOptions?["us"] ?? streamingOptions?["US"] ?? []
        return options.map { option in
            StreamingOption(
                serviceName: option.displayServiceName,
                type: option.displayTypeText,
                priceText: option.displayPriceText,
                qualityText: option.displayQualityText,
                openURL: option.displayOpenURL
            )
        }
    }
}
