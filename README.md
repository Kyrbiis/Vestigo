# Vestigo

A personal movie and TV tracker for iOS. Discover what to watch next, track what you've seen, and get recommendations that actually reflect your taste.

<br>

## Features

**Discovery**
- Trending, popular, new releases, and upcoming titles
- Personalized *For You* recommendations based on your watch history and ratings
- *Pick For Me* — answer a few mood questions and get a curated pick with AI reasoning
- Thematic search (e.g. "Cold War spy thrillers", "feel-good underdog stories")
- Genre browsing with curated genre tiles

**Tracking**
- Mark movies and series as watched
- Rate what you've seen (1–10)
- Track episode and season progress for TV series
- Watchlist for saving titles to watch later

**Organization**
- Custom collections — group titles any way you like
- Automatic collection suggestions based on franchises and series you've watched

**Details**
- Cast & crew with person profiles and filmographies
- Streaming availability (where to watch, rent, or buy)
- Trailers
- Showtimes at nearby AMC theatres

**Settings**
- IMDb or TMDb ratings (IMDb requires a free OMDb API key)
- Carousel customization — reorder and hide For You and Home sections
- Content filters: hide anime, adult content, short films, upcoming releases
- Appearance: dark/light mode, accent color, plain background mode
- iCloud sync for library data and settings

<br>

## Requirements

- iOS 18.0+
- Xcode 16+ (to build from source)

<br>

## Installation

**TestFlight** — public beta coming soon.

**Build from source** — clone the repo, open `Vestigo.xcodeproj` in Xcode, and run on a simulator or device. You will need a [TMDb API key](https://developer.themoviedb.org/docs/getting-started) and, optionally, an [OMDb API key](https://www.omdbapi.com/apikey.aspx) for IMDb ratings. Add these in the app's Settings tab.

<br>

## Tech

- **SwiftUI** — native UI throughout
- **TMDb API** — metadata, discovery, search, cast, trailers, ratings
- **OMDb API** — IMDb ratings (optional, user-supplied key)
- **Streaming Availability API by Movie of the Night** — where to watch
- **Groq** — AI reasoning for Pick For Me

<br>

## Attributions

This product uses the TMDB API but is not endorsed or certified by TMDB.

Streaming availability data is provided by [Streaming Availability API by Movie of the Night](https://www.movieofthenight.com/about/api).

<br>

## License

MIT
