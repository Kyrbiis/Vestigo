import Foundation

/* TasteDiveService is disabled
struct TasteDiveService {
    func similarTitles(for title: String, kind: MediaKind) async throws -> [String] { [] }
}
*/

struct RelatedMediaService {
    private let endpoint = URL(string: "https://query.wikidata.org/sparql")!

    func sections(imdbID: String) async throws -> [RelatedMediaSection] {
        let cleanedID = imdbID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedID.hasPrefix("tt") else { return [] }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "query", value: sparqlQuery(imdbID: cleanedID)),
            URLQueryItem(name: "format", value: "json")
        ]

        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(WikidataSPARQLResponse.self, from: data)
        let items = decoded.results.bindings.compactMap(RelatedMediaItem.init(binding:))
        return RelatedMediaSection.sections(from: items)
    }

    func franchiseMembers(imdbID: String) async throws -> [WikidataFranchiseMember] {
        let cleanedID = imdbID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedID.hasPrefix("tt") else { return [] }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "query", value: franchiseQuery(imdbID: cleanedID)),
            URLQueryItem(name: "format", value: "json")
        ]

        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return []
        }

        let decoded = try JSONDecoder().decode(WikidataFranchiseSPARQLResponse.self, from: data)
        return decoded.results.bindings.compactMap(WikidataFranchiseMember.init(binding:))
    }

    private func sparqlQuery(imdbID: String) -> String {
        """
        SELECT ?relation ?item ?itemLabel ?itemDescription ?image ?article WHERE {
          ?work wdt:P345 "\(imdbID)" .
          ?work wdt:P144 ?item .
          BIND("original" AS ?relation)
          OPTIONAL { ?item wdt:P18 ?image . }
          OPTIONAL {
            ?article schema:about ?item ;
                     schema:isPartOf <https://en.wikipedia.org/> .
          }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        }
        LIMIT 30
        """
    }

    private func franchiseQuery(imdbID: String) -> String {
        """
        SELECT DISTINCT ?tmdbID ?kind WHERE {
          ?work wdt:P345 "\(imdbID)" .
          {
            ?work wdt:P179 ?series .
            ?item wdt:P179 ?series .
          } UNION {
            ?work wdt:P361 ?parent .
            ?item wdt:P361 ?parent .
          } UNION {
            ?work wdt:P1080 ?universe .
            ?item wdt:P1080 ?universe .
          }
          FILTER(?item != ?work)
          {
            ?item wdt:P4985 ?tmdbID .
            BIND("tv" AS ?kind)
          } UNION {
            ?item wdt:P4947 ?tmdbID .
            BIND("movie" AS ?kind)
          }
        }
        LIMIT 50
        """
    }
}

struct WikidataFranchiseSPARQLResponse: Decodable {
    let results: WikidataFranchiseSPARQLResults
}

struct WikidataFranchiseSPARQLResults: Decodable {
    let bindings: [WikidataFranchiseBinding]
}

struct WikidataFranchiseBinding: Decodable {
    let tmdbID: WikidataSPARQLValue
    let kind: WikidataSPARQLValue
}

struct WikidataFranchiseMember: Hashable {
    let tmdbID: Int
    let kind: MediaKind

    init?(binding: WikidataFranchiseBinding) {
        guard let id = Int(binding.tmdbID.value) else { return nil }
        switch binding.kind.value {
        case "tv": kind = .tv
        case "movie": kind = .movie
        default: return nil
        }
        tmdbID = id
    }

    var mediaKey: MediaKey { MediaKey(id: tmdbID, kind: kind) }
}

struct WikidataSPARQLResponse: Decodable {
    let results: WikidataSPARQLResults
}

struct WikidataSPARQLResults: Decodable {
    let bindings: [WikidataRelatedMediaBinding]
}

struct WikidataRelatedMediaBinding: Decodable {
    let relation: WikidataSPARQLValue
    let item: WikidataSPARQLValue
    let itemLabel: WikidataSPARQLValue
    let itemDescription: WikidataSPARQLValue?
    let image: WikidataSPARQLValue?
    let article: WikidataSPARQLValue?
}

struct WikidataSPARQLValue: Decodable {
    let value: String
}
