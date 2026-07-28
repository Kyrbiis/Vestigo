*This app is vibe-coded in Xcode but all the non-coding aspects of the project were done by humans.
# Vestigo

A personal movie and TV tracker for iOS. Discover what to watch next, track what you've seen, and get recommendations that reflect and watched and rated history.

<br>

## Features

**Discovery**
- Trending, popular, new releases, and upcoming titles
- Personalized *For You* recommendations based on your watch history and ratings
- *Pick For Me* — answer a few questions and get a set of results based on your answers, powered by TMDb and a unique archetype system
- Thematic search (e.g. "Cold War spy thrillers", "feel-good underdog stories") for if you don't know the name of the item you're searching for
- Genre browsing with collections for every genre and franchise

**Tracking**
- Mark movies and series as watched or put them on your watchlist
- Rate what you've seen (1-5)
- Track episode and season progress for TV series
- You can mark items as "not interested" or even "never show again" to avoid seeing results that you don't like

**Organization**
- Custom collections — group titles any way you like or automatically by franchise
- Automatic collection suggestions based on franchises and series you've watched

**Details**
- Cast & crew with person profiles and filmographies
- Streaming availability (where to watch, rent, or buy)
- Trailers
- Original media if applicable

<br>

## Requirements

- iOS 26.0+
- Xcode 24+ (to build from source)

<br>

## Using Vestigo

The first time you open the app, you will be offered the option to select your streaming services and notification preferences. If you change your mind about the statuses of those settings, they can be found anytime in the content and alerts tabs respectively.

Vestigo has five tabs: Home, Search, For You, Watchlist, and Collections. The tab bar hides as you scroll and reappears when you scroll back up. Tapping the active tab a second time returns to the top of that screen; scrolling up from the top refreshes its content.

**Home** is your discovery feed — trending titles, popular picks, new releases, and upcoming films and series. Filter the whole tab to movies, series, or both using the pills at the top. **Search** lets you find titles or people by name, or browse by genre from the empty state. **For You** surfaces personalized recommendations built from your watch history and ratings; the more you log, the better they get. At the bottom of For You is **Pick For Me** — answer a few questions about what you're in the mood for and the app gives a selection of item that fit your requirements. To help get the best results, you can find tips in the top right corner of any Pick For Me question screen.

Tap any poster anywhere in the app to open its detail view, where you can save it to your watchlist, mark it watched, rate it, track episode progress for series, see the full cast and crew, find out where it's streaming, and watch trailers. Long-pressing a poster brings up quick actions without opening the full detail view, as well as the options to mark as not interested or never show again.

**Watchlist** holds everything you've saved. In settings you can configure the behaviour of watched items on your watchlist between being automatically removed from your list or just going to a section of Watchlist named "Watched." **Collections** shows the lists you've created manually, plus franchise and genre groups the app generates automatically as you log more titles. 

**Settings** — can be accessed from the Home tab. There are five main tabs: Content, Display, Alerts, Data, and About. The content tab has the following settings: the ability to change your streaming services, the ability to change whether the app uses IMDb or TMDb depending on if you have an OMDb API key configured, the option to prioritise English content, the option to hide explicit results, the option to hide anime, the option to reduce kids or family items, the option to hide watched items from results, the option to hide short films, the option to hide extras and promos, the option to hide upcoming releases, the aforementioned  watchlist configuration, the option to turn off the prompt to rate an item after it is marked as watched, and the default filters for each tab. Keep in mind that turning on the content filters (hide explicit, anime, child focused, short films, extras and promos results) may also hide items that are adjacent but not considered part of the hidden category. The display tab allows you to change between light and dark modes, set the background colour, and change the order of the content carousels in the Home and For You tabs. the alerts tab is notification settings. The data tab is where you can export and import your watched data as a .csv or .txt, review the items marked as not interested or never show again, and reset your settings and data. The about tab is information about the app, primarily attributions to the sources of data that make it function. in addition, there is a hidden developer tab that can be accessed from the about tab by tapping the Vestigo title seven times. The developer tab contains information about the backend and your app caches.

## Installation

**TestFlight** — public beta coming soon.

**Build from source** — clone the repo, open `Vestigo.xcodeproj` in Xcode, and run on a simulator or device. You will need a [TMDb API key](https://developer.themoviedb.org/docs/getting-started) and optionally, an [OMDb API key](https://www.omdbapi.com/apikey.aspx) for IMDb ratings. Add these in the app's Settings tab.

<br>

## Attributions

This product uses the TMDB API but is not endorsed or certified by TMDB.
Streaming availability and provider data are in part provided by Watchmode.
Series, season, episode, and franchise data are provided in part by The TVDB.
This product uses the OMDb API but is not endorsed or certified by OMDb or IMDb. Ratings and movie data are provided in part by The Open Movie Database and IMDb.
Trailer playback uses embedded YouTube videos where available.
Original media and knowledge links use Wikimedia projects and their content licences.

<br>

While the app is free, it is also going to stay free for me so users will need to get their own OMDb key. If the app becomes successful in the future, I will add a paid one to the backend.

<br>

## License

MIT
