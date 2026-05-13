*THIS APP IS VIBE-CODED IN XCODE USING CHATGPT PLUS

# Vestigo

Vestigo is an iOS movie and series tracking app built in SwiftUI. It started as GlassWatch and was later renamed to Vestigo. The app is designed to combine movie and TV discovery, search, watchlist management, watched-history tracking, ratings, collections, streaming availability, and personalized recommendations into one clean iOS app.

Vestigo uses TMDb for movie, series, person, cast, crew, genre, rating, runtime, release-date, and recommendation metadata. It also uses Movie of the Night’s Streaming Availability API for provider availability, so the app can show where a movie or series is available to stream, rent, or buy when that data is available.

The app is currently in active development. The main app structure is functional: Home, Search, Watchlist, Collections, Settings, detail sheets, people detail sheets, local library storage, watched tracking, ratings, recommendations, and provider lookup are all implemented or partially implemented.

---

## Overview

Vestigo is organized around five main tabs:

- Home
- Search
- Watchlist
- Collections
- Settings

The app uses a native SwiftUI `TabView`, not the old custom tab bar. The tab bar uses the system iOS glass/liquid behavior and supports `.tabBarMinimizeBehavior(.onScrollDown)` on iOS. The selected-tab retap behavior has also been added: tapping a different tab switches normally, tapping the current tab while not at root returns that tab to root, and tapping the current tab while already at root reloads or resets that tab.

The app uses a shared visual system based around `AppBackground`, `BaseScreen`, `liquidGlass(...)`, and `sheetLiquidGlass(...)`. This gives Home, Search, Watchlist, Collections, and Settings the same background behavior and keeps the UI consistent across tabs. Settings also includes a plain black/white background toggle for a simpler background mode.

Most of the app is currently concentrated in `ContentView.swift`. The major model/controller object is `VestigoModel`, an `ObservableObject` that stores app state, handles loading data, manages user library data, performs search, loads details, updates settings, and coordinates navigation.

---

## Home

The Home tab is the main discovery screen. It currently includes sections for recommendations, trending titles, popular titles, new releases, and upcoming releases.

The Home filter supports:

- Movies
- Series
- Both

The default Home filter can be configured in Settings. Home reloads based on the active media filter and uses `TMDbService` to fetch the relevant content.

Upcoming releases have special filtering because the TMDb upcoming endpoint can sometimes return stale or old titles. Vestigo now treats a title as actually upcoming only if it is returned by TMDb’s upcoming endpoint and has a release date after today. Items with missing release dates are excluded from the Upcoming carousel. This keeps the Upcoming section from showing movies that were released a long time ago.

Home also respects several user settings, including hiding watched items from Home, prioritizing English-language results, hiding anime-like results, hiding adult/explicit results where the API supports it, and showing or hiding Upcoming releases.

Recommendations are generated from watched history. They appear only after the user has marked enough items as watched. The recommendation system uses the user’s watched items, ratings, genre overlap, TMDb recommendation results, and a configurable Recommendation Strength setting to score candidate recommendations. Higher strength leans more heavily on highly rated watched items, while lower strength uses a broader range of watched history. Watched-but-unrated items still contribute, but their weight changes based on recommendation strength. Low-rated watched items can reduce scores for related recommendations. Already watched items are excluded from recommendation results.

---

## Search

The Search tab supports searching for movies, series, and people. Search uses its own filter type, `SearchFilter`, rather than the Home `MediaFilter`.

Search filter options are:

- Movies
- Series
- People

Search intentionally does not include a “Both” option. People search is separate from media search and returns person rows instead of media tiles.

Search includes a search field, search history, genre browsing tiles, result display, and a collapsible filter panel for media searches. Search results can be shown as movie/series grids or people result rows depending on the selected search type.

The Search input has been adjusted so submitted text, accepted predictive/autofill text, and focus loss should commit the input before running search. The `commitSearchInput()` helper trims the query, saves it to search history, clears focus, and calls `model.updateSearch()`. This is meant to make iOS keyboard suggestions behave correctly with the app’s search system.

Search history stores recent non-empty searches, moves repeated searches to the front, and caps the list to a small number of entries.

For media search, Vestigo combines exact/similar TMDb search results with contextual search results, deduplicates them, sorts them by relevance, and then applies app-level filters. For People search, Vestigo calls TMDb people search and displays people-specific rows.

Search currently includes filter sections for runtime, TMDb rating, and release-date ranges. Runtime filters include ranges such as under 1 hour, 1 to 1.5 hours, 1.5 to 2 hours, 2 to 2.5 hours, 2.5 to 3 hours, and over 3 hours. Rating filters use TMDb rating thresholds, and date filters support broad release-date windows.

A known structural limitation is that runtime/date/rating filtering currently works best after a text search. The next major Search improvement should be blank search with active filters, so the user can browse filtered results without typing a query. This will also support future genre filtering inside the Search filter panel.

Search can also browse genres from the empty-search state. Tapping a genre opens a genre/category results screen using the Search navigation stack.

---

## Genre and Category Browsing

Genre browsing exists through Search. The empty Search screen shows genre tiles, and tapping a genre opens a `GenreResultsView`.

Genre result pages support:

- Movie / Series / Both filtering
- Category sorting
- Media grid/list display
- Watched filtering based on settings

Category sorting currently supports sorting by TMDb rating or release date. The default category sort can be configured in Settings. Genre cache keys include the genre ID, media filter, and sort mode so results stay separated correctly.

The current category system still needs a larger redesign. Planned future categories include Documentary, Based on a true story, Book adaptation, Game adaptation, Romance, and Anime. The intended future direction is to stop relying on static curated lists and make categories query/config driven, with large result pools and cleaner primary-category assignment. The Anime category should eventually bypass the global Hide anime setting.

---

## Detail Views

Tapping a movie or series opens a detail sheet. Detail sheets use a custom translucent glass surface with rounded corners. The app uses `sheetLiquidGlass(...)` for these sheets instead of the normal stronger `liquidGlass(...)` used for smaller UI bubbles. This avoids the heavy grey backing that previously made detail popups hard to distinguish from the background.

Detail views currently show:

- Poster
- Title
- Metadata line
- Runtime when available
- TMDb rating
- Age rating
- Release date or air date
- Director or creator
- Overview
- Save button
- Watched button when allowed
- Rating controls after marking watched
- Cast/crew section
- Episode/season progress for series
- Similar or related titles
- Streaming provider availability

Movies can show runtime in the metadata line. Series can show season runtime when episode runtime data exists. If runtime is unknown, the app avoids showing placeholder text like “runtime unknown.”

Ratings are gated behind watched status. The user cannot rate an item unless it has been marked watched. If an item is not watched, the rating UI is not shown.

Upcoming items are treated specially. Upcoming titles should not show watched buttons or watched context-menu actions. The app preserves logic such as `hideWatchedForUpcoming: true` and checks like `if !item.isUpcoming` so unreleased titles are not treated like normal watched-trackable media.

Detail sheets include provider information from the Streaming Availability API where available. If provider pricing or buy/rent information is unavailable, the UI should avoid showing misleading placeholder fields.

---

## People and Cast/Crew

Vestigo supports people search and cast/crew navigation.

People can be opened from:

- Search results
- Cast carousel
- Crew/director/creator rows
- Known-for credits

The app uses a unified person navigation model through `model.selectedPerson = person`. The goal is to avoid multiple separate person-navigation systems.

Person detail views include:

- Profile image
- Name
- Biography
- Known-for credits
- Sorting by rating
- Sorting by date

People search result rows show the person image, name, known-for department or role, a chevron, and glass row styling. If no people match the search, the app shows a clear empty state.

Cast and crew are shown in a carousel format, with actor/crew image, name, and role. Directors and other significant production people are meant to be reachable through the same person-detail flow.

---

## Watchlist

The Watchlist tab stores saved movies and series.

Watchlist items can be sorted and displayed using the app’s media grid/list components. Items are split into watched and unwatched sections.

The Watchlist behavior depends on the setting “Remove items from watchlist”:

- If enabled, marking a saved item as watched removes it from Watchlist.
- If disabled, watched saved items remain in Watchlist under the Watched section.

Saved and watched icons fill when active. Saved items use `bookmark.fill`, and watched items use `checkmark.circle.fill`.

Long-press context menus are available on media poster tiles. These menus can include actions such as Add to collection, Save or remove saved, Mark watched or unwatched, and Remove from collection depending on context. Upcoming items should not offer Mark watched.

---

## Collections

Collections let the user organize media manually and dynamically.

The Collections tab supports creating new collections and opening collection detail views. Collection detail views display the collection’s items and support sorting. Items can be added to collections through context menus and collection sheets.

Vestigo also generates dynamic collections from watched history. When the user marks items watched, the app can infer collection names from broad groupings or franchises and add relevant items to those collections. This is intended to make collections feel automatic when the user watches several entries from the same series or universe.

Collections use the same background and glass UI system as the rest of the app.

---

## Watched Tracking and Ratings

Vestigo tracks watched status for both movies and series.

For movies, the user can mark watched/unwatched and rate the item after marking it watched.

For series, the app supports episode progress. The user can toggle individual episodes and mark seasons watched. Season headers can display total runtime when episode runtime data exists.

Ratings are stored in the user library and affect recommendations. A user rating only matters if the item is watched. Attempting to set a rating for an unwatched item is ignored.

Watched items are stored locally in `UserLibrary`, along with ratings, watchlist entries, collections, and episode progress.

---

## Settings

The Settings tab is organized into sections:

- Display
- Interaction
- Content
- Data
- Attributions

Settings are presented as individual glass bubbles rather than old grouped panels. The old `SettingsPanel` helper was removed.

Display settings include Dark Mode, plain black/white background, and accent colour. The plain background mode gives a simple black background in dark mode and white background in light mode, without overriding the selected accent colour.

Interaction settings currently include a Haptics toggle. The setting exists, but actual haptic events still need to be wired into actions such as tab switching, save/remove saved, mark watched/unwatched, add to collection, filter selection, and rating changes.

Content settings include recommendation strength, prioritizing English, hiding adult/explicit results, hiding anime, hiding watched results from Home/Search, removing watched items from Watchlist, showing upcoming releases, default Home filter, default Search type, and default Category sort.

Data settings include importing watched titles, exporting watched data, resetting settings, and clearing all app data. The Import as watched UI groups the text field and import button into one shared bubble, with the text field itself inside an inset bubble. Export watched data is a compact aligned button row.

Attributions are shown at the bottom of Settings for TMDb and Movie of the Night’s Streaming Availability API.

---

## Data and Persistence

Vestigo stores local user data using a `Storage` helper.

Saved data includes:

- Watched items
- Ratings
- Watchlist
- Collections
- Episode progress
- Settings

The main user data container is `UserLibrary`. Settings are stored in `AppSettings`.

The model loads local data during bootstrap, then loads Home data. Local data is saved after changes, with some saves delayed through `saveLocalSoon()` to avoid unnecessary immediate writes.

`clearAllData()` resets the user library and settings, clears selected paths and search state, saves the cleared data, and reloads Home.

---

## App Model

Most app state lives in `VestigoModel`.

Important published state includes:

- Selected tab
- Media filter
- Home view mode
- Search view mode
- Watchlist view mode
- Collection view mode
- Search filters
- Search text
- Trending results
- Popular results
- New releases
- Upcoming releases
- Recommendations
- Search results
- People search results
- Genre results
- Detail cache
- Provider cache
- Person credits cache
- User library
- Settings
- Selected item sheet
- Selected person sheet
- Home navigation path
- Search navigation path
- Loading state
- Error text
- Export document state

The model handles bootstrapping, Home loading, recommendation loading, search updating, runtime enrichment, genre loading, detail loading, person credit loading, watchlist toggling, watched toggling, ratings, episode tracking, collection changes, import/export, local saving/loading, tab switching, tab reselection, root reset, and reload behavior.

---

## Navigation

Vestigo uses native `NavigationStack` for Home and Search.

Home uses:

- `homePath: [SectionRoute]`

Search uses:

- `searchPath: [GenreRoute]`

Sheets are used for details and person views through:

- `selectedItem: MediaItem?`
- `selectedPerson: PersonSummary?`

The selected-tab retap system uses `TabBarRetapObserver`, a small UIKit bridge around `UITabBarControllerDelegate`. This is needed because SwiftUI’s `TabView(selection:)` does not reliably trigger the selection binding when the user taps the currently selected tab.

Tab retap behavior is:

- If the user taps a different tab, switch normally.
- If the user taps the current tab while not at root, reset that tab to root.
- If the user taps the current tab while already at root, reload or reset that tab.

Home root reload resets the Home filter to the default Home filter, resets Home view mode, clears the Home path, and reloads Home data.

Search root reset clears the Search path, clears query/results, clears people results, collapses filters, clears active filters, resets the minimum TMDb rating filter to default, and restores the default Search type.

---

## Scrolling and Gesture Behavior

Scrolling was one of the most important device-specific fixes.

The app previously had inconsistent one-finger scrolling on iPhone. Light scrolls were unreliable, while two-finger scrolling worked more consistently. The behavior also happened on empty tabs, so it was not only caused by poster tiles or carousel items.

The main cause was gesture competition. A global/high-priority full-screen edge-back drag gesture was competing with native `ScrollView` gestures. Removing that gesture fixed the main problem.

The current scrolling setup uses ordinary SwiftUI `ScrollView`s and a small `ScrollViewTouchTuningView` helper that configures the underlying `UIScrollView`. Vertical scroll views are tuned as vertical scroll views, while horizontal carousels are tuned as horizontal scroll views.

Horizontal carousels intentionally keep `.scrollClipDisabled()` because the design shows a small peek of the next poster on the right. When `.scrollClipDisabled(false)` was applied to horizontal carousels, the right-side poster peek was clipped. Restoring `.scrollClipDisabled()` fixed the visual issue.

There is still a small amount of horizontal drift on the main page, but it snaps back quickly and is acceptable for now. The important rule is not to restore a full-screen high-priority drag gesture. If edge-back navigation returns in the future, it should be implemented with a narrow edge-only approach that does not compete with scroll gestures.

Keyboard dismissal now uses scroll-view behavior rather than a custom full-screen drag. This avoids adding another gesture recognizer that could interfere with scrolling.

---

## API Integration

Vestigo uses TMDb for metadata and discovery.

TMDb-backed features include:

- Trending
- Popular
- New releases
- Upcoming releases
- Search
- People search
- Genre discovery
- Movie detail
- Series detail
- Runtime
- Age rating
- Cast and crew
- Person credits
- Recommendations
- Related or similar titles

Vestigo uses Movie of the Night’s Streaming Availability API for streaming provider availability.

The app currently includes text attribution for both services in Settings.

TMDb attribution shown in-app:

> This product uses the TMDB API but is not endorsed or certified by TMDB.

Movie of the Night attribution shown in-app:

> Streaming availability information is provided by Streaming Availability API by Movie of the Night.

The exact official attribution/logo requirements should be verified before public release or TestFlight distribution.

---

## Filtering Preferences

Vestigo includes several content filtering preferences.

Prioritise English sorts English-language titles first when otherwise similar results are available.

Hide adult/explicit results controls TMDb’s `include_adult` behavior where the API path supports it. The important inversion is that `includeAdult` should be set to `!settings.hideAdultResults`. People search no longer sends duplicate adult-filter parameters. Some discover/category paths may still need verification.

Hide anime currently uses a rough filter based on animation genre ID and anime-related keywords. This is not perfect because TMDb genre ID 16 means Animation, not strictly anime. A future version should use better signals such as origin country, original language, keywords, and maybe TMDb-specific anime classification strategies. A dedicated Anime category should bypass the global Hide anime setting.

Hide watched results can be configured separately for Home and Search. Watchlist and Collections should not be affected by hide-watched search/home settings.

---

## Error Handling

Vestigo includes `LoadErrorFilter.shouldIgnore(error)` to suppress harmless/cancelled load errors.

This prevents visible error banners from being shown for cancelled async operations or other harmless interrupted loads. `loadHome()` and `updateSearch()` use this filter before setting `errorText`.

A possible future improvement is to only show Home load errors when all major Home sections are empty or when visible content is actually affected. A failed refresh should ideally not wipe or hide existing content.
