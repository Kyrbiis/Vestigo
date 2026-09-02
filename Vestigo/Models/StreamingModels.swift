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

    var isUpcoming: Bool {
        guard let date = DateParser.parse(airDate) else { return false }
        return date > .now
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

struct KnownStreamingService: Identifiable, Hashable {
    let id: String          // used for matching against StreamingOption.serviceName
    let displayName: String
    let isFree: Bool
    let iconLabel: String   // short text shown inside the icon tile
    let brandColorHex: String
    let lightText: Bool     // false = use dark text (for bright brand colors)
    let domain: String      // used to build the Brandfetch logo CDN URL
    let aliases: [String]   // alternative API names (e.g. "Amazon" for "Prime Video")
    let tmdbProviderID: Int?

    var logoURL: URL? {
        URL(string: "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api/brand-logo?domain=\(domain)&w=128&h=128")
    }

    func matches(_ serviceName: String) -> Bool {
        let b = serviceName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let a = id.lowercased()
        if b.contains(a) || a.contains(b) { return true }
        return aliases.contains { alias in
            let c = alias.lowercased()
            return b.contains(c) || c.contains(b)
        }
    }

    private static func s(
        _ id: String, _ display: String, _ icon: String, _ hex: String, _ domain: String,
        free: Bool = false, dark: Bool = false, aliases: [String] = [], tmdbID: Int? = nil
    ) -> KnownStreamingService {
        KnownStreamingService(id: id, displayName: display, isFree: free, iconLabel: icon,
                              brandColorHex: hex, lightText: !dark, domain: domain, aliases: aliases,
                              tmdbProviderID: tmdbID)
    }

    static let catalog: [KnownStreamingService] = [
        // Subscription
        s("Netflix",              "Netflix",          "N",      "#E50914",  "netflix.com",                                                                    tmdbID: 8),
        s("Prime Video",          "Prime Video",      "prime",  "#00A8E1",  "primevideo.com",     aliases: ["Amazon", "Amazon Prime", "Amazon Prime Video"],   tmdbID: 9),
        s("Apple TV+",            "Apple TV+",        "TV+",    "#1C1C1E",  "tv.apple.com",       aliases: ["Apple TV", "AppleTV"],                            tmdbID: 350),
        s("Disney+",              "Disney+",          "D+",     "#113ECF",  "disneyplus.com",                                                                  tmdbID: 337),
        s("Hulu",                 "Hulu",             "hulu",   "#1CE783",  "hulu.com",           dark: true,                                                  tmdbID: 15),
        s("Max",                  "Max",              "max",    "#002BE7",  "max.com",            aliases: ["HBO Max"],                                         tmdbID: 1899),
        s("Peacock",              "Peacock",          "P",      "#1D1D1B",  "peacocktv.com",                                                                   tmdbID: 387),
        s("Paramount+",           "Paramount+",       "P+",     "#0064FF",  "paramountplus.com",  aliases: ["Paramount Plus"],                                 tmdbID: 531),
        s("YouTube TV",           "YouTube TV",       "YT",     "#FF0000",  "tv.youtube.com",                                                                  tmdbID: 227),
        s("Fubo",                 "Fubo",             "fubo",   "#E8173B",  "fubo.tv",            aliases: ["FuboTV"],                                          tmdbID: 257),
        s("Sling TV",             "Sling TV",         "SLING",  "#1B6BFF",  "sling.com",                                                                       tmdbID: 190),
        s("DirecTV Stream",       "DirecTV",          "DTV",    "#00A8E0",  "directv.com",        aliases: ["DirecTV"]),
        s("Starz",                "Starz",            "STARZ",  "#141414",  "starz.com",                                                                       tmdbID: 43),
        s("Epix",                 "MGM+",             "MGM+",   "#1A1A1A",  "mgmplus.com",        aliases: ["MGM Plus", "MGM+"],                               tmdbID: 268),
        s("Crunchyroll",          "Crunchyroll",      "CR",     "#F47521",  "crunchyroll.com",                                                                 tmdbID: 283),
        s("Funimation",           "Funimation",       "FUN",    "#410099",  "funimation.com",                                                                  tmdbID: 269),
        s("Discovery+",           "Discovery+",       "D+",     "#0D4296",  "discoveryplus.com",  aliases: ["Discovery Plus"],                                 tmdbID: 510),
        s("ESPN+",                "ESPN+",            "E+",     "#CC0001",  "espn.com",           aliases: ["ESPN Plus"],                                       tmdbID: 149),
        s("MUBI",                 "MUBI",             "MUBI",   "#2B2B2B",  "mubi.com",                                                                        tmdbID: 100),
        s("BritBox",              "BritBox",          "BB",     "#13294B",  "britbox.com",                                                                     tmdbID: 151),
        s("AMC+",                 "AMC+",             "AMC+",   "#002366",  "amcplus.com",        aliases: ["AMC Plus"],                                        tmdbID: 526),
        s("Shudder",              "Shudder",          "SHD",    "#1E1E1E",  "shudder.com",                                                                     tmdbID: 99),
        s("Criterion Channel",    "Criterion",        "CC",     "#CC1411",  "criterionchannel.com",                                                            tmdbID: 258),
        s("Acorn TV",             "Acorn TV",         "acorn",  "#1D6B2E",  "acorn.tv",                                                                        tmdbID: 87),
        s("Hallmark Movies Now",  "Hallmark",         "HMN",    "#8B1A1A",  "hallmarkchannel.com"),
        s("Lifetime Movie Club",  "Lifetime",         "LMC",    "#8B008B",  "mylifetime.com"),
        s("CuriosityStream",      "Curiosity",        "CS",     "#FF6B00",  "curiositystream.com"),
        s("Magellan TV",          "Magellan",         "MAG",    "#1A1A2E",  "magellantv.com"),
        s("Screambox",            "Screambox",        "SCR",    "#8B0000",  "screambox.com"),
        s("Arrow",                "Arrow",            "ARR",    "#E50914",  "arrow-player.com"),
        s("Spectrum",             "Spectrum",         "SPEC",   "#003DA5",  "spectrum.net",       aliases: ["Spectrum TV", "Spectrum On Demand"]),
        s("Fandango at Home",     "Fandango",         "FAN",    "#3D0C96",  "fandango.com",       aliases: ["Vudu", "FandangoNOW"]),
        // Free
        s("Tubi",                 "Tubi",             "tubi",   "#FA4706",  "tubitv.com",         free: true,                                                  tmdbID: 73),
        s("Pluto TV",             "Pluto TV",         "pluto",  "#006EFF",  "pluto.tv",           free: true,                                                  tmdbID: 300),
        s("Kanopy",               "Kanopy",           "K",      "#6B0CB0",  "kanopy.com",         free: true,                                                  tmdbID: 191),
        s("Plex",                 "Plex",             "PLEX",   "#E5A00D",  "plex.tv",            free: true,                                                  tmdbID: 538),
        s("Peacock Free",         "Peacock Free",     "P",      "#1D1D1B",  "peacocktv.com",      free: true,                                                  tmdbID: 386),
        s("The Roku Channel",     "Roku Channel",     "ROKU",   "#6C1D45",  "therokuchannel.com", free: true,                                                  tmdbID: 207),
        s("Crackle",              "Crackle",          "CKL",    "#C0392B",  "crackle.com",        free: true,                                                  tmdbID: 54),
        s("YouTube",              "YouTube",          "YT",     "#FF0000",  "youtube.com",        free: true,                                                  tmdbID: 192),
    ]
}

extension KnownStreamingService {
    static func tmdbProviderIDs(for serviceNames: Set<String>) -> Set<Int> {
        Set(catalog.filter { serviceNames.contains($0.id) }.compactMap { $0.tmdbProviderID })
    }
}

extension StreamingOption {
    func isSubscribed(in serviceNames: Set<String>) -> Bool {
        guard !serviceNames.isEmpty else { return false }
        let name = serviceName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Direct name overlap with subscribed service IDs
        if serviceNames.contains(where: { let s = $0.lowercased(); return name.contains(s) || s.contains(name) }) {
            return true
        }

        // Catalog-mediated match: handles cases where the API name differs from the catalog ID
        // e.g. "Amazon" → "Prime Video", "AppleTV" → "Apple TV+"
        if let knownService = KnownStreamingService.catalog.first(where: { $0.matches(serviceName) }) {
            return serviceNames.contains(knownService.id)
        }

        return false
    }
}
