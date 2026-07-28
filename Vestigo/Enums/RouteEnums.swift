import SwiftUI

// MARK: - Section Routes

enum SectionRoute: String, Hashable {
    case trending, popular, newReleases, upcoming, settings

    var title: String {
        switch self {
        case .trending: return "Trending now"
        case .popular: return "Popular"
        case .newReleases: return "New releases"
        case .upcoming: return "Upcoming releases"
        case .settings: return "Settings"
        }
    }
}

struct GenreRoute: Hashable { let genre: GenreDefinition }

enum SearchRoute: Hashable {
    case genre(GenreRoute)
    case chart(MediaKind)
}

struct GenreDefinition: Identifiable, Hashable {
    var id: Int { tmdbID }
    let name: String
    let tmdbID: Int
    let iconicFilm: String
    let imageURL: String
    var mediaScope: MediaFilter = .both

    var imageURLValue: URL? {
        URL(string: imageURL)
    }

    static let all: [GenreDefinition] = [
        GenreDefinition(name: "Action", tmdbID: 28, iconicFilm: "Die Hard", imageURL: "https://image.tmdb.org/t/p/w780/4HWAQu28e2yaWrtupFPGFkdNU7V.jpg"),
        GenreDefinition(name: "Adventure", tmdbID: 12, iconicFilm: "Indiana Jones", imageURL: "https://image.tmdb.org/t/p/w780/ceG9VzoRAVGwivFU403Wc3AHRys.jpg"),
        GenreDefinition(name: "Sci-Fi", tmdbID: 878, iconicFilm: "Blade Runner 2049", imageURL: "https://image.tmdb.org/t/p/w780/8rpDcsfLJypbO6vREc0547VKqEv.jpg"),
        GenreDefinition(name: "Fantasy", tmdbID: 14, iconicFilm: "The Lord of the Rings", imageURL: "https://image.tmdb.org/t/p/w780/6oom5QYQ2yQTMJIbnvbkBL9cHo6.jpg"),
        GenreDefinition(name: "Drama", tmdbID: 18, iconicFilm: "The Godfather", imageURL: "https://image.tmdb.org/t/p/w780/3bhkrj58Vtu7enYsRolD1fZdja1.jpg"),
        GenreDefinition(name: "Horror", tmdbID: 27, iconicFilm: "Alien", imageURL: "https://image.tmdb.org/t/p/w500/vfrQk5IPloGg1v9Rzbh2Eg3VGyM.jpg"),
        GenreDefinition(name: "Animation", tmdbID: 16, iconicFilm: "Spirited Away", imageURL: "https://image.tmdb.org/t/p/w780/39wmItIWsg5sZMyRUHLkWBcuVCM.jpg"),
        GenreDefinition(name: "Crime", tmdbID: 80, iconicFilm: "Pulp Fiction", imageURL: "https://image.tmdb.org/t/p/w500/d5iIlFn5s0ImszYzBPb8JPIfbXD.jpg"),
        GenreDefinition(name: "Comedy", tmdbID: 35, iconicFilm: "Airplane!", imageURL: "https://image.tmdb.org/t/p/w780/hiURvJjCgk0s10urHVCg80TFF11.jpg"),
        GenreDefinition(name: "Mystery", tmdbID: 9648, iconicFilm: "Knives Out", imageURL: "https://image.tmdb.org/t/p/w780/pThyQovXQrw2m0s9x82twj48Jq4.jpg"),
        GenreDefinition(name: "Thriller", tmdbID: 53, iconicFilm: "Gone Girl", imageURL: "https://image.tmdb.org/t/p/w780/qymaJhucquUwjpb8oiqynMeXnID.jpg"),
        GenreDefinition(name: "Romance", tmdbID: 10749, iconicFilm: "Before Sunrise", imageURL: "https://image.tmdb.org/t/p/w780/kf1Jb1c2JAOqjuzA3H4oDM263uB.jpg", mediaScope: .movie),
        GenreDefinition(name: "Family", tmdbID: 10751, iconicFilm: "Paddington", imageURL: "https://image.tmdb.org/t/p/w780/2M2JxEv3HSpjnZWjY9NOdGgfUd.jpg", mediaScope: .movie),
        GenreDefinition(name: "Documentary", tmdbID: 99, iconicFilm: "Free Solo", imageURL: "https://image.tmdb.org/t/p/w780/oQHF0Y4gCw6VdPmapjsbZoxY2ht.jpg"),
        GenreDefinition(name: "History", tmdbID: 36, iconicFilm: "Oppenheimer", imageURL: "https://image.tmdb.org/t/p/w780/8Gxv8gSFCU0XGDykEGv7zR1n2ua.jpg", mediaScope: .movie),
        GenreDefinition(name: "Based on a True Story", tmdbID: 30001, iconicFilm: "The Social Network", imageURL: "https://image.tmdb.org/t/p/w780/n0ybibhJtQ5icDqTp8eRytcIHJx.jpg"),
        GenreDefinition(name: "Based on a Book", tmdbID: 30002, iconicFilm: "The Lord of the Rings", imageURL: "https://image.tmdb.org/t/p/w780/6oom5QYQ2yQTMJIbnvbkBL9cHo6.jpg"),
        GenreDefinition(name: "Based on a Game", tmdbID: 30003, iconicFilm: "The Last of Us", imageURL: "https://image.tmdb.org/t/p/w780/uKvVjHNqB5VmOrdxqAt2F7J78ED.jpg"),
        GenreDefinition(name: "War", tmdbID: 10752, iconicFilm: "1917", imageURL: "https://image.tmdb.org/t/p/w780/iZf0KyrE25z1sage4SYFLCCrMi9.jpg", mediaScope: .movie),
        GenreDefinition(name: "Western", tmdbID: 37, iconicFilm: "Unforgiven", imageURL: "https://image.tmdb.org/t/p/w780/yKyLJmRAtyXEEYKOvPhKHXIcPq9.jpg"),
        GenreDefinition(name: "Reality", tmdbID: 10764, iconicFilm: "The Traitors", imageURL: "https://image.tmdb.org/t/p/w780/7lD7Q3dP6tQheQw3JIgYfR3MN6Y.jpg", mediaScope: .tv),
        GenreDefinition(name: "Talk", tmdbID: 10767, iconicFilm: "Hot Ones", imageURL: "https://image.tmdb.org/t/p/w780/2n95p9isIi1LYTscTcGytlI4zYd.jpg", mediaScope: .tv),
        GenreDefinition(name: "80s", tmdbID: 1980, iconicFilm: "Back to the Future", imageURL: "https://image.tmdb.org/t/p/w780/fNOH9f1aA7XRTzl1sAOx9iF553Q.jpg"),
        GenreDefinition(name: "90s", tmdbID: 1990, iconicFilm: "Jurassic Park", imageURL: "https://image.tmdb.org/t/p/w780/9i3plLl89DHMz7mahksDaAo7HIS.jpg"),
        GenreDefinition(name: "00s", tmdbID: 2000, iconicFilm: "The Dark Knight", imageURL: "https://image.tmdb.org/t/p/w780/qJ2tW6WMUDux911r6m7haRef0WH.jpg"),
        GenreDefinition(name: "10s", tmdbID: 2010, iconicFilm: "Interstellar", imageURL: "https://image.tmdb.org/t/p/w780/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg")
    ]

    var gradient: LinearGradient { Self.gradient(for: tmdbID) }
    static func gradient(for id: Int?) -> LinearGradient {
        switch id {
        case 1980: return LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        case 1990: return LinearGradient(colors: [.green, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        case 2000: return LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        case 2010: return LinearGradient(colors: [.indigo, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
        case 28: return LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        case 878: return LinearGradient(colors: [.cyan, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
        case 14: return LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        case 27: return LinearGradient(colors: [.black, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
        default: return LinearGradient(colors: [.gray, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - ForYou Navigation

enum ForYouRoute: Hashable {
    case section(ForYouSection)
    case pickForMe
}

// MARK: - Carousel Enums

enum HomeCarousel: String, Codable, CaseIterable, Identifiable, Hashable {
    case trending, newReleases, upcoming
    var id: String { rawValue }
    var title: String {
        switch self {
        case .trending: return "Trending now"
        case .newReleases: return "New releases"
        case .upcoming: return "Upcoming releases"
        }
    }
}

enum ForYouCarousel: String, Codable, CaseIterable, Identifiable, Hashable {
    case forYou, moreLikeLast, moreLikeFavourite, watchlistPicks, seriesNext
    var id: String { rawValue }
    var title: String {
        switch self {
        case .forYou: return "For you"
        case .moreLikeLast: return "More like recent watched"
        case .moreLikeFavourite: return "More like a favourite"
        case .watchlistPicks: return "From your watchlist"
        case .seriesNext: return "Continue with related series"
        }
    }
}
