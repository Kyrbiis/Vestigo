import SwiftUI
import Foundation

struct ImageRefreshTokenKey: EnvironmentKey {
    static let defaultValue = 0
}

struct RefreshImagesAction {
    let action: () -> Void

    func callAsFunction() {
        action()
    }
}

struct RefreshImagesKey: EnvironmentKey {
    static let defaultValue = RefreshImagesAction {}
}

extension EnvironmentValues {
    var imageRefreshToken: Int {
        get { self[ImageRefreshTokenKey.self] }
        set { self[ImageRefreshTokenKey.self] = newValue }
    }

    var refreshImages: RefreshImagesAction {
        get { self[RefreshImagesKey.self] }
        set { self[RefreshImagesKey.self] = newValue }
    }
}

extension URL {
    func refreshedImageURL(token: Int) -> URL {
        guard token > 0 else { return self }

        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.removeAll { $0.name == "vestigoRefresh" }
        queryItems.append(URLQueryItem(name: "vestigoRefresh", value: String(token)))
        components?.queryItems = queryItems

        return components?.url ?? self
    }
}


extension View {
    func favouriteReplacementOverlay(model: VestigoModel) -> some View {
        overlay {
            if model.showFavouriteReplacementAlert,
               let candidate = model.pendingFavouriteReplacement,
               let current = model.currentFavourite(for: candidate.kind) {
                FavouriteReplacementOverlay(
                    current: current,
                    candidate: candidate,
                    cancel: {
                        model.pendingFavouriteReplacement = nil
                        model.showFavouriteReplacementAlert = false
                    },
                    replace: {
                        model.confirmFavouriteReplacement()
                    }
                )
            }
        }
    }
}

#if canImport(UIKit) && os(iOS)
extension UIApplication {
    func openNotificationSettings() {
        let notificationSettingsURL: URL?
        if #available(iOS 16.0, *) {
            notificationSettingsURL = URL(string: UIApplication.openNotificationSettingsURLString)
        } else {
            notificationSettingsURL = nil
        }

        let fallbackURL = URL(string: UIApplication.openSettingsURLString)
        guard let url = notificationSettingsURL ?? fallbackURL else { return }
        open(url)
    }
}
#endif

struct FavouriteReplacementOverlay: View {
    let current: MediaItem
    let candidate: MediaItem
    let cancel: () -> Void
    let replace: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text("Replace favourite?")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                Text("You can only have one favourite \(candidate.displayKindLabel.lowercased()). \(current.title) will no longer be marked favourite.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button("Cancel") {
                        cancel()
                    }
                    .buttonStyle(.plain)
                    .font(.headline.bold())
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .liquidGlass(cornerRadius: 22)

                    Button("Replace") {
                        replace()
                    }
                    .buttonStyle(.plain)
                    .font(.headline.bold())
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .liquidGlass(cornerRadius: 22)
                }
            }
            .padding(18)
            .frame(maxWidth: 330)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.black.opacity(0.42))
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1.1)
            }
            .padding(.horizontal, 26)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
        .zIndex(999)
    }
}
