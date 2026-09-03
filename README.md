*This app is vibe-coded in Xcode but all the non-coding aspects of the project were done by humans.
# Vestigo

A personal movie and TV tracker for iOS. Discover what to watch next, track what you've seen, and get recommendations that reflect your watched and rated history.

<br>

## Features

**Discovery**
- Trending, popular, new releases, and upcoming titles
- Personalized *For You* recommendations based on your watch history and ratings
- *More like* carousels based on your most recently watched title and top favourites
- *From your watchlist* and *Continue with related series* carousels
- *Pick For Me* — answer a few questions and get a set of results based on your answers, powered by TMDb and a unique archetype system
- *Describe It* — thematic search (e.g. "Cold War spy thrillers", "feel-good underdog stories") for when you don't know the name of what you're looking for, powered by AI
- Genre browsing with collections for every genre and franchise

**Tracking**
- Mark movies and series as watched or put them on your watchlist
- Rate what you've seen (1–5, supports half-star increments)
- Track watch dates manually, or enable automatic date recording when marking something watched
- Track episode and season progress for TV series
- Mark items as "not interested" or "never show again" to stop seeing results you don't want

**Organization**
- Custom collections — group titles any way you like or automatically by franchise
- Automatic collection suggestions based on franchises and series you've watched

**Details**
- Cast & crew with person profiles and filmographies
- Trailers
- Streaming availability with prices and direct links to streaming apps where available
- Original media if applicable

**Friends**
- Add friends via invite link or QR code — no account or phone number required
- Me view with profile avatar, Featured picks (editable), and Excited For upcoming releases
- Share your watchlist and watched history with friends, or keep everything private (sharing is off by default)
- View friends' profiles, featured picks, and shared libraries
- Mutual friend adds — accepting a link or QR code automatically creates the friendship on both sides
- Removing a friend notifies them and removes the friendship on their side too

<br>

## Requirements

- iOS 26.0+
- Xcode 24+ (to build from source)

<br>

## Using Vestigo

The first time you open the app, you will be offered the option to select your streaming services. If you change your mind, this can be found anytime in the Content tab of Settings.

Vestigo has five tabs: Home, Search, Watchlist, Collections, and Friends. The tab bar hides as you scroll and reappears when you scroll back up. Tapping the active tab a second time returns to the top of that screen; scrolling up from the top refreshes its content.

**Home** is your discovery feed — trending titles, personalized For You recommendations, new releases, and upcoming films and series. Filter the whole tab to movies, series, or both using the pills at the top. The For You recommendations carousel sits between Trending and New Releases by default. At the bottom of Home is **Pick For Me** — answer a few questions about what you're in the mood for and the app gives a selection of items that fit your requirements. To help get the best results, you can find tips in the top right corner of any Pick For Me question screen. **Search** lets you find titles or people by name, or browse by genre from the empty state. **Describe It** is also accessible from Search — type a natural language description of what you want to watch and the app uses AI to surface matching titles.

Tap any poster anywhere in the app to open its detail view, where you can save it to your watchlist, mark it watched, rate it, track episode progress for series, see the full cast and crew, find out where it's streaming, and watch trailers. Long-pressing a poster brings up quick actions without opening the full detail view, as well as the options to mark as not interested or never show again.

**Watchlist** holds everything you've saved. In settings you can configure the behaviour of watched items on your watchlist between being automatically removed from your list or just going to a section of Watchlist named "Watched." **Collections** shows the lists you've created manually, plus franchise and genre groups the app generates automatically as you log more titles.

**Friends** is a social tab built on invite links and QR codes — no account or phone number required. The **Me** view shows your profile, your **Featured** picks (your top favourites by default, editable with the pencil icon), and an **Excited For** section for upcoming releases you're looking forward to — items automatically expire from this list once they're released. You can choose to share your watchlist, your watched history, or keep everything private. The **Friends** view lists your added friends ordered by recent activity. Tap the + button to share an invite link or show your QR code; when someone scans or taps it both sides are added as friends automatically. Tapping a friend opens their profile with featured picks and, if they've chosen to share, their watchlist and watched history. Long-pressing a friend in the list lets you remove them — the removal is reflected on both sides with a notification alert.

**Settings** — can be accessed from the Home tab. There are four main tabs: Content, Display, Data, and About. The content tab has the following settings: the ability to change your streaming services, the ability to change whether the app uses IMDb or TMDb ratings depending on if you have an OMDb API key configured, the option to prioritise English content, the option to hide explicit results, the option to hide anime, the option to reduce kids or family items, the option to hide watched items from results, the option to hide short films, the option to hide extras and promos, the option to hide upcoming releases, the aforementioned watchlist configuration, the option to turn off the prompt to rate an item after it is marked as watched, the option to control whether watch dates are tracked automatically or set manually, and the default filters for each tab. Keep in mind that turning on the content filters may also hide items that are adjacent but not considered part of the hidden category. The display tab allows you to change between light and dark modes, set the background colour, and change the order of the content carousels in the Home tab (including the For You recommendations carousel and its sub-carousels). The data tab is where you can export and import your watched data as a .csv or .txt, review the items marked as not interested or never show again, clear caches, and reset your settings and data. The Clear caches button frees up storage used by temporarily saved data such as ratings, streaming availability, and search results — your watchlist, watched history, ratings, and collections are not affected. The about tab is information about the app, primarily attributions to the sources of data that make it function. The import function supports Letterboxd-style .csv imports as well to make it easy to move your data to Vestigo. To help with getting the correct titles into your library, if the app cannot find an item from the import list it will ask you to choose the correct one manually, so adding more details is better. In addition, there is a hidden developer tab that can be accessed from the About tab by tapping the Vestigo title seven times. The developer tab shows backend status and a detailed breakdown of every app cache — Ratings, Details, Streaming availability, Related media, Person credits, Person details, Collection recommendations, Home feed, and Describe It results — with individual or bulk clear buttons for each. Caches are temporary data that speed up the app by avoiding repeated network fetches; clearing them frees up storage without removing any of your personal data (watchlist, watched history, ratings, and collections are completely unaffected).

## Installation

**TestFlight** — https://testflight.apple.com/join/zbvP2WEx.

**Build from source** — clone the repo, open `Vestigo.xcodeproj` in Xcode, and run on a simulator or device. No API keys are required — the app connects to the same shared backend as the distributed version. Optionally, add an [OMDb API key](https://www.omdbapi.com/apikey.aspx) in Settings to enable IMDb ratings.

<br>

## Attributions

This product uses the TMDB API but is not endorsed or certified by TMDB.
Streaming availability and provider data are in part provided by Watchmode.
Series, season, episode, and franchise data are provided in part by The TVDB.
This product uses the OMDb API but is not endorsed or certified by OMDb or IMDb. Ratings and movie data are provided in part by The Open Movie Database and IMDb.
Trailer playback uses embedded YouTube videos where available.
Streaming service brand logos and assets are powered by Brandfetch.
Original media and knowledge links use Wikimedia projects and their content licences.

<br>

While the app is free, it is also going to stay free for me so users will need to get their own OMDb key. If the app becomes successful in the future, I will add a paid one to the backend.

<br>

## License

MIT
