import Foundation

enum SoundtrackPlatform: String, CaseIterable, Identifiable {
    case appleMusic
    case deezer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .deezer: return "Deezer"
        }
    }

    var shortTitle: String {
        switch self {
        case .appleMusic: return "AM"
        case .deezer: return "DZ"
        }
    }

    var logoURL: URL? {
        let domain: String
        switch self {
        case .appleMusic: domain = "music.apple.com"
        case .deezer: domain = "deezer.com"
        }
        var components = URLComponents(string: "https://www.google.com/s2/favicons")
        components?.queryItems = [
            URLQueryItem(name: "sz", value: "128"),
            URLQueryItem(name: "domain", value: domain)
        ]
        return components?.url
    }

    func searchURL(for query: String) -> URL? {
        switch self {
        case .appleMusic:
            var components = URLComponents(string: "https://music.apple.com/us/search")
            components?.queryItems = [URLQueryItem(name: "term", value: query)]
            return components?.url
        case .deezer:
            let encodedPath = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
            return URL(string: "https://www.deezer.com/search/\(encodedPath)")
        }
    }
}

struct SoundtrackAvailabilityService {
    static func availablePlatforms(for query: String) async -> [SoundtrackPlatform] {
        await withTaskGroup(of: SoundtrackPlatform?.self) { group in
            group.addTask {
                await hasAppleMusicAlbum(for: query) ? .appleMusic : nil
            }
            group.addTask {
                await hasDeezerAlbum(for: query) ? .deezer : nil
            }

            var platforms: [SoundtrackPlatform] = []
            for await platform in group {
                if let platform {
                    platforms.append(platform)
                }
            }

            let order = Dictionary(uniqueKeysWithValues: SoundtrackPlatform.allCases.enumerated().map { ($0.element, $0.offset) })
            return platforms.sorted { (order[$0] ?? 0) < (order[$1] ?? 0) }
        }
    }

    private static func hasAppleMusicAlbum(for query: String) async -> Bool {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "limit", value: "6")
        ]
        guard let url = components?.url else { return false }

        do {
            let response: AppleMusicSearchResponse = try await fetch(url)
            return response.results.contains { result in
                result.collectionName.normalizedSoundtrackSearchText.containsSoundtrackSignal
            }
        } catch {
            return false
        }
    }

    private static func hasDeezerAlbum(for query: String) async -> Bool {
        var components = URLComponents(string: "https://api.deezer.com/search/album")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "6")
        ]
        guard let url = components?.url else { return false }

        do {
            let response: DeezerAlbumSearchResponse = try await fetch(url)
            return response.data.contains { album in
                album.title.normalizedSoundtrackSearchText.containsSoundtrackSignal
            }
        } catch {
            return false
        }
    }

    private static func fetch<Response: Decodable>(_ url: URL) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

struct AppleMusicSearchResponse: Decodable {
    let results: [AppleMusicAlbumResult]
}

struct AppleMusicAlbumResult: Decodable {
    let collectionName: String
}

struct DeezerAlbumSearchResponse: Decodable {
    let data: [DeezerAlbumResult]
}

struct DeezerAlbumResult: Decodable {
    let title: String
}

extension String {
    var normalizedSoundtrackSearchText: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    var containsSoundtrackSignal: Bool {
        contains("soundtrack") || contains("original motion picture") || contains("original series")
    }
}


