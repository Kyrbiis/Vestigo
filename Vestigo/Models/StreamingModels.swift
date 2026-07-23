import Foundation

struct WatchmodeOption: Decodable {
    let service: WatchmodeService?
    let addon: WatchmodeService?
    let type: String?
    let quality: String?
    let price: WatchmodePrice?
    let raw: WatchmodeJSONValue?
    let link: String?
    let openURL: String?
    let webURL: String?
    let iosURL: String?
    let androidURL: String?
    let appURL: String?

    enum CodingKeys: String, CodingKey {
        case service
        case addon
        case addOn
        case type
        case quality
        case price
        case amount
        case value
        case cost
        case retailPrice
        case rentalPrice
        case purchasePrice
        case rentPrice
        case buyPrice
        case currency
        case currencyCode
        case formattedPrice
        case priceFormatted
        case displayPrice
        case priceText
        case prices
        case pricing
        case offers
        case offer
        case links
        case link
        // openURL fields for openURL selection
        case openURL
        case openUrl
        case open_url
        // URL fields for openURL selection
        case url
        case webURL
        case webUrl
        case web_url
        case iosURL
        case iosUrl
        case ios_url
        case androidURL
        case androidUrl
        case android_url
        case appURL
        case appUrl
        case app_url
        case deepLink
        case deeplink
        case deep_link
    }

    init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        service = try keyed.decodeIfPresent(WatchmodeService.self, forKey: .service)
        addon = try keyed.decodeIfPresent(WatchmodeService.self, forKey: .addon) ?? keyed.decodeIfPresent(WatchmodeService.self, forKey: .addOn)
        type = try keyed.decodeIfPresent(String.self, forKey: .type)
        quality = try keyed.decodeIfPresent(String.self, forKey: .quality)
        raw = try? WatchmodeJSONValue(from: decoder)
        let decodedLink = try keyed.decodeIfPresent(String.self, forKey: .link)
        let decodedLinks = try keyed.decodeIfPresent(String.self, forKey: .links)
        let decodedURL = try keyed.decodeIfPresent(String.self, forKey: .url)
        let decodedDeepLink = try keyed.decodeIfPresent(String.self, forKey: .deepLink)
        let decodedDeeplink = try keyed.decodeIfPresent(String.self, forKey: .deeplink)
        let decodedDeepLinkSnake = try keyed.decodeIfPresent(String.self, forKey: .deep_link)
        link = decodedLink ?? decodedLinks ?? decodedURL ?? decodedDeepLink ?? decodedDeeplink ?? decodedDeepLinkSnake

        // openURL decoding (normalized field from backend)
        let decodedOpenURL = try keyed.decodeIfPresent(String.self, forKey: .openURL)
        let decodedOpenUrl = try keyed.decodeIfPresent(String.self, forKey: .openUrl)
        let decodedOpenURLSnake = try keyed.decodeIfPresent(String.self, forKey: .open_url)
        openURL = decodedOpenURL ?? decodedOpenUrl ?? decodedOpenURLSnake

        let decodedWebURL = try keyed.decodeIfPresent(String.self, forKey: .webURL)
        let decodedWebUrl = try keyed.decodeIfPresent(String.self, forKey: .webUrl)
        let decodedWebURLSnake = try keyed.decodeIfPresent(String.self, forKey: .web_url)
        webURL = decodedWebURL ?? decodedWebUrl ?? decodedWebURLSnake

        let decodedIOSURL = try keyed.decodeIfPresent(String.self, forKey: .iosURL)
        let decodedIOSUrl = try keyed.decodeIfPresent(String.self, forKey: .iosUrl)
        let decodedIOSURLSnake = try keyed.decodeIfPresent(String.self, forKey: .ios_url)
        iosURL = decodedIOSURL ?? decodedIOSUrl ?? decodedIOSURLSnake

        let decodedAndroidURL = try keyed.decodeIfPresent(String.self, forKey: .androidURL)
        let decodedAndroidUrl = try keyed.decodeIfPresent(String.self, forKey: .androidUrl)
        let decodedAndroidURLSnake = try keyed.decodeIfPresent(String.self, forKey: .android_url)
        androidURL = decodedAndroidURL ?? decodedAndroidUrl ?? decodedAndroidURLSnake

        let decodedAppURL = try keyed.decodeIfPresent(String.self, forKey: .appURL)
        let decodedAppUrl = try keyed.decodeIfPresent(String.self, forKey: .appUrl)
        let decodedAppURLSnake = try keyed.decodeIfPresent(String.self, forKey: .app_url)
        appURL = decodedAppURL ?? decodedAppUrl ?? decodedAppURLSnake

        var resolvedPrice: WatchmodePrice?

        if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .price) }
        if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .amount) }
        if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .value) }
        if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .cost) }
        if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .retailPrice) }
        if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .rentalPrice) }
        if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .purchasePrice) }
        if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .rentPrice) }
        if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .buyPrice) }
        if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .formattedPrice) }
        if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .priceFormatted) }
        if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .displayPrice) }
        if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .priceText) }
        if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .prices) }
        if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .pricing) }
        if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .offer) }
        if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .offers) }
        if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .link) }
        if resolvedPrice == nil { resolvedPrice = try keyed.decodeIfPresent(WatchmodePrice.self, forKey: .links) }

        if resolvedPrice?.displayText == nil {
            if let scannedText = raw?.firstPriceText() {
                resolvedPrice = WatchmodePrice(displayText: scannedText)
            }
        }

        price = resolvedPrice
    }

    var displayOpenURL: String? {
        let candidates = [openURL, iosURL, appURL, webURL, link, androidURL]
        return candidates
            .compactMap { value in
                value?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .first { value in
                guard !value.isEmpty else { return false }
                let lower = value.lowercased()
                guard lower != "ios:" else { return false }
                guard lower != "ios://" else { return false }
                guard !lower.contains("{ios") else { return false }
                guard !lower.contains("placeholder") else { return false }
                return URL(string: value) != nil
            }
    }

    var displayServiceName: String {
        addon?.name ?? service?.name ?? "Unknown"
    }

    var displayTypeText: String {
        let normalizedType = (type ?? "unknown").lowercased()
        switch normalizedType {
        case "rent", "rental":
            return "rent"
        case "buy", "purchase", "purchase4k", "buy4k":
            return "buy"
        case "free":
            return "free"
        case "subscription", "flatrate", "stream":
            return "subscription"
        case "addon", "add-on", "add_on":
            return "addon"
        default:
            return type ?? "unknown"
        }
    }

    var displayPriceText: String {
        if let displayText = price?.displayText, !displayText.isEmpty {
            return displayText
        }

        if let linkPrice = link?.priceTextFromURL(), !linkPrice.isEmpty {
            return linkPrice
        }

        let normalizedType = (type ?? "").lowercased()
        switch normalizedType {
        case "free":
            return "Free"
        case "subscription", "flatrate", "stream", "addon", "add-on", "add_on":
            return "Included"
        default:
            return ""
        }
    }

    var displayQualityText: String {
        guard let quality, !quality.isEmpty else { return "" }
        return quality.uppercased()
    }
}

struct WatchmodeService: Decodable {
    let name: String?
}

struct WatchmodePrice: Decodable {
    let displayText: String?

    init(displayText: String?) {
        self.displayText = displayText
    }

    init(from decoder: Decoder) throws {
        let raw = try? WatchmodeJSONValue(from: decoder)
        displayText = raw?.firstPriceText()
    }
}

struct SeasonInfo: Identifiable, Hashable {
    let number: Int
    let name: String
    let airDate: String?
    let episodeCount: Int
    let episodes: [EpisodeInfo]

    var id: Int { number }

    var releaseYearText: String? {
        guard let airDate,
              let date = DateParser.parse(airDate) else {
            return nil
        }

        return String(Calendar.current.component(.year, from: date))
    }

    var totalRuntime: Int? {
        let runtimes = episodes.compactMap(\.runtime)
        guard !runtimes.isEmpty else { return nil }
        return runtimes.reduce(0, +)
    }

    var episodeCountAndRuntimeText: String {
        var parts: [String] = ["\(episodeCount) episode\(episodeCount == 1 ? "" : "s")"]

        if let releaseYearText {
            parts.append(releaseYearText)
        }

        if let totalRuntime, totalRuntime > 0 {
            parts.append(Self.formatRuntime(totalRuntime))
        }

        return parts.joined(separator: " • ")
    }

    private static func formatRuntime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60

        if hours > 0, mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }

    static let placeholder: [SeasonInfo] = []
}

struct EpisodeInfo: Identifiable, Hashable {
    let number: Int
    let title: String
    let airDate: String?
    let runtime: Int?
    let stillPath: String?

    var id: Int { number }

    var releaseDateText: String? {
        DateParser.parse(airDate)?.formatted(.dateTime.month(.abbreviated).day().year())
    }

    var stillURL: URL? {
        guard let stillPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w300\(stillPath)")
    }
}

struct StreamingOption: Codable, Hashable, Identifiable {
    var id: String {
        "\(serviceName)-\(type)-\(priceText)-\(qualityText)-\(openURL ?? "")"
    }

    var serviceShort: String {
        let cleaned = serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "?" }

        let initials = cleaned
            .split { !$0.isLetter && !$0.isNumber }
            .compactMap { $0.first }
            .prefix(2)
            .map { String($0).uppercased() }
            .joined()

        if !initials.isEmpty {
            return initials
        }

        return String(cleaned.prefix(2)).uppercased()
    }

    var availabilityText: String {
        switch type.lowercased() {
        case "subscription", "sub":
            return "Subscription"
        case "free":
            return "Free"
        case "rent", "rental":
            return "Rent"
        case "buy", "purchase":
            return "Buy"
        case "addon", "add-on", "add_on":
            return "Add-on"
        default:
            return type.isEmpty ? "Available" : type.capitalized
        }
    }

    let serviceName: String
    let type: String
    let priceText: String
    let qualityText: String
    let openURL: String?

    init(
        serviceName: String,
        type: String,
        priceText: String,
        qualityText: String,
        openURL: String? = nil
    ) {
        self.serviceName = serviceName
        self.type = type
        self.priceText = priceText
        self.qualityText = qualityText
        self.openURL = openURL
    }
}
