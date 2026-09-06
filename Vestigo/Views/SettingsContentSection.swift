import SwiftUI
import Foundation

struct SettingsContentSection: View {
    @ObservedObject var model: VestigoModel
    @State private var omdbKeysExpanded = true
    @State private var showPrimaryKey = false
    @State private var showBackupKey = false
    @FocusState private var primaryKeyFocused: Bool
    @State private var primaryKeyWasEmptyOnFocus = false

    var body: some View {
        Text("Content")
            .sectionTitle()
            .padding(.top, 6)

        StreamingServicesSettingsSection(model: model)

        VStack(alignment: .leading, spacing: 10) {

            VStack(alignment: .leading, spacing: 10) {
                Text("Ratings source")
                    .font(.headline.bold())
                let imdbAvailable = !model.settings.omdbPrimaryKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Picker("Ratings source", selection: $model.settings.preferredRatingSource) {
                    Text("TMDb").tag(RatingSource.tmdb)
                    Text("IMDb").tag(RatingSource.imdb)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .liquidGlass(cornerRadius: 18)
                .onChange(of: model.settings.preferredRatingSource) { _, new in
                    if new == .imdb && !imdbAvailable {
                        model.settings.preferredRatingSource = .tmdb
                    }
                }
                Text(imdbAvailable
                    ? "IMDb scores from OMDb are used for rating displays, filters, and sorts where available."
                    : "Add an OMDb API key below to enable IMDb ratings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()

            let primaryTrimmed = model.settings.omdbPrimaryKey.trimmingCharacters(in: .whitespacesAndNewlines)
            DisclosureGroup(isExpanded: $omdbKeysExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Spacer()
                        Link("Get a free key →", destination: URL(string: "https://www.omdbapi.com/apikey.aspx")!)
                            .font(.caption.bold())
                            .foregroundStyle(model.settings.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Primary key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 0) {
                            Group {
                                if showPrimaryKey {
                                    TextField("Paste your OMDb API key", text: $model.settings.omdbPrimaryKey)
                                } else {
                                    SecureField("Paste your OMDb API key", text: $model.settings.omdbPrimaryKey)
                                }
                            }
                            .focused($primaryKeyFocused)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            Button { showPrimaryKey.toggle() } label: {
                                Image(systemName: showPrimaryKey ? "eye.slash" : "eye")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 8)
                            }
                        }
                        .padding(10)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Backup key (optional)")
                            .font(.caption)
                            .foregroundStyle(primaryTrimmed.isEmpty ? .tertiary : .secondary)
                        HStack(spacing: 0) {
                            Group {
                                if showBackupKey {
                                    TextField(primaryTrimmed.isEmpty ? "Add a primary key first" : "Paste a backup key", text: $model.settings.omdbBackupKey)
                                } else {
                                    SecureField(primaryTrimmed.isEmpty ? "Add a primary key first" : "Paste a backup key", text: $model.settings.omdbBackupKey)
                                }
                            }
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .disabled(primaryTrimmed.isEmpty)
                            Button { showBackupKey.toggle() } label: {
                                Image(systemName: showBackupKey ? "eye.slash" : "eye")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 8)
                            }
                            .disabled(primaryTrimmed.isEmpty)
                        }
                        .padding(10)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .opacity(primaryTrimmed.isEmpty ? 0.4 : 1)
                    }
                    .onChange(of: primaryTrimmed) { old, new in
                        if new.isEmpty {
                            model.settings.omdbBackupKey = ""
                            model.settings.preferredRatingSource = .tmdb
                        } else if old.isEmpty {
                            model.settings.preferredRatingSource = .imdb
                        }
                    }
                    .onChange(of: primaryKeyFocused) { _, focused in
                        if focused {
                            primaryKeyWasEmptyOnFocus = model.settings.omdbPrimaryKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        } else if primaryKeyWasEmptyOnFocus && !model.settings.omdbPrimaryKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            model.refreshVisibleExternalRatings()
                        }
                    }

                    Text("Your key is stored privately on-device and synced to your Apple ID via iCloud — it is never shared. Without a key, IMDb ratings are unavailable and scores fall back to TMDb.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !primaryTrimmed.isEmpty {
                        OMDbUsageBar(settings: model.settings)
                    }
                }
                .padding(.top, 8)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("OMDb API Keys")
                        .font(.headline.bold())
                        .foregroundStyle(.primary)
                    Text(primaryTrimmed.isEmpty ? "No key — ratings fall back to TMDb" : (!model.settings.omdbBackupKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Keys configured" : "Key configured"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(.primary)
            .tint(model.settings.accentColor)
            .settingBubble()
            .onAppear { omdbKeysExpanded = primaryTrimmed.isEmpty }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Prioritise English", isOn: $model.settings.prioritiseEnglish)
                    .font(.headline.bold())
                    .tint(model.settings.accentColor)

                Text("When this is on, English-language titles are shown first when otherwise similar results are available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()
            .onChange(of: model.settings.prioritiseEnglish) { _, _ in
                model.searchResults = model.preparedResults(model.searchResults)
                Task { await model.loadHome() }
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Hide adult/explicit results", isOn: $model.settings.hideAdultResults)
                    .font(.headline.bold())
                    .tint(model.settings.accentColor)

                Text("When this is on, searches and browsed results avoid adult-marked TMDb entries where the API supports that filtering. When it is off, TMDb may include adult-marked results.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()
            .onChange(of: model.settings.hideAdultResults) { _, _ in
                model.updateSearch()
                Task { await model.loadHome() }
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Hide anime", isOn: $model.settings.hideAnimeResults)
                    .font(.headline.bold())
                    .tint(model.settings.accentColor)

                Text("When this is on, anime and likely anime-related results are filtered out where possible. This may also hide anime-adjacent titles that are not considered actual anime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()
            .onChange(of: model.settings.hideAnimeResults) { _, _ in
                model.searchResults = model.preparedResults(model.searchResults)
                Task { await model.loadHome() }
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Reduce child-focused results", isOn: $model.settings.hideLowestAgeRatings)
                    .font(.headline.bold())
                    .tint(model.settings.accentColor)

                Text("When this is on, Vestigo hides known youngest-audience ratings where certification data is available, and downweights likely child-focused animation in recommendations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()
            .onChange(of: model.settings.hideLowestAgeRatings) { _, _ in
                model.searchResults = model.preparedResults(model.searchResults)
                model.updateSearch()
                Task { await model.loadHome() }
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Hide from Home", isOn: $model.settings.hideWatchedFromHome)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .tint(model.settings.accentColor)
                        .padding(.trailing, 6)

                    Toggle("Hide from Search", isOn: $model.settings.hideWatchedFromSearch)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .tint(model.settings.accentColor)
                        .padding(.trailing, 6)
                }
                .padding(.top, 8)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hide watched results")
                        .font(.headline.bold())
                        .foregroundStyle(.primary)

                    Text("Choose where items you have already marked as watched should be hidden. Watchlist and Collections still show their saved contents.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(.primary)
            .tint(model.settings.accentColor)
            .settingBubble()
            .onChange(of: model.settings.hideWatchedFromHome) { _, _ in
                Task { await model.loadHome() }
            }
            .onChange(of: model.settings.hideWatchedFromSearch) { _, _ in
                model.searchResults = model.preparedResults(model.searchResults, hideWatched: model.settings.hideWatchedFromSearch)

                Task {
                    for route in model.searchPath {
                        if case .genre(let genreRoute) = route {
                            await model.loadGenre(genreRoute.genre)
                        }
                    }
                }
            }

            ShortFilmsSettingsGroup(model: model)
            ExtrasAndPromosSettingsGroup(model: model)

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Search", isOn: $model.settings.hideUpcomingFromSearch)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .tint(model.settings.accentColor)
                        .padding(.trailing, 6)

                    Toggle("For You", isOn: $model.settings.hideUpcomingFromRecommended)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .tint(model.settings.accentColor)
                        .padding(.trailing, 6)

                    Toggle("Collection and franchise recommendations", isOn: $model.settings.hideUpcomingFromCollectionRecommendations)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .tint(model.settings.accentColor)
                        .padding(.trailing, 6)
                }
                .padding(.top, 8)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hide upcoming releases")
                        .font(.headline.bold())
                        .foregroundStyle(.primary)

                    Text("Choose where unreleased titles should be hidden. Home does not have a toggle because Upcoming releases is its own carousel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(.primary)
            .tint(model.settings.accentColor)
            .settingBubble()
            .onChange(of: model.settings.hideUpcomingFromSearch) { _, _ in
                model.updateSearch()

                Task {
                    for route in model.searchPath {
                        if case .genre(let genreRoute) = route {
                            await model.loadGenre(genreRoute.genre)
                        }
                    }
                }
            }
            .onChange(of: model.settings.hideUpcomingFromRecommended) { _, _ in
                Task { await model.loadSmartRecommendations() }
            }
            .onChange(of: model.settings.hideUpcomingFromCollectionRecommendations) { _, _ in
                Task {
                    for collection in model.library.collections {
                        await model.loadCollectionRecommendations(for: collection.id)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Remove items from watchlist", isOn: $model.settings.removeItemsFromWatchlist)
                    .font(.headline.bold())
                    .tint(model.settings.accentColor)

                Text("When this is on, marking a saved item as watched removes it from Watchlist. When it is off, watched saved items stay in Watchlist under the Watched section.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Prompt to rate after marking watched", isOn: $model.settings.promptToRateAfterMarkingWatched)
                    .font(.headline.bold())
                    .tint(model.settings.accentColor)

                Text("When this is on, marking a movie or series as watched opens a rating prompt right where you are.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Automatically track watch date", isOn: $model.settings.autoTrackWatchDate)
                    .font(.headline.bold())
                    .tint(model.settings.accentColor)

                Text("When off, watch dates are set manually. When on, the date is recorded automatically the moment you mark something as watched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Show upcoming releases", isOn: $model.settings.showUpcomingReleases)
                    .font(.headline.bold())
                    .tint(model.settings.accentColor)

                Text("When this is on, Home shows unreleased movies and series in the Upcoming section.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()
            .onChange(of: model.settings.showUpcomingReleases) { _, _ in
                Task { await model.loadHome() }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Default Home Filter")
                    .font(.headline.bold())

                FilterPills(
                    filter: Binding(
                        get: { model.settings.defaultHomeFilter },
                        set: { newValue in
                            model.settings.defaultHomeFilter = newValue
                            model.mediaFilter = newValue
                            Task { await model.loadHome() }
                        }
                    ),
                    options: [.movie, .tv, .both]
                ) {
                    model.mediaFilter = model.settings.defaultHomeFilter
                    Task { await model.loadHome() }
                }

                Text("Choose whether Home opens to movies, series, or both.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()

            VStack(alignment: .leading, spacing: 8) {
                Text("Default Search Type")
                    .font(.headline.bold())

                SearchFilterPills(
                    filter: Binding(
                        get: { model.settings.defaultSearchFilter },
                        set: { newValue in
                            model.settings.defaultSearchFilter = newValue
                            model.searchFilter = newValue
                            model.updateSearch()
                        }
                    )
                ) {
                    model.searchFilter = model.settings.defaultSearchFilter
                    model.updateSearch()
                }

                Text("Choose which type Search opens with by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()

            VStack(alignment: .leading, spacing: 8) {
                Text("Default Category Sort")
                    .font(.headline.bold())

                GenreSortPicker(
                    sort: Binding(
                        get: { model.settings.defaultCategorySort },
                        set: { newValue in
                            model.settings.defaultCategorySort = newValue
                        }
                    )
                ) { }

                Text("Choose whether category pages open sorted by IMDb rating or release date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()

        }
    }
}

// MARK: - Private helper (only used by SettingsContentSection)

private struct StreamingServicesSettingsSection: View {
    @ObservedObject var model: VestigoModel
    @State private var showSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Streaming Services")
                        .font(.headline.bold())
                    let count = model.settings.subscribedServiceNames.count
                    Text(count == 0 ? "None selected — showing all services" : "\(count) service\(count == 1 ? "" : "s") selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Manage") { showSheet = true }
                    .font(.subheadline)
                    .foregroundStyle(model.settings.accentColor)
            }

            Divider().opacity(0.3)

            HStack {
                Text("Region")
                    .font(.subheadline)
                Spacer()
                Picker("Region", selection: Binding(
                    get: { model.settings.streamingRegion },
                    set: { model.settings.streamingRegion = $0; model.saveSettings(); model.providerCache = [:] }
                )) {
                    ForEach(StreamingRegion.allCases) { region in
                        Text(region.displayName).tag(region)
                    }
                }
                .pickerStyle(.menu)
                .foregroundStyle(model.settings.accentColor)
            }

        }
        .settingBubble()
        .sheet(isPresented: $showSheet) {
            StreamingServicesSetupSheet(model: model, isOnboarding: false)
        }
    }
}
