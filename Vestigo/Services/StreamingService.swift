import Foundation

struct StreamingAvailabilityService {
    private let base = "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api"
    
    func providers(for item: MediaItem, regionCode: String = "US") async throws -> [StreamingOption] {
        var comps = URLComponents(string: base + "/watchmode-sources")!
        comps.queryItems = [
            URLQueryItem(name: "tmdbID", value: String(item.id)),
            URLQueryItem(name: "kind", value: item.kind == .tv ? "tv" : "movie"),
            URLQueryItem(name: "country", value: regionCode)
        ]
        
        guard let url = comps.url else { throw URLError(.badURL) }
        let response: WatchmodeSourcesResponse = try await fetch(url: url)
        return response.sources
    }
    
    private func fetch<T: Decodable>(url: URL) async throws -> T {
        let request = URLRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

struct WatchmodeSourcesResponse: Decodable {
    let ok: Bool
    let source: String?
    let tmdbID: Int?
    let kind: String?
    let country: String?
    let count: Int?
    let sources: [StreamingOption]
}
