import SwiftUI
import Foundation

// MARK: - ProviderRow

struct ProviderRow: View {
    let option: StreamingOption
    @Environment(\.openURL) private var openURL
    @Environment(\.imageRefreshToken) private var imageRefreshToken

    private var tappableURL: URL? {
        option.tappableURL
    }

    var body: some View {
        Button {
            guard let tappableURL else { return }
            openURL(tappableURL)
        } label: {
            HStack(spacing: 12) {
                providerLogo

                VStack(alignment: .leading, spacing: 3) {
                    Text(option.cleanedServiceName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(option.cleanedAvailabilityLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if tappableURL != nil {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: 22)
        .opacity(tappableURL == nil ? 0.72 : 1.0)
        .appScrollTouchSafe()
    }

    private var providerLogo: some View {
        let catalogService = option.matchedCatalogService
        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(catalogService.map { Color(hex: $0.brandColorHex) } ?? .white.opacity(0.13))

            if let url = option.logoURL {
                AsyncImage(url: url.refreshedImageURL(token: imageRefreshToken)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 52, height: 52)
                            .clipped()
                    default:
                        providerFallbackText(lightText: catalogService?.lightText ?? true)
                    }
                }
            } else {
                providerFallbackText(lightText: catalogService?.lightText ?? true)
            }
        }
        .frame(width: 52, height: 52)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func providerFallbackText(lightText: Bool) -> some View {
        Text(option.serviceShort)
            .font(.caption.bold())
            .foregroundStyle(lightText ? Color.white : Color.black)
    }
}

extension StreamingOption {
    var cleanedServiceName: String {
        let trimmed = serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown service" : trimmed
    }

    var cleanedAvailabilityLine: String {
        let parts = [cleanedTypeText, cleanedPriceText, cleanedQualityText]
            .compactMap { $0 }

        if parts.isEmpty {
            return "Availability details not provided"
        }

        return parts.joined(separator: " • ")
    }

    var dialogTitle: String {
        "\(cleanedServiceName) - \(cleanedAvailabilityLine)"
    }

    var tappableURL: URL? {
        guard let rawURL = openURL?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty else {
            return nil
        }
        return URL(string: rawURL)
    }

    private var cleanedTypeText: String? {
        let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.isUnknownPlaceholder else { return nil }
        return trimmed.capitalized
    }

    private var cleanedPriceText: String? {
        let trimmed = priceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.isUnknownPlaceholder else { return nil }
        return trimmed
    }

    private var cleanedQualityText: String? {
        let trimmed = qualityText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.isUnknownPlaceholder else { return nil }
        return trimmed
    }

    var matchedCatalogService: KnownStreamingService? {
        KnownStreamingService.catalog.first { $0.matches(serviceName) }
    }

    var logoURL: URL? {
        // Prefer Brandfetch via catalog — higher quality than favicons
        if let domain = matchedCatalogService?.domain {
            return URL(string: "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api/brand-logo?domain=\(domain)&w=128&h=128")
        }
        // Fallback: Google favicon for services not yet in catalog
        guard let domain = serviceLogoDomain else { return nil }
        var components = URLComponents(string: "https://www.google.com/s2/favicons")
        components?.queryItems = [
            URLQueryItem(name: "sz", value: "128"),
            URLQueryItem(name: "domain", value: domain)
        ]
        return components?.url
    }

    private var serviceLogoDomain: String? {
        let normalized = cleanedServiceName
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "+", with: "plus")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: "")

        if normalized.contains("showtime") { return "showtime.com" }
        if normalized.contains("googleplay") { return "play.google.com" }
        if normalized.contains("microsoft") { return "microsoft.com" }
        if normalized.contains("hoopla") { return "hoopladigital.com" }
        if normalized.contains("freevee") { return "amazon.com" }

        return nil
    }
}
