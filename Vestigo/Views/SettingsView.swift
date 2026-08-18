import SwiftUI
import Foundation
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WebKit)
import WebKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var model: VestigoModel
    @State private var clearPresses = 0
    @State private var showClearConfirm = false
    @State private var importText = ""
    @State private var importNotFound: [String] = []
    @State private var showImportNotFoundAlert = false
    @State private var pendingImportText: String?
    @State private var importWarningMessage = ""
    @State private var showImportWarningAlert = false
    @State private var showImportFilePicker = false
    @State private var isImporting = false
    @State private var pendingImportFormat: WatchedImportEntry.ImportFormat = .automatic
    @State private var selectedCategory: SettingsCategory = .content
    @State private var importPlaceholderIndex = 0
    @State private var omdbKeysExpanded = true
    @State private var showPrimaryKey = false
    @State private var showBackupKey = false
    @FocusState private var primaryKeyFocused: Bool
    @State private var primaryKeyWasEmptyOnFocus = false
    @AppStorage("Vestigo.devMode") private var devMode: Bool = false

    enum SettingsCategory: String, CaseIterable, Identifiable {
        case content
        case display
        case notifications
        case data
        case about
        case dev

        var id: String { rawValue }
        var title: String {
            switch self {
            case .display: return "Display"
            case .content: return "Content"
            case .notifications: return "Alerts"
            case .data: return "Data"
            case .about: return "About"
            case .dev: return "Dev"
            }
        }
    }

    private var importPlaceholderText: String {
        let examples = [
            "Star Wars 5 f m\nRed Notice 4.5\nThe Flash 4 s",
            "Star Wars 5 f m, Red Notice 4.5, The Flash 4 s"
        ]
        return examples[importPlaceholderIndex % examples.count]
    }
    
    var body: some View {
        BaseScreen(title: "Settings", filter: .constant(.both), settings: model.settings, contentTopPadding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                settingsCategoryPills

                if selectedCategory == .display {
                Text("Display")
                    .sectionTitle()
                
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Display style")
                            .font(.headline.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Picker("Display style", selection: $model.settings.appearance) {
                            ForEach(AppearanceMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .settingBubble()

                    Toggle("Plain background", isOn: $model.settings.usePlainBackground)
                        .font(.headline.bold())
                        .tint(model.settings.accentColor)
                        .settingBubble()

                    ColorPicker(
                        "Accent Colour",
                        selection: Binding(
                            get: { model.settings.accentColor },
                            set: { model.settings.setAccentColor($0) }
                        ),
                        supportsOpacity: false
                    )
                    .font(.headline.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingBubble()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Home & For You carousels")
                            .font(.headline.bold())
                            .foregroundStyle(.primary)

                        Text("Drag to reorder. Tap the eye to hide a carousel from its tab.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)

                    CarouselOrderContent(model: model)
                }
                }
                
                if selectedCategory == .content {
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

                            Toggle("For You / Recommended", isOn: $model.settings.hideUpcomingFromRecommended)
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

                if selectedCategory == .data {
                Text("Data")
                    .sectionTitle()
                    .padding(.top, 6)
                
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Import watched titles as title, star rating, optional f for favourite, and m for movie or s for series. Type in the text field with the format or import files. .txt can use one item per line or commas; .csv uses commas only.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        
                        TextField(importPlaceholderText, text: $importText, axis: .vertical)
                            .lineLimit(3...5)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .liquidGlass(cornerRadius: 18)
                        
                        Button {
                            importWatchedData(importText)
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: "tray.and.arrow.down")
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(width: 24, height: 22, alignment: .center)
                                
                                Text(isImporting ? "Importing..." : "Import pasted data")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                    .frame(height: 22, alignment: .center)
                                
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 32, alignment: .center)
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isImporting || importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button {
                            showImportFilePicker = true
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: "doc.badge.plus")
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(width: 24, height: 22, alignment: .center)

                                Text("Import .txt or .csv file")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                    .frame(height: 22, alignment: .center)

                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 32, alignment: .center)
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isImporting)
                    }
                    .padding(10)
                    .liquidGlass(cornerRadius: 22)
                    
                    HStack(spacing: 10) {
                        ForEach(ExportFormat.allCases) { format in
                            Button {
                                model.prepareExport(format: format)
                            } label: {
                                HStack(alignment: .center, spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 17, weight: .semibold))
                                        .frame(width: 22, height: 22, alignment: .center)

                                    Text("Export \(format.title)")
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .lineLimit(1)
                                        .frame(height: 22, alignment: .center)

                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 48, alignment: .center)
                                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .liquidGlass(cornerRadius: 18)
                        }
                    }
                    .fileExporter(isPresented: $model.showExporter, document: model.exportDocument, contentType: model.exportFormat.contentType, defaultFilename: model.exportFormat.filename) { _ in }

                    NavigationLink {
                        HiddenItemsReviewView(model: model)
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: "eye.slash.circle")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 22, height: 22, alignment: .center)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Review hidden items")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)
                                Text("Restore \"Never show\" or \"Not interested\" items.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .settingBubble()

                    Button("Reset settings") {
                        model.settings = AppSettings()
                        model.searchFilter = model.settings.defaultSearchFilter
                        model.searchFilter = model.settings.defaultSearchFilter
                        model.mediaFilter = model.settings.defaultHomeFilter
                        model.genreResults.removeAll()
                        model.updateSearch()
                        Task { await model.loadHome() }
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingBubble()
                    
                    Button(clearPresses < 3 ? "Clear all data (press \(3 - clearPresses) more)" : "Confirm clear all data") {
                        clearPresses += 1
                        if clearPresses >= 3 { showClearConfirm = true }
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingBubble()
                }
                
                }

                if selectedCategory == .about {
                    Text("About")
                        .sectionTitle()
                        .padding(.top, 6)

                    AboutInfoView()

                    AttributionFooter()
                }

                if selectedCategory == .dev {
                    Text("Developer")
                        .sectionTitle()
                        .padding(.top, 6)

                    DevToolsPanel(model: model)

                    Button("Hide developer tab") {
                        selectedCategory = .about
                        devMode = false
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingBubble()
                    .padding(.top, 4)
                }
            }
        }
        .onChange(of: model.settings) { _, _ in
            model.saveSettings()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                importPlaceholderIndex = (importPlaceholderIndex + 1) % 2
            }
        }
        .alert("Delete all Vestigo data?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) { clearPresses = 0 }
            Button("Delete", role: .destructive) {
                model.clearAllData()
                clearPresses = 0
            }
        } message: {
            Text("This removes watched items, ratings, watchlist, collections, episode progress, and settings from local storage.")
        }
        .alert("The following items were not found", isPresented: $showImportNotFoundAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importNotFound.joined(separator: "\n"))
        }
        .alert("Double-check import formatting", isPresented: $showImportWarningAlert) {
            Button("Cancel", role: .cancel) {
                pendingImportText = nil
            }
            Button("Continue") {
                if let pendingImportText {
                    let textToImport = pendingImportText
                    let formatToImport = pendingImportFormat
                    self.pendingImportText = nil
                    importWatchedData(textToImport, format: formatToImport, skipsWarnings: true)
                }
            }
        } message: {
            Text(importWarningMessage)
        }
        .fileImporter(isPresented: $showImportFilePicker, allowedContentTypes: [.plainText, .commaSeparatedText], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importWatchedFile(url)
            case .failure:
                break
            }
        }
    }

    private var visibleCategories: [SettingsCategory] {
        SettingsCategory.allCases.filter { $0 != .notifications && ($0 != .dev || devMode) }
    }

    private var settingsCategoryPills: some View {
        Picker("Settings category", selection: $selectedCategory) {
            ForEach(visibleCategories) { category in
                Text(category.title).tag(category)
            }
        }
        .pickerStyle(.segmented)
        .liquidGlass(cornerRadius: 18)
    }

    private func importWatchedData(_ text: String, format: WatchedImportEntry.ImportFormat = .automatic, skipsWarnings: Bool = false) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let report = WatchedImportEntry.report(for: trimmedText, format: format)
        if !skipsWarnings, let warningMessage = WatchedImportEntry.warningMessage(for: report) {
            pendingImportText = trimmedText
            pendingImportFormat = format
            importWarningMessage = warningMessage
            showImportWarningAlert = true
            return
        }

        isImporting = true
        Task {
            let notFound = await model.importWatchedText(trimmedText, format: format)
            await MainActor.run {
                importNotFound = notFound
                showImportNotFoundAlert = !notFound.isEmpty
                isImporting = false
            }
        }
    }

    private func importWatchedFile(_ url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        importText = text
        let fileExtension = url.pathExtension.lowercased()
        let format: WatchedImportEntry.ImportFormat = fileExtension == "csv" ? .commaSeparated : .automatic
        importWatchedData(text, format: format)
    }
}

struct CarouselOrderContent: View {
    @ObservedObject var model: VestigoModel
    @State private var draggingHome: HomeCarousel?
    @State private var draggingForYou: ForYouCarousel?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Home")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)

                VStack(spacing: 10) {
                    ForEach(model.settings.homeCarouselOrder, id: \.self) { carousel in
                        CarouselOrderRow(
                            title: carousel.title,
                            isHidden: model.settings.homeCarouselHidden.contains(carousel),
                            isDragging: draggingHome == carousel,
                            accentColor: model.settings.accentColor,
                            toggle: {
                                if model.settings.homeCarouselHidden.contains(carousel) {
                                    model.settings.homeCarouselHidden.remove(carousel)
                                } else {
                                    model.settings.homeCarouselHidden.insert(carousel)
                                }
                            }
                        )
                        .onDrag {
                            draggingHome = carousel
                            return NSItemProvider(object: carousel.rawValue as NSString)
                        }
                        .onDrop(
                            of: [.text],
                            delegate: CarouselDropDelegate(
                                target: carousel,
                                order: Binding(
                                    get: { model.settings.homeCarouselOrder },
                                    set: { model.settings.homeCarouselOrder = $0 }
                                ),
                                dragging: $draggingHome,
                                valueFromRaw: HomeCarousel.init(rawValue:)
                            )
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("For You")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)

                VStack(spacing: 10) {
                    ForEach(model.settings.forYouCarouselOrder, id: \.self) { carousel in
                        CarouselOrderRow(
                            title: carousel.title,
                            isHidden: model.settings.forYouCarouselHidden.contains(carousel),
                            isDragging: draggingForYou == carousel,
                            accentColor: model.settings.accentColor,
                            toggle: {
                                if model.settings.forYouCarouselHidden.contains(carousel) {
                                    model.settings.forYouCarouselHidden.remove(carousel)
                                } else {
                                    model.settings.forYouCarouselHidden.insert(carousel)
                                }
                            }
                        )
                        .onDrag {
                            draggingForYou = carousel
                            return NSItemProvider(object: carousel.rawValue as NSString)
                        }
                        .onDrop(
                            of: [.text],
                            delegate: CarouselDropDelegate(
                                target: carousel,
                                order: Binding(
                                    get: { model.settings.forYouCarouselOrder },
                                    set: { model.settings.forYouCarouselOrder = $0 }
                                ),
                                dragging: $draggingForYou,
                                valueFromRaw: ForYouCarousel.init(rawValue:)
                            )
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CarouselDropDelegate<Item: Hashable>: DropDelegate {
    let target: Item
    @Binding var order: [Item]
    @Binding var dragging: Item?
    let valueFromRaw: (String) -> Item?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target,
              let fromIndex = order.firstIndex(of: dragging),
              let toIndex = order.firstIndex(of: target),
              fromIndex != toIndex else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            order.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

struct CarouselOrderRow: View {
    let title: String
    let isHidden: Bool
    let isDragging: Bool
    let accentColor: Color
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.headline.bold())
                .foregroundStyle(isHidden ? .secondary : .primary)

            Spacer()

            Button(action: toggle) {
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isHidden ? .secondary : accentColor)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isHidden ? "Show \(title)" : "Hide \(title)")

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 20)
        .opacity(isDragging ? 0.4 : 1.0)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct HiddenItemsReviewView: View {
    @ObservedObject var model: VestigoModel

    private var entries: [(item: MediaItem, status: HiddenStatus)] {
        let neverShow = model.library.neverShowAgainItems.map { ($0, HiddenStatus.neverShow) }
        let notInterested = model.library.notInterestedItems
            .filter { !model.library.isNeverShowAgain($0.key) }
            .map { ($0, HiddenStatus.notInterested) }
        return (neverShow + notInterested)
            .sorted { lhs, rhs in
                lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
            }
    }

    var body: some View {
        ZStack {
            AppBackground(settings: model.settings)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if entries.isEmpty {
                        StatusBubble(
                            title: "No hidden items",
                            text: "Items marked as \"Never show\" or \"Not interested\" show up here."
                        )
                    } else {
                        ForEach(entries, id: \.item.key) { entry in
                            HiddenItemRow(
                                item: entry.item,
                                status: entry.status,
                                ratingText: model.ratingDisplayText(for: entry.item),
                                accentColor: model.settings.accentColor,
                                onOpen: { model.selectedItem = entry.item },
                                onChangeStatus: {
                                    switch entry.status {
                                    case .neverShow:
                                        model.toggleNotInterested(entry.item)
                                    case .notInterested:
                                        model.toggleNeverShowAgain(entry.item)
                                    }
                                },
                                onRestore: {
                                    switch entry.status {
                                    case .neverShow:
                                        model.toggleNeverShowAgain(entry.item)
                                    case .notInterested:
                                        model.toggleNotInterested(entry.item)
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Hidden items")
        .navigationBarTitleDisplayMode(.inline)
    }

    enum HiddenStatus {
        case neverShow
        case notInterested

        var label: String {
            switch self {
            case .neverShow: return "Never show"
            case .notInterested: return "Not interested"
            }
        }

        var iconName: String {
            switch self {
            case .neverShow: return "eye.slash"
            case .notInterested: return "hand.thumbsdown"
            }
        }
    }
}

struct HiddenItemRow: View {
    let item: MediaItem
    let status: HiddenItemsReviewView.HiddenStatus
    let ratingText: String
    let accentColor: Color
    let onOpen: () -> Void
    let onChangeStatus: () -> Void
    let onRestore: () -> Void
    @Environment(\.imageRefreshToken) private var imageRefreshToken

    private var statusBinding: Binding<HiddenItemsReviewView.HiddenStatus> {
        Binding(
            get: { status },
            set: { newStatus in if newStatus != status { onChangeStatus() } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) {
                HStack(alignment: .center, spacing: 12) {
                    posterThumbnail

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.headline.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(metadataLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if !ratingText.isEmpty {
                            Text(ratingText)
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Picker("Status", selection: statusBinding) {
                    Text("Not interested").tag(HiddenItemsReviewView.HiddenStatus.notInterested)
                    Text("Never show").tag(HiddenItemsReviewView.HiddenStatus.neverShow)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .liquidGlass(cornerRadius: 18)

                Button(action: onRestore) {
                    ZStack {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 36, height: 36)
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Restore \(item.title)")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 22)
    }

    private var metadataLine: String {
        var parts: [String] = [item.kind.label]
        let yearText = item.releaseYearText
        if yearText != "TBA" {
            parts.append(yearText)
        }
        return parts.joined(separator: " • ")
    }

    private var posterThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.08))

            if let url = item.posterURL {
                AsyncImage(url: url.refreshedImageURL(token: imageRefreshToken)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Image(systemName: "film")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: "film")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 54, height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct AboutInfoView: View {
    @AppStorage("Vestigo.devMode") private var devMode: Bool = false
    @State private var titleTapCount = 0

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

        switch (version, build) {
        case let (.some(version), .some(build)) where !version.isEmpty && !build.isEmpty:
            return "Version \(version) (\(build))"
        case let (.some(version), _) where !version.isEmpty:
            return "Version \(version)"
        default:
            return "Version unavailable"
        }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            VStack(alignment: .center, spacing: 4) {
                Text("Vestigo")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .onTapGesture {
                        guard !devMode else { return }
                        titleTapCount += 1
                        if titleTapCount >= 7 {
                            devMode = true
                            titleTapCount = 0
                        }
                    }

                Text(versionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Created by Jojo Hyman")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            AboutLinkButton(
                title: "GitHub",
                systemImage: "chevron.left.forwardslash.chevron.right",
                url: URL(string: "https://github.com/Kyrbiis/Vestigo")!
            )

            VStack(alignment: .center, spacing: 6) {
                Text("Your library and preferences are stored on-device and in iCloud where enabled.")
                Text("Vestigo was vibe coded: AI assisted with code implementation, while the product thinking, decisions, review, and non-coding work were all done by people.")
                Text("Vestigo is not affiliated with TMDB, IMDb, OMDb, TheTVDB, Watchmode, YouTube, Wikimedia, or their parent companies.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
    }
}

struct AboutLinkButton: View {
    let title: String
    let systemImage: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))

                Text(title)
                    .font(.caption.bold())
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: 17)
    }
}

struct AttributionFooter: View {
    private let providers = AttributionProvider.all

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Text("Vestigo combines catalog, ratings, recommendations, availability, trailer, and open-knowledge data from the following services:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .center, spacing: 14) {
                ForEach(providers) { provider in
                    Link(destination: provider.url) {
                        AttributionProviderRow(provider: provider)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}

struct AttributionProviderRow: View {
    let provider: AttributionProvider

    var body: some View {
        VStack(alignment: .center, spacing: provider.hasLogo ? 5 : 0) {
            AttributionLogoView(provider: provider)

            Text(provider.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 320)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct AttributionLogoView: View {
    let provider: AttributionProvider

    var body: some View {
        ZStack {
            if let logoText = provider.logoText {
                Text(logoText)
                    .font(.custom("HelveticaNeue-Thin", fixedSize: 30))
                    .fontWeight(.thin)
                    .foregroundStyle(Color(red: 0.42, green: 0.42, blue: 0.42))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else if let logoURL = provider.logoURL {
                AsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(6)
                    default:
                        fallback
                    }
                }
            } else if let logoAssetName = provider.logoAssetName {
                Image(logoAssetName)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            } else {
                fallback
            }
        }
        .frame(width: provider.logoAssetName == nil ? 120 : 150, height: provider.hasLogo ? provider.logoHeight : 0)
        .opacity(provider.hasLogo ? 1 : 0)
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Text(provider.shortLabel)
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 4)
    }
}

struct AttributionProvider: Identifiable {
    let id: String
    let name: String
    let shortLabel: String
    let description: String
    let url: URL
    let logoURL: URL?
    let logoAssetName: String?
    let logoText: String?
    var logoHeight: CGFloat = 36

    var hasLogo: Bool {
        logoURL != nil || logoAssetName != nil || logoText != nil
    }

    static let all: [AttributionProvider] = [
        AttributionProvider(
            id: "tmdb",
            name: "TMDB",
            shortLabel: "TMDB",
            description: "This product uses the TMDB API but is not endorsed or certified by TMDB.",
            url: URL(string: "https://www.themoviedb.org/")!,
            logoURL: nil,
            logoAssetName: "TMDBLogo",
            logoText: nil
        ),
        AttributionProvider(
            id: "watchmode",
            name: "Watchmode",
            shortLabel: "WM",
            description: "Streaming availability and provider data are provided in part by Watchmode.",
            url: URL(string: "https://api.watchmode.com/")!,
            logoURL: nil,
            logoAssetName: "WatchmodeLogo",
            logoText: nil
        ),
        AttributionProvider(
            id: "thetvdb",
            name: "TheTVDB",
            shortLabel: "TVDB",
            description: "Series, season, episode, and franchise metadata are provided in part by TheTVDB.",
            url: URL(string: "https://thetvdb.com/")!,
            logoURL: URL(string: "https://www.thetvdb.com/images/attribution/logo1.png"),
            logoAssetName: nil,
            logoText: nil
        ),
        AttributionProvider(
            id: "omdb",
            name: "OMDb",
            shortLabel: "OMDb",
            description: "This product uses the OMDb API but is not endorsed or certified by OMDb or IMDb. Ratings and movie data are provided in part by The Open Movie Database and IMDb.",
            url: URL(string: "https://www.omdbapi.com/")!,
            logoURL: nil,
            logoAssetName: nil,
            logoText: "OMDb API"
        ),
        /*
        TasteDive attribution is intentionally disabled because the app no longer calls
        TasteDive in the active recommendation path. If we re-enable TasteDive as a live
        data source later, restore this provider entry at the same time.

        AttributionProvider(
            id: "tastedive",
            name: "TasteDive",
            shortLabel: "TD",
            description: "Some similar-title candidate data is provided by the legacy TasteDive API.",
            url: URL(string: "https://tastedive.com/read/api")!,
            logoURL: nil,
            logoAssetName: "TasteDiveLogo",
            logoText: nil
        ),
        */
        AttributionProvider(
            id: "youtube",
            name: "YouTube",
            shortLabel: "YT",
            description: "Trailer playback uses embedded YouTube videos where available.",
            url: URL(string: "https://www.youtube.com/")!,
            logoURL: nil,
            logoAssetName: "YouTubeLogo",
            logoText: nil,
            logoHeight: 30
        ),
        AttributionProvider(
            id: "wikimedia",
            name: "Wikidata and Wikipedia",
            shortLabel: "W",
            description: "Original-media and knowledge links use Wikimedia projects and their content licenses.",
            url: URL(string: "https://www.wikidata.org/")!,
            logoURL: nil,
            logoAssetName: nil,
            logoText: nil
        )
    ]
}

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
                        HStack(spacing: 16) {
                            Button("Skip") { model.completeStreamingSetup() }
                                .foregroundStyle(.secondary)
                            Button("Done") { model.completeStreamingSetup() }
                                .fontWeight(.semibold)
                                .foregroundStyle(model.settings.accentColor)
                        }
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

private struct StreamingServicesPicker: View {
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

private struct ServiceIconButton: View {
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
                
                Toggle("Hide from Recommended", isOn: $model.settings.hideShortFilmsFromRecommended)
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

                Toggle("Hide from Recommended", isOn: $model.settings.hideExtrasAndPromosFromRecommended)
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

struct RatingPromptOverlay: ViewModifier {
    @ObservedObject var model: VestigoModel
    var suppressedItemKey: MediaKey?
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if let item = model.pendingRatingPromptItem, item.key != suppressedItemKey {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .transition(.opacity)
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Rate \(item.title)?")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                    
                    Text("This feature can be disabled in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    StarRatingView(rating: $model.pendingRatingPromptValue)
                    
                    Button {
                        model.pendingRatingPromptMakeFavourite.toggle()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: model.pendingRatingPromptMakeFavourite ? "star.fill" : "star")
                                .font(.headline.bold())
                            
                            Text(model.pendingRatingPromptMakeFavourite ? "Make favourite" : "Also make favourite")
                                .font(.headline.bold())
                            
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .liquidGlass(cornerRadius: 22)
                        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    
                    HStack(spacing: 12) {
                        Button("Cancel") {
                            model.dismissPendingRatingPrompt()
                        }
                        .buttonStyle(.plain)
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .liquidGlass(cornerRadius: 22)
                        
                        Button("Confirm") {
                            model.confirmPendingRatingPrompt()
                        }
                        .buttonStyle(.plain)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(model.settings.accentColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
                .padding(18)
                .frame(maxWidth: 360, alignment: .leading)
                .liquidGlass(cornerRadius: 30)
                .padding(.horizontal, 22)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
                .zIndex(50)
            }
        }
        .animation(.smooth(duration: 0.22), value: model.pendingRatingPromptItem?.key)
    }
}

extension View {
    func ratingPromptOverlay(model: VestigoModel, suppressedItemKey: MediaKey? = nil) -> some View {
        modifier(RatingPromptOverlay(model: model, suppressedItemKey: suppressedItemKey))
    }
}

// MARK: - OMDb Usage Bar

struct OMDbUsageBar: View {
    let settings: AppSettings

    private var todayCount: Int {
        let today = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
        return settings.omdbLastRequestDate == today ? settings.omdbDailyRequestCount : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(todayCount.formatted()) calls")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("All time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(settings.omdbTotalRequestCount.formatted()) calls")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Dev Tools

private struct DevToolsPanel: View {
    @ObservedObject var model: VestigoModel
    @State private var isCheckingBackend = false
    @State private var backendResult: String = ""
    @State private var iCloudPushResult: String = ""

    @State private var showLibraryImportPicker = false
    @State private var showSettingsImportPicker = false
    @State private var importResult: String = ""

    @State private var isRestartingConnection = false
    @State private var restartResult: String = ""

    @State private var cerebrasCallCount: Int = 0
    @State private var isLoadingCerebrasUsage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // MARK: Cerebras Usage
            devSectionLabel("Cerebras (Pick For Me)")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Requests used")
                        .font(.subheadline)
                    Spacer()
                    Text("\(cerebrasCallCount)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button(isLoadingCerebrasUsage ? "Loading…" : "Refresh") {
                    fetchCerebrasUsage()
                }
                .font(.caption.bold())
                .foregroundStyle(model.settings.accentColor)
                .disabled(isLoadingCerebrasUsage)
            }
            .settingBubble()
            .onAppear { fetchCerebrasUsage() }

            // MARK: Snapshots
            devSectionLabel("Snapshots")

            VStack(alignment: .leading, spacing: 8) {
                monoBlock("Library", librarySummary)
                Divider().opacity(0.3)
                monoBlock("Caches", cacheSummary)
                Divider().opacity(0.3)
                monoBlock("iCloud", iCloudSummary)
            }
            .settingBubble()

            // MARK: Clipboard
            devSectionLabel("Clipboard")

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button("Copy library JSON") { copyJSON(model.library) }
                    Spacer()
                    Button("Import") { showLibraryImportPicker = true }
                        .foregroundStyle(model.settings.accentColor)
                }
                HStack {
                    Button("Copy settings JSON") { copyJSON(model.settings) }
                    Spacer()
                    Button("Import") { showSettingsImportPicker = true }
                        .foregroundStyle(model.settings.accentColor)
                }
                if !importResult.isEmpty {
                    Text(importResult)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingBubble()

            // MARK: Caches
            devSectionLabel("Caches")

            VStack(alignment: .leading, spacing: 10) {
                cacheRow("Ratings",           count: model.externalRatingsCache.count)  { model.clearExternalRatingsCache() }
                cacheRow("Details",           count: model.detailsCache.count)           { model.detailsCache = [:] }
                cacheRow("Streaming",         count: model.providerCache.count)          { model.providerCache = [:] }
                cacheRow("Related media",     count: model.relatedMediaCache.count)      { model.relatedMediaCache = [:] }
                cacheRow("Person credits",    count: model.personCreditsCache.count)     { model.personCreditsCache = [:] }
                cacheRow("Person details",    count: model.personDetails.count)          { model.personDetails = [:] }
                cacheRow("Collection recs",   count: model.collectionRecommendations.count) { model.collectionRecommendations = [:] }
                cacheRow("Home feed",         count: nil)                                { model.clearHomeFeedCache() }
                cacheRow("Describe It",       count: model.describeItResultsCache.count) { model.clearDescribeItCache() }
                Divider().opacity(0.3)
                Button("Clear all caches") {
                    model.clearAllCaches()
                    model.clearExternalRatingsCache()
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .settingBubble()

            // MARK: Features
            devSectionLabel("Features")

            Toggle("Show cinema showtimes", isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: "Vestigo.showCinemas") },
                set: { UserDefaults.standard.set($0, forKey: "Vestigo.showCinemas") }
            ))
            .font(.headline.bold())
            .tint(model.settings.accentColor)
            .settingBubble()

            // MARK: Actions
            devSectionLabel("Actions")

            Button("Reset OMDb counters") {
                model.resetOMDbCounters()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingBubble()

            VStack(alignment: .leading, spacing: 6) {
                Button("Force iCloud push") {
                    iCloudPushResult = model.forceICloudPush()
                }
                if !iCloudPushResult.isEmpty {
                    Text(iCloudPushResult)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingBubble()

            Button("Simulate first launch") {
                model.simulateFirstLaunch()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingBubble()

            Button("Simulate OMDb limit alert") {
                model.showOMDbLimitAlert = true
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingBubble()



            // MARK: Diagnostics
            devSectionLabel("Diagnostics")

            VStack(alignment: .leading, spacing: 6) {
                Button(isRestartingConnection ? "Restarting…" : "Restart backend connection") {
                    restartBackendConnection()
                }
                .disabled(isRestartingConnection)

                if !restartResult.isEmpty {
                    Text(restartResult)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingBubble()

            VStack(alignment: .leading, spacing: 6) {
                Button(isCheckingBackend ? "Checking…" : "Check backend secrets") {
                    checkBackend()
                }
                .disabled(isCheckingBackend)

                if !backendResult.isEmpty {
                    Text(backendResult)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingBubble()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fileImporter(isPresented: $showLibraryImportPicker, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            importJSON(result: result, as: UserLibrary.self) { model.library = $0 }
        }
        .fileImporter(isPresented: $showSettingsImportPicker, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            importJSON(result: result, as: AppSettings.self) { model.settings = $0 }
        }
    }

    // MARK: Computed summaries

    private var librarySummary: String {
        let l = model.library
        return """
        items:       \(l.items.count)
        watchlist:   \(l.watchlist.count)
        watched:     \(l.watched.count)
        favourites:  \(l.favouriteKeys.count)
        collections: \(l.collections.count)
        neverShow:   \(l.neverShowAgain.count)
        notInterest: \(l.notInterested.count)
        ratings:     \(l.ratings.count)
        """
    }

    private var cacheSummary: String {
        """
        ratings:     \(model.externalRatingsCache.count)
        details:     \(model.detailsCache.count)
        streaming:   \(model.providerCache.count)
        related:     \(model.relatedMediaCache.count)
        people:      \(model.personCreditsCache.count)
        describe it: \(model.describeItResultsCache.count)
        """
    }

    private var iCloudSummary: String {
        let snapshot = Storage.loadKVSnapshot()
        guard let snapshot else { return "No snapshot found" }
        let encoder = JSONEncoder()
        let sizeKB: String
        if let data = try? encoder.encode(snapshot) {
            sizeKB = "\(data.count / 1024) KB"
        } else {
            sizeKB = "unknown"
        }
        let dateStr = snapshot.modifiedAt.formatted(date: .abbreviated, time: .shortened)
        return "Last push: \(dateStr)\nSize:      ~\(sizeKB)"
    }

    // MARK: Helpers

    @ViewBuilder
    private func cacheRow(_ name: String, count: Int?, clear: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(name)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let count {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button("Clear") { clear() }
                .font(.caption.bold())
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func devSectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func monoBlock(_ label: String, _ content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.primary)
            Text(content)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copyJSON<T: Encodable>(_ value: T) {
#if canImport(UIKit)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(value),
           let text = String(data: data, encoding: .utf8) {
            UIPasteboard.general.string = text
        }
#endif
    }

    private func importJSON<T: Decodable>(result: Result<[URL], Error>, as type: T.Type, apply: @escaping (T) -> Void) {
        switch result {
        case .failure(let error):
            importResult = "✗ \(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode(type, from: data)
                apply(decoded)
                importResult = "✓ Imported \(String(describing: type)) at \(Date().formatted(date: .omitted, time: .standard))"
            } catch {
                importResult = "✗ \(error.localizedDescription)"
            }
        }
    }

    private func restartBackendConnection() {
        isRestartingConnection = true
        restartResult = ""
        URLCache.shared.removeAllCachedResponses()
        model.clearAllCaches()
        Task {
            let urlString = "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api/health"
            guard let url = URL(string: urlString) else {
                await MainActor.run { isRestartingConnection = false }
                return
            }
            let start = Date()
            do {
                var req = URLRequest(url: url)
                req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                let (_, response) = try await URLSession.shared.data(for: req)
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                await MainActor.run {
                    restartResult = status == 200 ? "✓ Reconnected (\(ms)ms)" : "⚠ HTTP \(status) (\(ms)ms)"
                    isRestartingConnection = false
                }
            } catch {
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                await MainActor.run {
                    restartResult = "✗ \(error.localizedDescription) (\(ms)ms)"
                    isRestartingConnection = false
                }
            }
        }
    }

    private func fetchCerebrasUsage() {
        isLoadingCerebrasUsage = true
        Task {
            defer { Task { @MainActor in isLoadingCerebrasUsage = false } }
            guard let url = URL(string: "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api/cerebras-usage") else { return }
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            struct Resp: Decodable { let count: Int }
            if let resp = try? JSONDecoder().decode(Resp.self, from: data) {
                await MainActor.run { cerebrasCallCount = resp.count }
            }
        }
    }

    private func checkBackend() {
        let urlString = "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api/secrets-check"
        guard let url = URL(string: urlString) else { return }

        isCheckingBackend = true
        backendResult = ""
        Task {
            defer { Task { @MainActor in isCheckingBackend = false } }
            let start = Date()
            do {
                let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    await MainActor.run {
                        backendResult = "⚠ HTTP \(status) (\(ms)ms)"
                    }
                    return
                }
                let lines = json.sorted(by: { $0.key < $1.key }).compactMap { key, val -> String? in
                    if let dict = val as? [String: Any] {
                        if let present = dict["exists"] as? Bool {
                            return present ? "✓  \(key)" : "✗  \(key)  ← missing"
                        }
                        let inner = dict.sorted(by: { $0.key < $1.key })
                            .map { "\($0.key): \($0.value)" }.joined(separator: ", ")
                        return "\(key): { \(inner) }"
                    } else if let b = val as? Bool {
                        return "\(key): \(b)"
                    } else {
                        return "\(key): \(val)"
                    }
                }
                await MainActor.run {
                    backendResult = lines.joined(separator: "\n") + "\n(\(ms)ms)"
                }
            } catch {
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                await MainActor.run {
                    backendResult = "✗ \(error.localizedDescription) (\(ms)ms)"
                }
            }
        }
    }
}
