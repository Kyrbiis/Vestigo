import Foundation

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
