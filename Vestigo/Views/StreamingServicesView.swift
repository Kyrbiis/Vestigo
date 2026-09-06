import SwiftUI
import Foundation

// MARK: - Streaming Services Setup Sheet

struct StreamingServicesSetupSheet: View {
    @ObservedObject var model: VestigoModel
    let isOnboarding: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    if isOnboarding {
                        Image(systemName: "play.tv.fill")
                            .font(.title3)
                            .foregroundStyle(model.settings.accentColor)
                    }
                    Text(isOnboarding ? "Your Streaming Services" : "Streaming Services")
                        .font(.title2.bold())
                    Spacer()
                    if isOnboarding {
                        Button("Done") { model.completeStreamingSetup() }
                            .fontWeight(.semibold)
                            .foregroundStyle(model.settings.accentColor)
                    }
                }

                if isOnboarding {
                    Text("Select what you subscribe to. Vestigo will put these at the top of where-to-watch lists and can alert you when your saved titles arrive on them.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                StreamingServicesPicker(model: model)
            }
            .padding(18)
            .padding(.bottom, 110)
        }
        .scrollClipDisabled()
        .scrollDismissesKeyboard(.immediately)
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.46))
                .frame(width: 48, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(.clear)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheetLiquidGlass(cornerRadius: 48)
        .ignoresSafeArea(edges: .bottom)
        .presentationBackground(.clear)
        .presentationCornerRadius(54)
    }
}

struct StreamingServicesPicker: View {
    @ObservedObject var model: VestigoModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            let subscribed = model.settings.subscribedServiceNames
            let paid = KnownStreamingService.catalog.filter { !$0.isFree }
            let free = KnownStreamingService.catalog.filter { $0.isFree }

            serviceGrid(title: "Subscription", services: paid, subscribed: subscribed)
            serviceGrid(title: "Free", services: free, subscribed: subscribed)

            if !subscribed.isEmpty {
                Button("Clear all") {
                    for svc in KnownStreamingService.catalog {
                        model.settings.subscribedServiceNames.remove(svc.id)
                    }
                    model.saveSettings()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func serviceGrid(title: String, services: [KnownStreamingService], subscribed: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.leading, 2)

            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(services) { service in
                    ServiceIconButton(
                        service: service,
                        isSelected: subscribed.contains(service.id),
                        accentColor: model.settings.accentColor
                    ) {
                        model.toggleSubscribedService(service.id)
                    }
                }
            }
        }
    }
}

struct ServiceIconButton: View {
    let service: KnownStreamingService
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    private let iconSize: CGFloat = 72

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    iconTile
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(isSelected ? accentColor : Color.white.opacity(0.08), lineWidth: isSelected ? 3 : 1)
                        )

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white, accentColor)
                            .offset(x: 8, y: -8)
                    }
                }

                Text(service.displayName)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: iconSize + 10)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var iconTile: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(hex: service.brandColorHex))
            .frame(width: iconSize, height: iconSize)
            .overlay {
                AsyncImage(url: service.logoURL) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        textLabel
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var textLabel: some View {
        Text(service.iconLabel)
            .font(.system(size: service.iconLabel.count > 4 ? 13 : 16, weight: .heavy, design: .rounded))
            .foregroundStyle(service.lightText ? Color.white : Color.black)
            .minimumScaleFactor(0.6)
            .padding(6)
    }
}
