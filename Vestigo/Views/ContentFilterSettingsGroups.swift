import SwiftUI
import Foundation

struct ShortFilmsSettingsGroup: View {
    @ObservedObject var model: VestigoModel

    var body: some View {
        DisclosureGroup {
            toggles
        } label: {
            label
        }
        .foregroundStyle(.primary)
        .tint(model.settings.accentColor)
        .settingBubble()
        .onChange(of: model.settings.hideShortFilmsFromHome) { _, _ in
            Task { await model.loadHome() }
        }
        .onChange(of: model.settings.hideShortFilmsFromSearch) { _, _ in
            model.updateSearch()

            Task {
                for route in model.searchPath {
                    if case .genre(let genreRoute) = route {
                        await model.loadGenre(genreRoute.genre)
                    }
                }
            }
        }
        .onChange(of: model.settings.hideShortFilmsFromRecommended) { _, _ in
            Task { await model.loadSmartRecommendations() }
        }
        .onChange(of: model.settings.hideShortFilmsFromCollectionRecommendations) { _, _ in
            Task {
                for collection in model.library.collections {
                    await model.loadCollectionRecommendations(for: collection.id)
                }
            }
        }
    }

    private var toggles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Hide from Home", isOn: $model.settings.hideShortFilmsFromHome)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .tint(model.settings.accentColor)
                .padding(.trailing, 6)

            Toggle("Hide from Search", isOn: $model.settings.hideShortFilmsFromSearch)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .tint(model.settings.accentColor)
                .padding(.trailing, 6)

            Toggle("Hide from For You", isOn: $model.settings.hideShortFilmsFromRecommended)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .tint(model.settings.accentColor)
                .padding(.trailing, 6)

            Toggle("Hide from Collection Recommendations", isOn: $model.settings.hideShortFilmsFromCollectionRecommendations)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .tint(model.settings.accentColor)
                .padding(.trailing, 6)
        }
        .padding(.top, 8)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hide short films")
                .font(.headline.bold())
                .foregroundStyle(.primary)

            Text("Short films are detected from runtime after details load. Unknown runtimes stay visible.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ExtrasAndPromosSettingsGroup: View {
    @ObservedObject var model: VestigoModel

    var body: some View {
        DisclosureGroup {
            toggles
        } label: {
            label
        }
        .foregroundStyle(.primary)
        .tint(model.settings.accentColor)
        .settingBubble()
        .onChange(of: model.settings.hideExtrasAndPromosFromHome) { _, _ in
            Task { await model.loadHome() }
        }
        .onChange(of: model.settings.hideExtrasAndPromosFromSearch) { _, _ in
            model.updateSearch()

            Task {
                for route in model.searchPath {
                    if case .genre(let genreRoute) = route {
                        await model.loadGenre(genreRoute.genre)
                    }
                }
            }
        }
        .onChange(of: model.settings.hideExtrasAndPromosFromRecommended) { _, _ in
            Task { await model.loadSmartRecommendations() }
        }
        .onChange(of: model.settings.hideExtrasAndPromosFromCollectionRecommendations) { _, _ in
            Task {
                for collection in model.library.collections {
                    await model.loadCollectionRecommendations(for: collection.id)
                }
            }
        }
    }

    private var toggles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Hide from Home", isOn: $model.settings.hideExtrasAndPromosFromHome)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .tint(model.settings.accentColor)
                .padding(.trailing, 6)

            Toggle("Hide from Search", isOn: $model.settings.hideExtrasAndPromosFromSearch)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .tint(model.settings.accentColor)
                .padding(.trailing, 6)

            Toggle("Hide from For You", isOn: $model.settings.hideExtrasAndPromosFromRecommended)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .tint(model.settings.accentColor)
                .padding(.trailing, 6)

            Toggle("Hide from Collection Recommendations", isOn: $model.settings.hideExtrasAndPromosFromCollectionRecommendations)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .tint(model.settings.accentColor)
                .padding(.trailing, 6)
        }
        .padding(.top, 8)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hide extras and promos")
                .font(.headline.bold())
                .foregroundStyle(.primary)

            Text("Uses TMDb metadata signals like runtime, documentary genre, audience footprint, and catalog completeness. It avoids fixed title phrase lists, so it only runs when enabled.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
