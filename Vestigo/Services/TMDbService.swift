import Foundation

struct TMDbService {
    private let base = "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api"
    
    func trending(filter: MediaFilter) async throws -> [MediaItem] {
        try await fetchList(path: "/trending/\(filter.tmdbPath)/week", query: [])
    }
    
    func popular(filter: MediaFilter) async throws -> [MediaItem] {
        if filter == .both {
            async let movies = fetchList(path: "/movie/popular", query: [])
            async let tv = fetchList(path: "/tv/popular", query: [])
            return try await (movies + tv).sorted { $0.voteAverage > $1.voteAverage }
        }
        return try await fetchList(path: "/\(filter.tmdbPath)/popular", query: [])
    }
    
    func newReleases(filter: MediaFilter) async throws -> [MediaItem] {
        var items: [MediaItem] = []
        var firstError: Error?

        if filter != .tv {
            do {
                items += try await fetchList(path: "/movie/now_playing", query: [URLQueryItem(name: "region", value: "US")])
            } catch {
                firstError = firstError ?? error
            }
        }

        if filter != .movie {
            do {
                items += try await fetchList(path: "/tv/on_the_air", query: [])
            } catch {
                firstError = firstError ?? error
            }
        }

        if items.isEmpty, let firstError {
            throw firstError
        }

        return items.uniqued()
    }
    
    func upcoming(filter: MediaFilter) async throws -> [MediaItem] {
        var items: [MediaItem] = []
        var firstError: Error?

        if filter != .tv {
            do {
                items += try await fetchList(path: "/movie/upcoming", query: [URLQueryItem(name: "region", value: "US")])
            } catch {
                firstError = firstError ?? error
            }
        }

        if filter != .movie {
            do {
                items += try await fetchList(path: "/discover/tv", query: [
                    URLQueryItem(name: "first_air_date.gte", value: DateParser.tmdbDateString(from: Date())),
                    URLQueryItem(name: "sort_by", value: "popularity.desc"),
                    URLQueryItem(name: "include_null_first_air_dates", value: "false")
                ])
            } catch {
                firstError = firstError ?? error
            }
        }

        if items.isEmpty, let firstError {
            throw firstError
        }

        return items.uniqued()
    }
    
    func topRated(kind: MediaKind, pages: Int = 5) async throws -> [MediaItem] {
        guard kind == .movie || kind == .tv else { return [] }
        let path = "/\(kind.tmdbPath)/top_rated"
        return try await withThrowingTaskGroup(of: [MediaItem].self) { group in
            for page in 1...max(pages, 1) {
                group.addTask { try await self.fetchList(path: path, query: [], page: page) }
            }
            var all: [MediaItem] = []
            for try await pageItems in group { all += pageItems }
            return all.uniqued().sorted { $0.voteAverage > $1.voteAverage }
        }
    }

    func search(query: String, filter: MediaFilter, includeAdult: Bool = false) async throws -> [MediaItem] {
        let path = filter == .both ? "/search/multi" : "/search/\(filter.tmdbPath)"
        return try await fetchList(path: path, query: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "include_adult", value: includeAdult ? "true" : "false")
        ])
        .filter { $0.kind != .person }
    }
    
    func searchPeople(query: String, includeAdult: Bool = false) async throws -> [PersonSummary] {
        let response: TMDbPersonSearchResponse = try await fetch(path: "/search/person", query: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "include_adult", value: includeAdult ? "true" : "false")
        ])
        
        return response.results
            .map { dto in
                PersonSummary(dto, fallbackRole: dto.knownForDepartment ?? "Person")
            }
            .uniquedPeople()
    }
    
    func contextualSearch(query: String, filter: MediaFilter, includeAdult: Bool = false) async throws -> [MediaItem] {
        let found = try await search(query: query, filter: filter, includeAdult: includeAdult)
        var more: [MediaItem] = []
        for item in found {
            more += (try? await recommendations(for: item.key)) ?? []
            more += (try? await sameSeriesOrSimilar(for: item.key)) ?? []
        }
        return more
    }
    
    func discover(genreID: Int, filter: MediaFilter, sort: GenreSort) async throws -> [MediaItem] {
        if Self.isEraID(genreID) {
            return try await discoverEra(eraID: genreID, filter: filter, sort: sort)
        }

        if let keywordIDs = Self.specialCategoryKeywordIDs[genreID] {
            return try await discoverKeywordCategory(keywordIDs: keywordIDs, filter: filter, sort: sort)
        }

        async let discoveredItems = discoverCategoryItems(genreID: genreID, filter: filter)
        async let curatedItems = curatedCategoryItems(genreID: genreID, filter: filter)

        return try await (discoveredItems + curatedItems)
            .uniqued()
            .prefixArray(50)
    }

    private func discoverCategoryItems(genreID: Int, filter: MediaFilter) async throws -> [MediaItem] {
        switch filter {
        case .both:
            async let movies = discoverCategorySingleMedia(genreID: genreID, media: "movie")
            async let series = discoverCategorySingleMedia(genreID: genreID, media: "tv")
            return try await (movies + series)
                .uniqued()
                .prefixArray(50)
        case .movie:
            return try await discoverCategorySingleMedia(genreID: genreID, media: "movie")
        case .tv:
            return try await discoverCategorySingleMedia(genreID: genreID, media: "tv")
        }
    }

    private func discoverKeywordCategory(keywordIDs: [Int], filter: MediaFilter, sort: GenreSort) async throws -> [MediaItem] {
        switch filter {
        case .both:
            async let movies = discoverKeywordCategorySingleMedia(keywordIDs: keywordIDs, media: "movie", sort: sort)
            async let series = discoverKeywordCategorySingleMedia(keywordIDs: keywordIDs, media: "tv", sort: sort)
            return try await (movies + series).uniqued().prefixArray(50)
        case .movie:
            return try await discoverKeywordCategorySingleMedia(keywordIDs: keywordIDs, media: "movie", sort: sort)
        case .tv:
            return try await discoverKeywordCategorySingleMedia(keywordIDs: keywordIDs, media: "tv", sort: sort)
        }
    }

    private func discoverKeywordCategorySingleMedia(keywordIDs: [Int], media: String, sort: GenreSort) async throws -> [MediaItem] {
        try await fetchListPages(path: "/discover/\(media)", query: [
            URLQueryItem(name: "sort_by", value: sort.tmdbSort),
            URLQueryItem(name: "with_keywords", value: keywordIDs.map(String.init).joined(separator: "|")),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "include_video", value: "false"),
            URLQueryItem(name: "vote_count.gte", value: media == "movie" ? "80" : "50"),
            URLQueryItem(name: "vote_average.gte", value: "5.5"),
            URLQueryItem(name: "region", value: "US"),
            URLQueryItem(name: "watch_region", value: "US")
        ], pages: 5)
    }
    
    private func curatedCategoryItems(genreID: Int, filter: MediaFilter) async throws -> [MediaItem] {
        guard let entries = Self.curatedCategoryEntries[genreID] else { return [] }
        var resolved: [MediaItem] = []
        
        let filteredEntries = entries.filter { entry in
            switch filter {
            case .both:
                return true
            case .movie:
                return entry.kind == .movie
            case .tv:
                return entry.kind == .tv
            }
        }
        
        let limitedEntries = Array(filteredEntries.prefix(6))
        try await withThrowingTaskGroup(of: MediaItem?.self) { group in
            for entry in limitedEntries {
                group.addTask {
                    try await resolveCuratedEntry(entry)
                }
            }

            for try await item in group {
                if let item {
                    resolved.append(item)
                }
            }
        }
        
        return resolved
            .uniqued()
            .prefixArray(6)
    }
    
    private func resolveCuratedEntry(_ entry: CuratedCategoryEntry) async throws -> MediaItem? {
        let results = try await search(query: entry.title, filter: entry.filter)
        let normalizedTarget = Self.normalizedTitle(entry.title)
        
        return results.first { item in
            item.kind == entry.kind && Self.normalizedTitle(item.title) == normalizedTarget
        } ?? results.first { item in
            item.kind == entry.kind && Self.normalizedTitle(item.title).contains(normalizedTarget)
        } ?? results.first { item in
            item.kind == entry.kind
        }
    }
    
    private static func normalizedTitle(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
    
    private struct CuratedCategoryEntry {
        let title: String
        let kind: MediaKind
        
        var filter: MediaFilter {
            kind == .tv ? .tv : .movie
        }
    }
    
    private static func movie(_ title: String) -> CuratedCategoryEntry {
        CuratedCategoryEntry(title: title, kind: .movie)
    }
    
    private static func show(_ title: String) -> CuratedCategoryEntry {
        CuratedCategoryEntry(title: title, kind: .tv)
    }

    private static let basedOnTrueStoryCategoryID = 30001
    private static let basedOnBookCategoryID = 30002
    private static let basedOnGameCategoryID = 30003

    private static let specialCategoryKeywordIDs: [Int: [Int]] = [
        basedOnTrueStoryCategoryID: [9672],
        basedOnBookCategoryID: [818],
        basedOnGameCategoryID: [41645]
    ]
    
    private static let curatedCategoryEntries: [Int: [CuratedCategoryEntry]] = [
        28: [
            movie("Die Hard"), movie("Terminator 2: Judgment Day"), movie("Mad Max: Fury Road"), movie("The Raid"), movie("John Wick"),
            movie("Mission: Impossible - Fallout"), movie("The Bourne Ultimatum"), movie("Speed"), movie("Police Story"), movie("Hard Boiled"),
            movie("Enter the Dragon"), movie("The Killer"), movie("Lethal Weapon"), movie("Predator"), movie("First Blood"),
            movie("Casino Royale"), movie("Skyfall"), movie("Top Gun: Maverick"), movie("The Fugitive"), movie("Heat"),
            movie("The Rock"), movie("True Lies"), movie("Face/Off"), movie("Con Air"), movie("Point Break"),
            movie("Kill Bill: Vol. 1"), movie("Kill Bill: Vol. 2"), movie("The Man from Nowhere"), movie("The Night Comes for Us"), movie("Ong-Bak"),
            movie("Dredd"), movie("Nobody"), movie("The Equalizer"), movie("Taken"), movie("Man on Fire"),
            movie("Extraction"), movie("Baby Driver"), movie("Atomic Blonde"), movie("Sicario"), movie("The Warriors"),
            show("24"), show("Reacher"), show("Jack Ryan"), show("The Night Manager"), show("Warrior"),
            show("The Terminal List"), show("Strike Back"), show("Banshee"), show("The Punisher"), show("Gangs of London")
        ],
        878: [
            movie("Blade Runner"), movie("Blade Runner 2049"), movie("The Matrix"), movie("Inception"), movie("Interstellar"),
            movie("2001: A Space Odyssey"), movie("Alien"), movie("Aliens"), movie("The Terminator"), movie("Back to the Future"),
            movie("The Empire Strikes Back"), movie("Star Wars"), movie("Return of the Jedi"), movie("Arrival"), movie("Dune"),
            movie("Dune: Part Two"), movie("The Martian"), movie("Minority Report"), movie("Children of Men"), movie("Ex Machina"),
            movie("Her"), movie("Eternal Sunshine of the Spotless Mind"), movie("WALL·E"), movie("District 9"), movie("Moon"),
            movie("A.I. Artificial Intelligence"), movie("Gattaca"), movie("The Fifth Element"), movie("Planet of the Apes"), movie("Rise of the Planet of the Apes"),
            movie("Dawn of the Planet of the Apes"), movie("War for the Planet of the Apes"), movie("Edge of Tomorrow"), movie("Looper"), movie("Source Code"),
            movie("Contact"), movie("Close Encounters of the Third Kind"), movie("Solaris"), movie("12 Monkeys"), movie("The Thing"),
            show("The Expanse"), show("Black Mirror"), show("Dark"), show("Severance"), show("Battlestar Galactica"),
            show("Doctor Who"), show("Fringe"), show("Westworld"), show("Foundation"), show("For All Mankind")
        ],
        14: [
            movie("The Lord of the Rings: The Fellowship of the Ring"), movie("The Lord of the Rings: The Two Towers"), movie("The Lord of the Rings: The Return of the King"), movie("The Wizard of Oz"), movie("Pan's Labyrinth"),
            movie("Harry Potter and the Prisoner of Azkaban"), movie("Harry Potter and the Deathly Hallows: Part 2"), movie("The Princess Bride"), movie("The NeverEnding Story"), movie("Labyrinth"),
            movie("The Dark Crystal"), movie("Willow"), movie("Stardust"), movie("Big Fish"), movie("Edward Scissorhands"),
            movie("The Shape of Water"), movie("Beauty and the Beast"), movie("Spirited Away"), movie("Howl's Moving Castle"), movie("Princess Mononoke"),
            movie("Crouching Tiger, Hidden Dragon"), movie("The Green Knight"), movie("The Chronicles of Narnia: The Lion, the Witch and the Wardrobe"), movie("The Hobbit: An Unexpected Journey"), movie("The Hobbit: The Desolation of Smaug"),
            movie("The Hobbit: The Battle of the Five Armies"), movie("Excalibur"), movie("Jason and the Argonauts"), movie("Clash of the Titans"), movie("The Fall"),
            movie("A Monster Calls"), movie("The Secret of Kells"), movie("Song of the Sea"), movie("Kubo and the Two Strings"), movie("Coraline"),
            movie("The Tale of The Princess Kaguya"), movie("The Red Turtle"), movie("Only Lovers Left Alive"), movie("Wings of Desire"), movie("Time Bandits"),
            show("Game of Thrones"), show("House of the Dragon"), show("The Witcher"), show("His Dark Materials"), show("The Sandman"),
            show("Merlin"), show("Once Upon a Time"), show("The Dark Crystal: Age of Resistance"), show("Shadow and Bone"), show("The Legend of Vox Machina")
        ],
        18: [
            movie("The Shawshank Redemption"), movie("The Godfather"), movie("The Godfather Part II"), movie("12 Angry Men"), movie("Schindler's List"),
            movie("The Green Mile"), movie("Forrest Gump"), movie("One Flew Over the Cuckoo's Nest"), movie("Good Will Hunting"), movie("Dead Poets Society"),
            movie("The Truman Show"), movie("The Social Network"), movie("There Will Be Blood"), movie("No Country for Old Men"), movie("Whiplash"),
            movie("Moonlight"), movie("Parasite"), movie("A Beautiful Mind"), movie("American Beauty"), movie("Million Dollar Baby"),
            movie("The Pianist"), movie("Life Is Beautiful"), movie("City of God"), movie("Amadeus"), movie("Raging Bull"),
            movie("Taxi Driver"), movie("Apocalypse Now"), movie("The Deer Hunter"), movie("Rocky"), movie("Rain Man"),
            movie("The King's Speech"), movie("Spotlight"), movie("Manchester by the Sea"), movie("Marriage Story"), movie("Nomadland"),
            movie("The Father"), movie("Minari"), movie("Sound of Metal"), movie("A Separation"), movie("Ikiru"),
            show("Breaking Bad"), show("Better Call Saul"), show("The Sopranos"), show("The Wire"), show("Mad Men"),
            show("Succession"), show("The Crown"), show("Six Feet Under"), show("Friday Night Lights"), show("The Bear")
        ],
        27: [
            movie("Psycho"), movie("The Shining"), movie("Alien"), movie("The Exorcist"), movie("Halloween"),
            movie("The Texas Chain Saw Massacre"), movie("A Nightmare on Elm Street"), movie("The Thing"), movie("Rosemary's Baby"), movie("Jaws"),
            movie("Night of the Living Dead"), movie("Dawn of the Dead"), movie("The Fly"), movie("Scream"), movie("Get Out"),
            movie("Hereditary"), movie("Midsommar"), movie("The Babadook"), movie("It Follows"), movie("The Witch"),
            movie("Let the Right One In"), movie("Train to Busan"), movie("28 Days Later"), movie("The Descent"), movie("The Conjuring"),
            movie("Insidious"), movie("Sinister"), movie("The Ring"), movie("Ringu"), movie("Audition"),
            movie("The Orphanage"), movie("REC"), movie("A Quiet Place"), movie("Us"), movie("Nope"),
            movie("Barbarian"), movie("Talk to Me"), movie("The Lighthouse"), movie("Carrie"), movie("Misery"),
            show("The Haunting of Hill House"), show("Midnight Mass"), show("Hannibal"), show("American Horror Story"), show("Penny Dreadful"),
            show("The Terror"), show("Bates Motel"), show("Castle Rock"), show("From"), show("Marianne")
        ],
        16: [
            movie("Spirited Away"), movie("Spider-Man: Into the Spider-Verse"), movie("Spider-Man: Across the Spider-Verse"), movie("Toy Story"), movie("Toy Story 2"),
            movie("Toy Story 3"), movie("Finding Nemo"), movie("The Incredibles"), movie("WALL·E"), movie("Up"),
            movie("Inside Out"), movie("Coco"), movie("Ratatouille"), movie("Monsters, Inc."), movie("Shrek"),
            movie("How to Train Your Dragon"), movie("The Iron Giant"), movie("The Lion King"), movie("Beauty and the Beast"), movie("Aladdin"),
            movie("The Nightmare Before Christmas"), movie("Coraline"), movie("Kubo and the Two Strings"), movie("Fantastic Mr. Fox"), movie("The Lego Movie"),
            movie("Akira"), movie("Ghost in the Shell"), movie("Princess Mononoke"), movie("Howl's Moving Castle"), movie("My Neighbor Totoro"),
            movie("Grave of the Fireflies"), movie("The Tale of The Princess Kaguya"), movie("Your Name."), movie("A Silent Voice"), movie("Wolf Children"),
            movie("The Secret of Kells"), movie("Song of the Sea"), movie("Persepolis"), movie("Waltz with Bashir"), movie("The Red Turtle"),
            show("Avatar: The Last Airbender"), show("Arcane"), show("BoJack Horseman"), show("Gravity Falls"), show("Samurai Jack"),
            show("Batman: The Animated Series"), show("Star Wars: The Clone Wars"), show("Adventure Time"), show("Over the Garden Wall"), show("Invincible")
        ],
        80: [
            movie("The Godfather"), movie("The Godfather Part II"), movie("Goodfellas"), movie("Pulp Fiction"), movie("The Departed"),
            movie("Se7en"), movie("The Silence of the Lambs"), movie("Heat"), movie("Scarface"), movie("Casino"),
            movie("Reservoir Dogs"), movie("L.A. Confidential"), movie("Fargo"), movie("No Country for Old Men"), movie("Zodiac"),
            movie("Prisoners"), movie("Memories of Murder"), movie("Oldboy"), movie("City of God"), movie("The Usual Suspects"),
            movie("M"), movie("Double Indemnity"), movie("Chinatown"), movie("The French Connection"), movie("Dog Day Afternoon"),
            movie("Serpico"), movie("The Untouchables"), movie("A Bronx Tale"), movie("Carlito's Way"), movie("Road to Perdition"),
            movie("Mystic River"), movie("Gone Girl"), movie("Nightcrawler"), movie("Sicario"), movie("Training Day"),
            movie("Collateral"), movie("Inside Man"), movie("The Girl with the Dragon Tattoo"), movie("Eastern Promises"), movie("A History of Violence"),
            show("The Wire"), show("The Sopranos"), show("Breaking Bad"), show("Better Call Saul"), show("True Detective"),
            show("Fargo"), show("Mindhunter"), show("Narcos"), show("Ozark"), show("Peaky Blinders")
        ],
        35: [
            movie("Some Like It Hot"), movie("Dr. Strangelove or: How I Learned to Stop Worrying and Love the Bomb"), movie("Monty Python and the Holy Grail"), movie("Life of Brian"), movie("Airplane!"),
            movie("The Big Lebowski"), movie("Groundhog Day"), movie("Ghostbusters"), movie("Back to the Future"), movie("The Princess Bride"),
            movie("Ferris Bueller's Day Off"), movie("Planes, Trains and Automobiles"), movie("When Harry Met Sally..."), movie("Annie Hall"), movie("The Apartment"),
            movie("City Lights"), movie("Modern Times"), movie("The General"), movie("Duck Soup"), movie("Young Frankenstein"),
            movie("Blazing Saddles"), movie("This Is Spinal Tap"), movie("Office Space"), movie("Shaun of the Dead"), movie("Hot Fuzz"),
            movie("Superbad"), movie("Bridesmaids"), movie("Mean Girls"), movie("Clueless"), movie("School of Rock"),
            movie("Tropic Thunder"), movie("Borat"), movie("The Grand Budapest Hotel"), movie("Fantastic Mr. Fox"), movie("Hunt for the Wilderpeople"),
            movie("Jojo Rabbit"), movie("Knives Out"), movie("Palm Springs"), movie("Game Night"), movie("The Nice Guys"),
            show("Seinfeld"), show("The Office"), show("Parks and Recreation"), show("Community"), show("Arrested Development"),
            show("30 Rock"), show("Brooklyn Nine-Nine"), show("It's Always Sunny in Philadelphia"), show("Curb Your Enthusiasm"), show("What We Do in the Shadows")
        ]
    ]
    
    private static func isEraID(_ id: Int) -> Bool {
        id == 1980 || id == 1990 || id == 2000 || id == 2010
    }
    
    private func discoverEra(eraID: Int, filter: MediaFilter, sort: GenreSort) async throws -> [MediaItem] {
        let years: (start: String, end: String)
        
        switch eraID {
        case 1980:
            years = ("1980-01-01", "1989-12-31")
        case 1990:
            years = ("1990-01-01", "1999-12-31")
        case 2000:
            years = ("2000-01-01", "2009-12-31")
        case 2010:
            years = ("2010-01-01", "2019-12-31")
        default:
            years = ("1980-01-01", "2019-12-31")
        }
        
        if filter == .both {
            async let movies = discoverEraSingleMedia(years: years, media: "movie", sort: sort)
            async let shows = discoverEraSingleMedia(years: years, media: "tv", sort: sort)
            
            return try await (movies + shows)
                .uniqued()
                .sorted(using: .tmdbRating, ratings: [:])
        }
        
        let media = filter == .tv ? "tv" : "movie"
        return try await discoverEraSingleMedia(years: years, media: media, sort: sort)
    }
    
    private func discoverEraSingleMedia(years: (start: String, end: String), media: String, sort: GenreSort) async throws -> [MediaItem] {
        let datePrefix = media == "tv" ? "first_air_date" : "primary_release_date"
        let minVoteCount = media == "tv" ? "350" : "1200"
        let minVoteAverage = media == "tv" ? "7.0" : "6.8"
        
        return try await fetchList(path: "/discover/\(media)", query: [
            URLQueryItem(name: "sort_by", value: sort.tmdbSort),
            URLQueryItem(name: "with_original_language", value: "en"),
            URLQueryItem(name: "vote_count.gte", value: minVoteCount),
            URLQueryItem(name: "vote_average.gte", value: minVoteAverage),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "include_video", value: "false"),
            URLQueryItem(name: "region", value: "US"),
            URLQueryItem(name: "watch_region", value: "US"),
            URLQueryItem(name: "with_watch_monetization_types", value: "flatrate|free|rent|buy"),
            URLQueryItem(name: "\(datePrefix).gte", value: years.start),
            URLQueryItem(name: "\(datePrefix).lte", value: years.end)
        ])
    }
    
    func discoverFilteredSearch(filter: SearchFilter, runtimeFilter: RuntimeSearchFilter, minimumRating: Double, includeAdult: Bool) async throws -> [MediaItem] {
        if filter == .people { return [] }
        
        if filter == .movie {
            return try await discoverFilteredSearchSingleMedia(
                media: "movie",
                runtimeFilter: runtimeFilter,
                minimumRating: minimumRating,
                includeAdult: includeAdult
            )
        }
        
        if filter == .tv {
            return try await discoverFilteredSearchSingleMedia(
                media: "tv",
                runtimeFilter: runtimeFilter,
                minimumRating: minimumRating,
                includeAdult: includeAdult
            )
        }
        
        return []
    }

    // MARK: - Thematic search support

    func personIDs(for name: String) async throws -> [Int] {
        let response: TMDbPersonSearchResponse = try await fetch(path: "/search/person", query: [
            URLQueryItem(name: "query", value: name),
            URLQueryItem(name: "include_adult", value: "false")
        ])
        // Filter by popularity to avoid matching obscure people who share a name with well-known figures
        let qualified = response.results.filter { ($0.popularity ?? 0) > 5.0 }
        return Array(qualified.prefix(2).map(\.id))
    }

    func keywordIDs(for term: String) async throws -> [Int] {
        let response: TMDbKeywordsResponse = try await fetch(path: "/search/keyword", query: [
            URLQueryItem(name: "query", value: term)
        ])
        return Array((response.results ?? []).prefix(3).map(\.id))
    }

    func discoverThematic(personIDs: [Int], keywordIDs: [Int], genreIDs: Set<Int>, filter: MediaFilter, releaseYear: Int? = nil) async throws -> [MediaItem] {
        switch filter {
        case .movie:
            return try await discoverThematicSingleMedia(media: "movie", personIDs: personIDs, keywordIDs: keywordIDs, genreIDs: genreIDs, releaseYear: releaseYear)
        case .tv:
            return try await discoverThematicSingleMedia(media: "tv", personIDs: personIDs, keywordIDs: keywordIDs, genreIDs: genreIDs, releaseYear: releaseYear)
        case .both:
            async let movies = discoverThematicSingleMedia(media: "movie", personIDs: personIDs, keywordIDs: keywordIDs, genreIDs: genreIDs, releaseYear: releaseYear)
            async let series = discoverThematicSingleMedia(media: "tv", personIDs: personIDs, keywordIDs: keywordIDs, genreIDs: genreIDs, releaseYear: releaseYear)
            return try await (movies + series).uniqued()
        }
    }

    private func discoverThematicSingleMedia(media: String, personIDs: [Int], keywordIDs: [Int], genreIDs: Set<Int>, releaseYear: Int? = nil) async throws -> [MediaItem] {
        guard !personIDs.isEmpty || !keywordIDs.isEmpty || !genreIDs.isEmpty else { return [] }
        var query: [URLQueryItem] = [
            URLQueryItem(name: "sort_by", value: "vote_average.desc"),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "include_video", value: "false"),
            URLQueryItem(name: "vote_count.gte", value: media == "movie" ? "80" : "50"),
            URLQueryItem(name: "region", value: "US")
        ]
        if let year = releaseYear {
            let yearParam = media == "movie" ? "primary_release_year" : "first_air_date_year"
            query.append(URLQueryItem(name: yearParam, value: String(year)))
        }
        if !personIDs.isEmpty {
            query.append(URLQueryItem(name: "with_people", value: personIDs.prefix(8).map(String.init).joined(separator: "|")))
        }
        if !keywordIDs.isEmpty {
            query.append(URLQueryItem(name: "with_keywords", value: keywordIDs.prefix(8).map(String.init).joined(separator: "|")))
        }
        if !genreIDs.isEmpty {
            query.append(URLQueryItem(name: "with_genres", value: genreIDs.map(String.init).sorted().joined(separator: ",")))
        }
        return try await fetchListPages(path: "/discover/\(media)", query: query, pages: 2)
    }

    func discoverPickForMe(filter: MediaFilter, genreIDs: Set<Int>, runtimeRange: PickForMeRuntimeRange, minimumRating: Double, includeAdult: Bool, sortBy: String) async throws -> [MediaItem] {
        switch filter {
        case .movie:
            return try await discoverPickForMeSingleMedia(media: "movie", genreIDs: genreIDs, runtimeRange: runtimeRange, minimumRating: minimumRating, includeAdult: includeAdult, sortBy: sortBy)
        case .tv:
            return try await discoverPickForMeSingleMedia(media: "tv", genreIDs: genreIDs, runtimeRange: runtimeRange, minimumRating: minimumRating, includeAdult: includeAdult, sortBy: sortBy)
        case .both:
            async let movies = discoverPickForMeSingleMedia(media: "movie", genreIDs: genreIDs, runtimeRange: runtimeRange, minimumRating: minimumRating, includeAdult: includeAdult, sortBy: sortBy)
            async let series = discoverPickForMeSingleMedia(media: "tv", genreIDs: genreIDs, runtimeRange: runtimeRange, minimumRating: minimumRating, includeAdult: includeAdult, sortBy: sortBy)
            return try await movies + series
        }
    }

    func discoverSourceMaterial(_ sourceMaterial: PickForMeSourceMaterial, filter: MediaFilter) async throws -> [MediaItem] {
        let keywordIDs = sourceMaterial.keywordIDs
        guard !keywordIDs.isEmpty else { return [] }

        switch filter {
        case .movie:
            return try await discoverSourceMaterialSingleMedia(keywordIDs: keywordIDs, media: "movie")
        case .tv:
            return try await discoverSourceMaterialSingleMedia(keywordIDs: keywordIDs, media: "tv")
        case .both:
            async let movies = discoverSourceMaterialSingleMedia(keywordIDs: keywordIDs, media: "movie")
            async let series = discoverSourceMaterialSingleMedia(keywordIDs: keywordIDs, media: "tv")
            return try await movies + series
        }
    }

    private func discoverSourceMaterialSingleMedia(keywordIDs: [Int], media: String) async throws -> [MediaItem] {
        return try await fetchListPages(path: "/discover/\(media)", query: [
            URLQueryItem(name: "sort_by", value: "vote_average.desc"),
            URLQueryItem(name: "with_keywords", value: keywordIDs.map(String.init).joined(separator: "|")),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "include_video", value: "false"),
            URLQueryItem(name: "vote_count.gte", value: media == "movie" ? "80" : "50"),
            URLQueryItem(name: "vote_average.gte", value: "5.5"),
            URLQueryItem(name: "region", value: "US"),
            URLQueryItem(name: "watch_region", value: "US")
        ], pages: 2)
    }

    private func discoverPickForMeSingleMedia(media: String, genreIDs: Set<Int>, runtimeRange: PickForMeRuntimeRange, minimumRating: Double, includeAdult: Bool, sortBy: String) async throws -> [MediaItem] {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "sort_by", value: sortBy),
            URLQueryItem(name: "include_adult", value: includeAdult ? "true" : "false"),
            URLQueryItem(name: "include_video", value: "false"),
            URLQueryItem(name: "region", value: "US"),
            URLQueryItem(name: "watch_region", value: "US"),
            URLQueryItem(name: "vote_count.gte", value: media == "movie" ? "120" : "80")
        ]

        if !genreIDs.isEmpty {
            query.append(URLQueryItem(name: "with_genres", value: genreIDs.map(String.init).sorted().joined(separator: "|")))
        }

        if minimumRating > 0 {
            query.append(URLQueryItem(name: "vote_average.gte", value: String(format: "%.1f", minimumRating)))
        }

        if runtimeRange.minMinutes > 0 {
            query.append(URLQueryItem(name: "with_runtime.gte", value: String(runtimeRange.minMinutes)))
        }

        if runtimeRange.maxMinutes > 0 {
            query.append(URLQueryItem(name: "with_runtime.lte", value: String(runtimeRange.maxMinutes)))
        }

        return try await fetchListPages(path: "/discover/\(media)", query: query, pages: 3)
    }

    func keywordDiscoveryCandidates(for item: MediaItem, keywordIDs: [Int]) async throws -> [MediaItem] {
        let keywordIDs = Array(keywordIDs.prefix(8))
        guard !keywordIDs.isEmpty else { return [] }
        let media = item.kind == .tv ? "tv" : "movie"
        return try await fetchListPages(path: "/discover/\(media)", query: [
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "with_keywords", value: keywordIDs.map(String.init).joined(separator: "|")),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "include_video", value: "false"),
            URLQueryItem(name: "vote_count.gte", value: item.kind == .tv ? "50" : "80"),
            URLQueryItem(name: "vote_average.gte", value: "5.8"),
            URLQueryItem(name: "region", value: "US"),
            URLQueryItem(name: "watch_region", value: "US")
        ], pages: 2)
    }

    func sharedPersonCandidates(for item: MediaItem, personIDs: [Int]) async throws -> [MediaItem] {
        let personIDs = Array(personIDs.prefix(8))
        guard !personIDs.isEmpty else { return [] }
        let media = item.kind == .tv ? "tv" : "movie"
        return try await fetchListPages(path: "/discover/\(media)", query: [
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "with_people", value: personIDs.map(String.init).joined(separator: "|")),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "include_video", value: "false"),
            URLQueryItem(name: "vote_count.gte", value: item.kind == .tv ? "50" : "80"),
            URLQueryItem(name: "vote_average.gte", value: "5.8"),
            URLQueryItem(name: "region", value: "US"),
            URLQueryItem(name: "watch_region", value: "US")
        ], pages: 2)
    }
    
    private func discoverFilteredSearchSingleMedia(media: String, runtimeFilter: RuntimeSearchFilter, minimumRating: Double, includeAdult: Bool) async throws -> [MediaItem] {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "with_original_language", value: "en"),
            URLQueryItem(name: "include_adult", value: includeAdult ? "true" : "false"),
            URLQueryItem(name: "include_video", value: "false"),
            URLQueryItem(name: "region", value: "US"),
            URLQueryItem(name: "watch_region", value: "US")
        ]
        
        if minimumRating > 0 {
            query.append(URLQueryItem(name: "vote_average.gte", value: String(format: "%.1f", minimumRating)))
        }
        
        if let minimumMinutes = runtimeFilter.minimumMinutes {
            query.append(URLQueryItem(name: "with_runtime.gte", value: String(minimumMinutes)))
        }
        
        if let maximumMinutes = runtimeFilter.maximumMinutes {
            query.append(URLQueryItem(name: "with_runtime.lte", value: String(maximumMinutes)))
        }
        
        return try await fetchListPages(path: "/discover/\(media)", query: query, pages: 5)
    }
    
    private func discoverCategorySingleMedia(genreID: Int, media: String) async throws -> [MediaItem] {
        let tmdbGenreIDs = tmdbGenreIDsToQuery(for: genreID, media: media)
        guard !tmdbGenreIDs.isEmpty else { return [] }
        
        let minVoteCount = minimumVoteCount(for: genreID, media: media)
        let minVoteAverage = minimumVoteAverage(for: genreID, media: media)
        let queryGenreString = tmdbGenreIDs.map(String.init).joined(separator: ",")
        
        let query: [URLQueryItem] = [
            URLQueryItem(name: "with_genres", value: queryGenreString),
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "with_original_language", value: "en"),
            URLQueryItem(name: "vote_count.gte", value: minVoteCount),
            URLQueryItem(name: "vote_average.gte", value: minVoteAverage),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "include_video", value: "false"),
            URLQueryItem(name: "region", value: "US"),
            URLQueryItem(name: "watch_region", value: "US")
        ]
        
        return try await fetchListPages(path: "/discover/\(media)", query: query, pages: 2)
            .filter { item in
                guard item.kind == .movie || item.kind == .tv else { return false }
                return item.categoryGenreIDs.contains(genreID)
            }
    }
    
    private func tmdbGenreIDsToQuery(for genreID: Int, media: String) -> [Int] {
        guard media == "tv" else { return [genreID] }
        
        switch genreID {
        case 28:
            return [10759]
        case 878:
            return []
        case 14:
            return [10765]
        case 18:
            return [18]
        case 16:
            return [16]
        case 80:
            return [80]
        case 35:
            return [35]
        case 27:
            return []
        default:
            return [genreID]
        }
    }
    
    private func minimumVoteCount(for genreID: Int, media: String) -> String {
        if media == "tv" {
            switch genreID {
            case 16, 35, 10762, 10764, 10767:
                return "60"
            case 878, 14:
                return "120"
            default:
                return "100"
            }
        }
        
        switch genreID {
        case 16, 27, 35, 37, 99, 36, 10752, 10749, 10751:
            return "150"
        default:
            return "220"
        }
    }
    
    private func minimumVoteAverage(for genreID: Int, media: String) -> String {
        if media == "tv" {
            switch genreID {
            case 27:
                return "5.8"
            case 35, 10762, 10764, 10767:
                return "6.0"
            default:
                return "6.1"
            }
        }
        
        switch genreID {
        case 27:
            return "5.7"
        case 35, 37, 99, 36, 10752, 10749, 10751:
            return "5.9"
        default:
            return "6.0"
        }
    }
    
    func recommendations(for key: MediaKey) async throws -> [MediaItem] {
        try await fetchList(path: "/\(key.kind.tmdbPath)/\(key.id)/recommendations", query: [])
            .filter { $0.shouldShowInDiscovery && !$0.isUpcoming }
    }
    
    func sameSeriesOrSimilar(for key: MediaKey) async throws -> [MediaItem] {
        try await fetchList(path: "/\(key.kind.tmdbPath)/\(key.id)/similar", query: [])
            .filter { $0.shouldShowInDiscovery && !$0.isUpcoming }
    }
    
    func detail(for item: MediaItem, regionCode: String = "US") async throws -> MediaDetail {
        let response: TMDbDetailResponse = try await fetch(path: "/\(item.kind.tmdbPath)/\(item.id)", query: [URLQueryItem(
            name: "append_to_response",
            value: item.kind == .movie
            ? "credits,similar,recommendations,keywords,watch/providers,release_dates,videos,external_ids"
            : "credits,similar,recommendations,keywords,watch/providers,content_ratings,videos,external_ids,networks"
        )])

        guard item.kind == .tv else {
            return MediaDetail(response: response, fallback: item, regionCode: regionCode)
        }

        let seasonsWithEpisodes = try await hydratedSeasons(for: item, baseSeasons: response.seasons ?? [])
        let hydratedResponse = response.replacingSeasons(seasonsWithEpisodes)
        return MediaDetail(response: hydratedResponse, fallback: item, regionCode: regionCode)
    }
    
    private func hydratedSeasons(for item: MediaItem, baseSeasons: [SeasonDTO]) async throws -> [SeasonDTO] {
        var hydratedSeasons: [SeasonDTO] = []
        
        for season in baseSeasons {
            guard let seasonNumber = season.seasonNumber, seasonNumber > 0 else {
                hydratedSeasons.append(season)
                continue
            }
            
            do {
                let hydratedSeason: SeasonDTO = try await fetch(path: "/tv/\(item.id)/season/\(seasonNumber)", query: [])
                hydratedSeasons.append(season.mergingEpisodes(from: hydratedSeason))
            } catch {
                hydratedSeasons.append(season)
            }
        }
        
        return hydratedSeasons
    }
    
    func personCredits(personID: Int) async throws -> [MediaItem] {
        let response: TMDbPersonCreditsResponse = try await fetch(path: "/person/\(personID)/combined_credits", query: [])
        let combinedCredits: [TMDbMediaDTO] = response.cast + response.crew
        let mappedItems: [MediaItem] = combinedCredits.map { dto in
            MediaItem(dto)
        }
        let filteredItems: [MediaItem] = mappedItems.filter { item in
            item.shouldShowInPersonCredits
        }
        let uniqueItems: [MediaItem] = filteredItems.uniqued()
        let sortedItems: [MediaItem] = uniqueItems.sorted { lhs, rhs in
            if lhs.voteAverage != rhs.voteAverage {
                return lhs.voteAverage > rhs.voteAverage
            }
            let lhsDate = lhs.releaseDateValue ?? .distantPast
            let rhsDate = rhs.releaseDateValue ?? .distantPast
            return lhsDate > rhsDate
        }
        return sortedItems
    }
    
    func personDetail(personID: Int) async throws -> PersonDetail {
        let response: TMDbPersonDetailResponse = try await fetch(path: "/person/\(personID)", query: [])
        return PersonDetail(response: response)
    }

    func item(for key: MediaKey) async throws -> MediaItem {
        let response: TMDbStandaloneMediaDTO = try await fetch(path: "/\(key.kind.tmdbPath)/\(key.id)", query: [])
        return MediaItem(
            id: response.id,
            kind: key.kind,
            title: response.title ?? response.name ?? "",
            overview: response.overview ?? "",
            posterPath: response.posterPath,
            backdropPath: response.backdropPath,
            releaseDate: response.releaseDate ?? response.firstAirDate,
            voteAverage: response.voteAverage ?? 0,
            voteCount: response.voteCount,
            genreIDs: response.genres?.map(\.id) ?? [],
            creditRole: nil,
            runtime: response.runtime,
            originalLanguage: response.originalLanguage
        )
    }

    func items(for keys: [MediaKey]) async throws -> [MediaItem] {
        let validKeys = keys.filter { $0.kind == .movie || $0.kind == .tv }.prefix(40)
        return try await withThrowingTaskGroup(of: MediaItem?.self) { group in
            for key in validKeys {
                group.addTask { try? await self.item(for: key) }
            }
            var results: [MediaItem] = []
            for try await item in group {
                if let item { results.append(item) }
            }
            return results.uniqued()
        }
    }
    
    
    // MARK: - Lightweight fetches for background notifications

    func seasonCount(forTVShowID id: Int) async throws -> Int {
        struct LightResponse: Decodable {
            let numberOfSeasons: Int?
            enum CodingKeys: String, CodingKey { case numberOfSeasons = "number_of_seasons" }
        }
        let response: LightResponse = try await fetch(path: "/tv/\(id)", query: [])
        return response.numberOfSeasons ?? 0
    }

    func trailerCount(for item: MediaItem) async throws -> Int {
        struct LightResponse: Decodable {
            struct VideosResponse: Decodable {
                let results: [VideoResult]
                struct VideoResult: Decodable { let type: String; let site: String }
            }
            let videos: VideosResponse?
            enum CodingKeys: String, CodingKey { case videos }
        }
        let response: LightResponse = try await fetch(
            path: "/\(item.kind.tmdbPath)/\(item.id)",
            query: [URLQueryItem(name: "append_to_response", value: "videos")]
        )
        return response.videos?.results.filter { $0.type == "Trailer" && $0.site == "YouTube" }.count ?? 0
    }

    private func fetchList(path: String, query: [URLQueryItem]) async throws -> [MediaItem] {
        let response: TMDbListResponse = try await fetch(path: path, query: query)
        return response.results.map(MediaItem.init).filter { !$0.title.isEmpty }
    }
    
    private func fetchListPages(path: String, query: [URLQueryItem], pages: Int) async throws -> [MediaItem] {
        var collected: [MediaItem] = []
        for page in 1...max(pages, 1) {
            let pageItems: [MediaItem] = try await fetchList(path: path, query: query, page: page)
            collected += pageItems
            if pageItems.isEmpty { break }
        }
        return collected.uniqued()
    }
    
    private func fetchList(path: String, query: [URLQueryItem], page: Int) async throws -> [MediaItem] {
        let response: TMDbListResponse = try await fetch(path: path, query: query, page: page)
        return response.results.map(MediaItem.init).filter { !$0.title.isEmpty }
    }
    
    private func fetch<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        try await fetch(path: path, query: query, page: 1)
    }
    
    private func fetch<T: Decodable>(path: String, query: [URLQueryItem], page: Int) async throws -> T {
        var comps = URLComponents(string: base + "/tmdb-proxy")!
        comps.queryItems = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "page", value: String(page))
        ] + query
        guard let url = comps.url else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
