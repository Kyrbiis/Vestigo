function normalizeAMCFormat(raw: string | null): string | null {
  if (!raw) return null
  const s = raw.toLowerCase()
  if (s.includes("imax")) return "IMAX"
  if (s.includes("dolby")) return "Dolby Cinema"
  if (s.includes("plf") || s.includes("premium large")) return "PLF"
  if (s.includes("laser")) return "Laser at AMC"
  if (s.includes("3d")) return "3D"
  if (s.includes("dine") || s.includes("fork")) return "Dine-In"
  if (s === "standard" || s === "digital") return null
  return raw
}

function normalizeTitle(value: string) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
}

function matchScore(name: string, query: string) {
  const normalizedName = normalizeTitle(name)
  const normalizedQuery = normalizeTitle(query)

  if (normalizedName === normalizedQuery) return 100
  if (normalizedName.includes(normalizedQuery)) return 75
  if (normalizedQuery.includes(normalizedName)) return 60
  return 0
}

function previewSecret(name: string) {
  const value = Deno.env.get(name)

  return {
    exists: Boolean(value)
  }
}

async function fetchWithTimeout(url: URL | string, init: RequestInit = {}, timeoutMilliseconds = 8000) {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), timeoutMilliseconds)

  try {
    return await fetch(url, {
      ...init,
      signal: controller.signal
    })
  } finally {
    clearTimeout(timeout)
  }
}

function tmdbVoteAverage(result: any) {
  return typeof result?.vote_average === "number" ? result.vote_average : 0
}

function itemTitle(result: any, kind: "movie" | "tv") {
  return kind === "movie"
    ? result.title ?? result.original_title ?? "Untitled"
    : result.name ?? result.original_name ?? "Untitled"
}

function itemReleaseDate(result: any, kind: "movie" | "tv") {
  return kind === "movie"
    ? result.release_date ?? null
    : result.first_air_date ?? null
}

function releaseYear(value: unknown) {
  if (typeof value !== "string" || value.length < 4) return null
  const year = Number(value.slice(0, 4))
  return Number.isFinite(year) && year > 0 ? String(year) : null
}

function tmdbMovieDTO(result: any) {
  const title = itemTitle(result, "movie")

  return {
    id: result.id,
    kind: "movie",
    title,
    overview: result.overview ?? "",
    posterPath: result.poster_path ?? null,
    backdropPath: result.backdrop_path ?? null,
    releaseDate: itemReleaseDate(result, "movie"),
    voteAverage: tmdbVoteAverage(result),
    genreIDs: Array.isArray(result.genre_ids) ? result.genre_ids : [],
    originalLanguage: result.original_language ?? null
  }
}

function tmdbTVDTO(result: any) {
  const title = itemTitle(result, "tv")

  return {
    id: result.id,
    kind: "tv",
    title,
    overview: result.overview ?? "",
    posterPath: result.poster_path ?? null,
    backdropPath: result.backdrop_path ?? null,
    releaseDate: itemReleaseDate(result, "tv"),
    voteAverage: tmdbVoteAverage(result),
    genreIDs: Array.isArray(result.genre_ids) ? result.genre_ids : [],
    originalLanguage: result.original_language ?? null
  }
}

async function fetchTMDb(path: string, params: Record<string, string> = {}) {
  const tmdbKey = Deno.env.get("TMDB_API_KEY")

  if (!tmdbKey) {
    throw new Error("Missing TMDB_API_KEY")
  }

  const url = new URL(`https://api.themoviedb.org/3${path}`)
  url.searchParams.set("api_key", tmdbKey)
  url.searchParams.set("language", "en-US")

  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value)
  }

  const response = await fetchWithTimeout(url)

  if (!response.ok) {
    const text = await response.text()
    throw new Error(`TMDb request failed: ${response.status} ${text}`)
  }

  return await response.json()
}

function isAllowedTMDbProxyPath(path: string) {
  if (!path.startsWith("/")) return false
  if (path.includes("..")) return false

  return [
    /^\/trending\/(all|movie|tv)\/(day|week)$/,
    /^\/movie\/(popular|now_playing|upcoming)$/,
    /^\/tv\/(popular|on_the_air|airing_today)$/,
    /^\/search\/(multi|movie|tv|person)$/,
    /^\/discover\/(movie|tv)$/,
    /^\/movie\/\d+\/(recommendations|similar|external_ids|release_dates|keywords)$/,
    /^\/tv\/\d+\/(recommendations|similar|external_ids|content_ratings|keywords)$/,
    /^\/movie\/\d+$/,
    /^\/tv\/\d+$/,
    /^\/tv\/\d+\/season\/\d+$/,
    /^\/person\/\d+$/,
    /^\/person\/\d+\/combined_credits$/
  ].some((pattern) => pattern.test(path))
}

async function tmdbProxy(path: string, params: URLSearchParams) {
  if (!isAllowedTMDbProxyPath(path)) {
    throw new Error("TMDb proxy path is not allowed")
  }

  const forwardedParams: Record<string, string> = {}
  const blockedParams = new Set(["api_key", "path"])

  for (const [key, value] of params.entries()) {
    if (!blockedParams.has(key)) {
      forwardedParams[key] = value
    }
  }

  return await fetchTMDb(path, forwardedParams)
}

async function tasteDiveSimilar(query: string, type: string, limit: string) {
  const tasteDiveKey = Deno.env.get("TASTEDIVE_API_KEY")

  if (!tasteDiveKey) {
    throw new Error("Missing TASTEDIVE_API_KEY")
  }

  const normalizedType = type === "show" ? "show" : "movie"
  const url = new URL("https://tastedive.com/api/similar")
  url.searchParams.set("q", query)
  url.searchParams.set("type", normalizedType)
  url.searchParams.set("limit", limit)
  url.searchParams.set("k", tasteDiveKey)

  const response = await fetchWithTimeout(url)

  if (!response.ok) {
    const text = await response.text()
    throw new Error(`TasteDive request failed: ${response.status} ${text}`)
  }

  const data = await response.json()
  const results = Array.isArray(data?.Similar?.Results) ? data.Similar.Results : []

  return results
    .filter((result: any) => result?.Type === normalizedType)
    .map((result: any) => String(result?.Name ?? "").trim())
    .filter((name: string) => name.length > 0)
}

async function fetchOMDb(params: Record<string, string>, userKeys: string[]) {
  const keys = userKeys
    .map((k, i) => ({ key: k.trim(), label: i === 0 ? "user-primary" : "user-backup" }))
    .filter(a => a.key.length > 0)

  if (keys.length === 0) {
    return null
  }

  let rateLimitError: string | null = null

  for (const attempt of keys) {
    const url = new URL("https://www.omdbapi.com/")
    url.searchParams.set("apikey", attempt.key)

    for (const [key, value] of Object.entries(params)) {
      if (value.trim().length > 0) {
        url.searchParams.set(key, value)
      }
    }

    const response = await fetchWithTimeout(url)

    if (!response.ok) {
      const text = await response.text()
      const loweredText = text.toLowerCase()

      if (loweredText.includes("request limit reached")) {
        rateLimitError = `OMDb request limit reached for ${attempt.label}`
        continue
      }

      throw new Error(`OMDb request failed for ${attempt.label}: ${response.status} ${text}`)
    }

    const data = await response.json()
    const errorText = String(data?.Error ?? "")

    if (data?.Response === "False" && errorText.toLowerCase().includes("request limit reached")) {
      rateLimitError = `OMDb request limit reached for ${attempt.label}`
      continue
    }

    if (data?.Response === "False") return null

    return data
  }

  throw new Error(rateLimitError ?? "No valid OMDb key provided")
}

function parseOMDbNumber(value: unknown) {
  if (typeof value !== "string" || value === "N/A") return null
  const parsed = Number(value.replace(/,/g, ""))
  return Number.isFinite(parsed) ? parsed : null
}

function parseRottenTomatoes(value: unknown) {
  if (typeof value !== "string" || value === "N/A") return null
  const parsed = Number(value.replace("%", ""))
  return Number.isFinite(parsed) ? parsed : null
}

function normalizeOMDbRatings(data: any) {
  if (!data) return null

  const rottenTomatoesText = Array.isArray(data.Ratings)
    ? data.Ratings.find((rating: any) => rating?.Source === "Rotten Tomatoes")?.Value ?? null
    : null

  return {
    imdbID: typeof data.imdbID === "string" && data.imdbID !== "N/A" ? data.imdbID : null,
    imdbRating: parseOMDbNumber(data.imdbRating),
    imdbVotes: typeof data.imdbVotes === "string" && data.imdbVotes !== "N/A" ? data.imdbVotes : null,
    rottenTomatoesRating: parseRottenTomatoes(rottenTomatoesText),
    rottenTomatoesText
  }
}

async function omdbRatingsForTMDbID(tmdbID: number, kind: "movie" | "tv", title: string | null, year: string | null = null, userKeys: string[] = []) {
  if (userKeys.filter(k => k.trim().length > 0).length === 0) return null

  let imdbID: string | null = null

  try {
    const externalIDs = await fetchTMDb(`/${kind}/${tmdbID}/external_ids`)
    const rawIMDbID = String(externalIDs?.imdb_id ?? "").trim()
    imdbID = rawIMDbID.length > 0 ? rawIMDbID : null
  } catch {
    imdbID = null
  }

  if (imdbID) {
    const data = await fetchOMDb({ i: imdbID, plot: "short" }, userKeys)
    const ratings = normalizeOMDbRatings(data)
    if (ratings?.imdbRating || ratings?.rottenTomatoesRating || ratings?.rottenTomatoesText) {
      return ratings
    }
  }

  if (title && title.trim().length > 0) {
    const baseParams = {
      t: title,
      type: kind === "movie" ? "movie" : "series",
      plot: "short"
    }

    const attempts = year
      ? [{ ...baseParams, y: year }, baseParams]
      : [baseParams]

    for (const params of attempts) {
      const data = await fetchOMDb(params, userKeys)
      const ratings = normalizeOMDbRatings(data)
      if (ratings?.imdbRating || ratings?.rottenTomatoesRating || ratings?.rottenTomatoesText) {
        return ratings
      }
    }
  }

  return null
}

// --- Watchmode helper functions ---
async function fetchWatchmode(path: string, params: Record<string, string> = {}) {
  const watchmodeKey = Deno.env.get("WATCHMODE_API_KEY")

  if (!watchmodeKey) {
    throw new Error("Missing WATCHMODE_API_KEY")
  }

  const url = new URL(`https://api.watchmode.com/v1${path}`)
  url.searchParams.set("apiKey", watchmodeKey)

  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value)
  }

  const response = await fetch(url)

  if (!response.ok) {
    const text = await response.text()
    throw new Error(`Watchmode request failed: ${response.status} ${text}`)
  }

  return await response.json()
}

function normalizeWatchmodeSource(source: any) {
  const type = String(source.type ?? "").toLowerCase()
  const format = String(source.format ?? "").toUpperCase()
  const price = source.price
  const rawWebURL = source.web_url ?? source.webUrl ?? null
  const rawIOSURL = source.ios_url ?? source.iosUrl ?? null
  const webURL = typeof rawWebURL === "string" && rawWebURL.startsWith("http") ? rawWebURL : null
  const iosURL = typeof rawIOSURL === "string" && !rawIOSURL.toLowerCase().includes("deeplinks available for paid plans only") ? rawIOSURL : null

  let typeText = "Watch"
  if (type === "sub" || type === "subscription") typeText = "Subscription"
  if (type === "free") typeText = "Free"
  if (type === "rent") typeText = "Rent"
  if (type === "buy" || type === "purchase") typeText = "Buy"

  let priceText: string | null = null
  if (typeText === "Subscription") {
    priceText = "Included"
  } else if (typeText === "Free") {
    priceText = "Free"
  } else if (typeof price === "number") {
    priceText = `$${price.toFixed(2)}`
  }

  return {
    serviceName: source.name ?? source.source_name ?? source.sourceName ?? "Unknown service",
    type: typeText,
    priceText,
    qualityText: format.length > 0 ? format : null,
    webURL,
    iosURL,
    openURL: iosURL ?? webURL
  }
}

function watchmodeSourceRank(source: any) {
  const type = String(source.type ?? "").toLowerCase()
  const quality = String(source.qualityText ?? "").toUpperCase()
  const priceText = String(source.priceText ?? "")
  const priceNumber = Number(priceText.replace(/[^0-9.]/g, ""))

  let typeRank = 99
  if (type === "subscription") typeRank = 0
  if (type === "free") typeRank = 1
  if (type === "rent") typeRank = 2
  if (type === "buy") typeRank = 3

  let qualityRank = 99
  if (quality === "4K") qualityRank = 0
  if (quality === "HD") qualityRank = 1
  if (quality === "SD") qualityRank = 2

  return {
    typeRank,
    priceRank: Number.isFinite(priceNumber) ? priceNumber : 0,
    qualityRank
  }
}

function dedupeWatchmodeSources(sources: any[]) {
  const bestByKey = new Map<string, any>()

  for (const source of sources) {
    const key = `${source.serviceName}-${source.type}`
    const existing = bestByKey.get(key)

    if (!existing) {
      bestByKey.set(key, source)
      continue
    }

    const currentRank = watchmodeSourceRank(source)
    const existingRank = watchmodeSourceRank(existing)

    if (currentRank.priceRank < existingRank.priceRank) {
      bestByKey.set(key, source)
      continue
    }

    if (currentRank.priceRank === existingRank.priceRank && currentRank.qualityRank < existingRank.qualityRank) {
      bestByKey.set(key, source)
    }
  }

  return Array.from(bestByKey.values()).sort((a: any, b: any) => {
    const lhs = watchmodeSourceRank(a)
    const rhs = watchmodeSourceRank(b)

    if (lhs.typeRank !== rhs.typeRank) return lhs.typeRank - rhs.typeRank
    if (lhs.priceRank !== rhs.priceRank) return lhs.priceRank - rhs.priceRank
    if (lhs.qualityRank !== rhs.qualityRank) return lhs.qualityRank - rhs.qualityRank
    return String(a.serviceName).localeCompare(String(b.serviceName))
  })
}

function watchmodeTitleIDFromSearch(data: any, kind: "movie" | "tv") {
  const titleResults = Array.isArray(data?.title_results)
    ? data.title_results
    : Array.isArray(data?.results)
      ? data.results
      : []

  const expectedTypes = kind === "movie"
    ? new Set(["movie"])
    : new Set(["tv_series", "tv_miniseries", "tv_special", "tv_movie", "tv"])

  const exactKindMatch = titleResults.find((item: any) => {
    const id = Number(item?.id)
    const type = String(item?.type ?? item?.result_type ?? "").toLowerCase()
    return Number.isFinite(id) && id > 0 && expectedTypes.has(type)
  })

  const fallbackMatch = titleResults.find((item: any) => {
    const id = Number(item?.id)
    return Number.isFinite(id) && id > 0
  })

  const match = exactKindMatch ?? fallbackMatch
  const id = Number(match?.id)

  return Number.isFinite(id) && id > 0 ? id : null
}

async function watchmodeTitleIDForTMDbID(tmdbID: number, kind: "movie" | "tv") {
  const searchAttempts: Array<{ search_field: string, search_value: string }> = []

  try {
    const externalIDs = await fetchTMDb(`/${kind}/${tmdbID}/external_ids`)
    const imdbID = String(externalIDs?.imdb_id ?? "").trim()

    if (imdbID.length > 0) {
      searchAttempts.push({ search_field: "imdb_id", search_value: imdbID })
    }
  } catch {
    // Fall through to TMDb-id based lookup attempts.
  }

  searchAttempts.push(
    { search_field: kind === "movie" ? "tmdb_movie_id" : "tmdb_tv_id", search_value: String(tmdbID) },
    { search_field: "tmdb_id", search_value: String(tmdbID) }
  )

  for (const attempt of searchAttempts) {
    try {
      const search = await fetchWatchmode("/search/", attempt)
      const watchmodeID = watchmodeTitleIDFromSearch(search, kind)

      if (watchmodeID) {
        return watchmodeID
      }
    } catch {
      continue
    }
  }

  return null
}

async function watchmodeSourcesForTMDbID(tmdbID: number, kind: "movie" | "tv", country: string) {
  const watchmodeID = await watchmodeTitleIDForTMDbID(tmdbID, kind)

  if (!watchmodeID) {
    return []
  }

  const sources = await fetchWatchmode(`/title/${watchmodeID}/sources/`, {
    regions: country.toUpperCase()
  })

  if (!Array.isArray(sources)) {
    return []
  }

  return dedupeWatchmodeSources(
    sources
      .map(normalizeWatchmodeSource)
      .filter((source: any) => source.serviceName && (source.webURL || source.iosURL))
  )
}

async function fetchWikidataSPARQL(query: string) {
  const url = new URL("https://query.wikidata.org/sparql")
  url.searchParams.set("query", query)
  url.searchParams.set("format", "json")

  const response = await fetch(url, {
    headers: {
      "Accept": "application/sparql-results+json",
      "User-Agent": "Vestigo/1.0 franchise-recommendations"
    }
  })

  if (!response.ok) {
    const text = await response.text()
    throw new Error(`Wikidata request failed: ${response.status} ${text}`)
  }

  return await response.json()
}

function sparqlString(value: string) {
  return value.replace(/\\/g, "\\\\").replace(/"/g, "\\\"")
}

async function searchWikidataFranchiseEntity(query: string) {
  const escapedQuery = sparqlString(query)
  const sparql = `
SELECT ?franchise ?franchiseLabel WHERE {
  ?franchise rdfs:label "${escapedQuery}"@en.
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
LIMIT 10
`

  const data = await fetchWikidataSPARQL(sparql)
  const bindings = data?.results?.bindings ?? []

  const exactMatches = bindings
    .map((binding: any) => ({
      uri: binding.franchise?.value ?? null,
      label: binding.franchiseLabel?.value ?? query
    }))
    .filter((item: any) => typeof item.uri === "string")
    .sort((a: any, b: any) => matchScore(b.label, query) - matchScore(a.label, query))

  return exactMatches[0] ?? null
}

async function getWikidataFranchiseRecommendations(query: string) {
  const franchise = await searchWikidataFranchiseEntity(query)

  if (!franchise?.uri) {
    return {
      franchise: null,
      refs: [] as Array<{ id: number, kind: "movie" | "tv" }>
    }
  }

  const escapedFranchiseURI = franchise.uri.replace(/[<>]/g, "")
    const sparql = `
    SELECT DISTINCT ?work ?workLabel ?tmdbMovieID ?tmdbTVID WHERE {
      VALUES ?franchise { <${escapedFranchiseURI}> }
      {
        ?work (wdt:P179|wdt:P361)+ ?franchise.
      }
      UNION
      {
        ?franchise (wdt:P527)+ ?work.
      }
      OPTIONAL { ?work wdt:P4947 ?tmdbMovieID. }
      OPTIONAL { ?work wdt:P4983 ?tmdbTVID. }
      FILTER(BOUND(?tmdbMovieID) || BOUND(?tmdbTVID))
      SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
    }
    LIMIT 300
    `

  const data = await fetchWikidataSPARQL(sparql)
  const bindings = data?.results?.bindings ?? []

  const refs: Array<{ id: number, kind: "movie" | "tv" }> = []

  for (const binding of bindings) {
    const movieID = Number(binding.tmdbMovieID?.value)
    const tvID = Number(binding.tmdbTVID?.value)

    if (Number.isFinite(movieID) && movieID > 0) {
      refs.push({ id: movieID, kind: "movie" })
    }

    if (Number.isFinite(tvID) && tvID > 0) {
      refs.push({ id: tvID, kind: "tv" })
    }
  }

  return {
    franchise: {
      uri: franchise.uri,
      name: franchise.label
    },
    refs: Array.from(
      new Map(refs.map((ref) => [`${ref.kind}-${ref.id}`, ref])).values()
    )
  }
}

// Search TMDb movie and TV endpoints for universe/franchise-like references by query text.
async function searchTMDbUniverseRefs(query: string) {
  const refs: Array<{ id: number, kind: "movie" | "tv" }> = []
  const normalizedQuery = normalizeTitle(query)
  const queryTokens = normalizedQuery.split(" ").filter((token) => token.length > 2)

  function matchesQueryText(item: any, titleKeys: string[]) {
    const title = titleKeys
      .map((key) => String(item?.[key] ?? ""))
      .find((value) => value.trim().length > 0) ?? ""
    const overview = String(item?.overview ?? "")
    const normalizedTitle = normalizeTitle(title)
    const normalizedText = normalizeTitle(`${title} ${overview}`)

    if (normalizedTitle.includes(normalizedQuery)) {
      return true
    }

    if (normalizedText.includes(normalizedQuery)) {
      return true
    }

    if (queryTokens.length > 1 && queryTokens.every((token) => normalizedText.includes(token))) {
      return true
    }

    return false
  }

  try {
    const movieSearch = await fetchTMDb("/search/movie", {
      query,
      include_adult: "false",
      page: "1"
    })

    const movieResults = Array.isArray(movieSearch.results) ? movieSearch.results : []

    for (const item of movieResults.slice(0, 40)) {
      if (typeof item.id === "number" && matchesQueryText(item, ["title", "original_title"])) {
        refs.push({ id: item.id, kind: "movie" })
      }
    }
  } catch {
    // Keep Wikidata results even if TMDb search fails.
  }

  try {
    const tvSearch = await fetchTMDb("/search/tv", {
      query,
      include_adult: "false",
      page: "1"
    })

    const tvResults = Array.isArray(tvSearch.results) ? tvSearch.results : []

    for (const item of tvResults.slice(0, 40)) {
      if (typeof item.id === "number" && matchesQueryText(item, ["name", "original_name"])) {
        refs.push({ id: item.id, kind: "tv" })
      }
    }
  } catch {
    // Keep Wikidata results even if TMDb search fails.
  }

  return Array.from(
    new Map(refs.map((ref) => [`${ref.kind}-${ref.id}`, ref])).values()
  )
}

async function tmdbCollectionByID(collectionID: number) {
  const collection = await fetchTMDb(`/collection/${collectionID}`)

  const parts = Array.isArray(collection.parts) ? collection.parts : []
  const items = parts
    .filter((item: any) => typeof item.id === "number")
    .map((item: any) => tmdbMovieDTO(item))

  return {
    id: collection.id,
    name: collection.name ?? "Collection",
    overview: collection.overview ?? null,
    items
  }
}

async function tmdbCollectionForMovie(movieID: number) {
  const detail = await fetchTMDb(`/movie/${movieID}`)
  const collection = detail.belongs_to_collection

  if (!collection || typeof collection.id !== "number") {
    return null
  }

  return await tmdbCollectionByID(collection.id)
}

async function getTVDBToken() {
  const tvdbKey = Deno.env.get("TVDB_API_KEY")

  if (!tvdbKey) {
    throw new Error("Missing TVDB_API_KEY")
  }

  const response = await fetch("https://api4.thetvdb.com/v4/login", {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      apikey: tvdbKey
    })
  })

  if (!response.ok) {
    const text = await response.text()
    throw new Error(`TVDB login failed: ${response.status} ${text}`)
  }

  const json = await response.json()
  return json.data.token
}

async function fetchTVDB(path: string, token: string) {
  const response = await fetch(`https://api4.thetvdb.com/v4${path}`, {
    headers: {
      "Authorization": `Bearer ${token}`,
      "Accept": "application/json"
    }
  })

  if (!response.ok) {
    const text = await response.text()
    throw new Error(`TVDB request failed ${path}: ${response.status} ${text}`)
  }

  const json = await response.json()
  return json.data
}

async function searchTVDB(query: string, token: string, type: string | null = null) {
  const url = new URL("https://api4.thetvdb.com/v4/search")
  url.searchParams.set("query", query)

  if (type) {
    url.searchParams.set("type", type)
  }

  const response = await fetch(url, {
    headers: {
      "Authorization": `Bearer ${token}`,
      "Accept": "application/json"
    }
  })

  if (!response.ok) {
    const text = await response.text()
    throw new Error(`TVDB search failed: ${response.status} ${text}`)
  }

  const json = await response.json()
  return json.data ?? []
}

function tvdbSearchQueries(query: string) {
  const normalized = query.trim()
  const variants = [
    normalized,
    normalized.replace(/\bfranchise\b/gi, "").trim(),
    normalized.replace(/\buniverse\b/gi, "").trim(),
    normalized.replace(/\bcinematic universe\b/gi, "").trim(),
    normalized.replace(/\bcollection\b/gi, "").trim()
  ]

  return Array.from(new Set(variants.filter((item) => item.length > 0)))
}

async function searchTVDBLists(query: string, token: string) {
  const allResults: any[] = []

  for (const candidateQuery of tvdbSearchQueries(query)) {
    try {
      allResults.push(...await searchTVDB(candidateQuery, token, "list"))
    } catch {
      continue
    }
  }

  if (allResults.length === 0) {
    for (const candidateQuery of tvdbSearchQueries(query)) {
      try {
        allResults.push(...await searchTVDB(candidateQuery, token, null))
      } catch {
        continue
      }
    }
  }

  return Array.from(
    new Map(
      allResults
        .filter((item: any) => typeof item.id === "number")
        .map((item: any) => [`${item.type ?? item.recordType ?? "unknown"}-${item.id}`, item])
    ).values()
  )
}

function tvdbEntityID(entity: any) {
  const candidates = [
    entity.id,
    entity.tvdb_id,
    entity.tvdbId,
    entity.entity_id,
    entity.entityId,
    entity.seriesId,
    entity.series_id,
    entity.movieId,
    entity.movie_id
  ]

  for (const candidate of candidates) {
    const number = Number(candidate)
    if (Number.isFinite(number) && number > 0) {
      return number
    }
  }

  return null
}

function tvdbEntityKind(entity: any) {
  const raw = String(
    entity.type ??
    entity.entityType ??
    entity.entity_type ??
    entity.recordType ??
    entity.record_type ??
    entity.objectType ??
    entity.object_type ??
    ""
  ).toLowerCase()

  if (raw.includes("movie") || raw === "film") return "movie"
  if (raw.includes("series") || raw.includes("show") || raw.includes("tv")) return "tv"

  if (entity.movieName || entity.movie_name) return "movie"
  if (entity.seriesName || entity.series_name) return "tv"

  return "unknown"
}

async function getTVDBEntityExtended(entity: any, token: string) {
  const id = tvdbEntityID(entity)
  const kind = tvdbEntityKind(entity)

  if (!id) return null

  const paths =
    kind === "movie"
      ? [`/movies/${id}/extended`]
      : kind === "tv"
        ? [`/series/${id}/extended`]
        : [`/series/${id}/extended`, `/movies/${id}/extended`]

  for (const path of paths) {
    try {
      return await fetchTVDB(path, token)
    } catch {
      continue
    }
  }

  return null
}

async function findTMDbRefsByTVDBID(tvdbID: number) {
  const data = await fetchTMDb(`/find/${tvdbID}`, {
    external_source: "tvdb_id"
  })

  const movieRefs = Array.isArray(data.movie_results)
    ? data.movie_results
        .filter((item: any) => typeof item.id === "number")
        .map((item: any) => ({ id: item.id, kind: "movie" as const }))
    : []

  const tvRefs = Array.isArray(data.tv_results)
    ? data.tv_results
        .filter((item: any) => typeof item.id === "number")
        .map((item: any) => ({ id: item.id, kind: "tv" as const }))
    : []

  return [...movieRefs, ...tvRefs]
}

function extractTMDbRefs(value: any, inheritedKind: "movie" | "tv" | "unknown" = "unknown") {
  const refs: Array<{ id: number, kind: "movie" | "tv" }> = []

  function visit(node: any, kindHint: "movie" | "tv" | "unknown") {
    if (!node || typeof node !== "object") return

    if (Array.isArray(node)) {
      for (const item of node) {
        visit(item, kindHint)
      }
      return
    }

    const localKind = tvdbEntityKind(node)
    const nextKind = localKind === "unknown" ? kindHint : localKind

    const remoteArrays = [
      node.remoteIds,
      node.remote_ids,
      node.externalIds,
      node.external_ids,
      node.remoteID,
      node.remote_ids_list
    ].filter(Array.isArray)

    for (const array of remoteArrays) {
      for (const remote of array) {
        const source = String(
          remote.sourceName ??
          remote.source_name ??
          remote.sourceType ??
          remote.source_type ??
          remote.source ??
          remote.type ??
          remote.name ??
          ""
        ).toLowerCase()

        const rawID = String(
          remote.id ??
          remote.remoteId ??
          remote.remote_id ??
          remote.value ??
          remote.externalId ??
          remote.external_id ??
          ""
        )

        if (!source.includes("tmdb") && !source.includes("themoviedb")) {
          continue
        }

        const numericID = Number(rawID)
        if (!Number.isFinite(numericID) || numericID <= 0) {
          continue
        }

        let kind: "movie" | "tv" | null = null
        if (source.includes("tv") || source.includes("series")) {
          kind = "tv"
        } else if (source.includes("movie") || source.includes("film")) {
          kind = "movie"
        } else if (nextKind === "movie" || nextKind === "tv") {
          kind = nextKind
        }

        if (kind) {
          refs.push({ id: numericID, kind })
        }
      }
    }

    for (const child of Object.values(node)) {
      visit(child, nextKind)
    }
  }

  visit(value, inheritedKind)

  return Array.from(
    new Map(refs.map((ref) => [`${ref.kind}-${ref.id}`, ref])).values()
  )
}

async function getTVDBFranchise(query: string, includeEntityDetails = false) {
  const token = await getTVDBToken()
  const lists = await searchTVDBLists(query, token)

  const bestList = lists
    .filter((item: any) => typeof item.id === "number" && typeof (item.name ?? item.title ?? item.translations?.eng) === "string")
    .sort((a: any, b: any) => {
      const aName = String(a.name ?? a.title ?? a.translations?.eng ?? "")
      const bName = String(b.name ?? b.title ?? b.translations?.eng ?? "")
      return matchScore(bName, query) - matchScore(aName, query)
    })[0]

  if (!bestList) {
    return null
  }

  const extended = await fetchTVDB(`/lists/${bestList.id}/extended`, token)
  const entities = Array.isArray(extended.entities) ? extended.entities : []

  const entityDetails: any[] = []

  if (includeEntityDetails) {
    for (const entity of entities.slice(0, 80)) {
      const detail = await getTVDBEntityExtended(entity, token)
      if (detail) {
        entityDetails.push(detail)
      }
    }
  }

  const allTitles = entities
    .flatMap((entity: any) => [
      entity.name,
      entity.title,
      entity.seriesName,
      entity.series_name,
      entity.movieName,
      entity.movie_name
    ])
    .filter((title: unknown): title is string => typeof title === "string")
    .filter((title: string) => title.trim().length > 0)

  return {
    id: bestList.id,
    name: extended.name ?? (bestList.name ?? bestList.title ?? bestList.translations?.eng) ?? query,
    overview: extended.overview ?? bestList.overview ?? null,
    memberTitles: Array.from(new Set(allTitles.map(normalizeTitle))),
    rawTitles: Array.from(new Set(allTitles)),
    entities,
    entityDetails
  }
}

function todayUTC(): string {
  return new Date().toISOString().slice(0, 10)
}

function extractJSON(text: string): any {
  // Try direct parse first
  try { return JSON.parse(text) } catch {}
  // Strip markdown code fences
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/)
  if (fenced) { try { return JSON.parse(fenced[1].trim()) } catch {} }
  // Find first {...} block
  const start = text.indexOf("{")
  const end = text.lastIndexOf("}")
  if (start !== -1 && end > start) { try { return JSON.parse(text.slice(start, end + 1)) } catch {} }
  throw new Error("No valid JSON found in response")
}

async function incrementAIUsage() {
  try {
    const kv = await Deno.openKv()
    await kv.atomic().sum(["ai_calls", todayUTC()], 1n).commit()
  } catch {
    // Non-fatal — don't fail the request if KV is unavailable
  }
}

async function getAIUsage(date: string): Promise<number> {
  const kv = await Deno.openKv()
  const entry = await kv.get<Deno.KvU64>(["ai_calls", date])
  return Number(entry.value ?? 0n)
}

Deno.serve(async (req) => {
  const url = new URL(req.url)

  try {
    if (url.pathname.endsWith("/ai-usage")) {
      const date = url.searchParams.get("date") ?? todayUTC()
      const count = await getAIUsage(date)
      return Response.json({ ok: true, date, count })
    }

    if (url.pathname.endsWith("/health")) {
      return Response.json({
        ok: true,
        app: "Vestigo",
        message: "Vestigo API is running"
      })
    }

    if (url.pathname.endsWith("/secrets-check")) {
      return Response.json({
        ok: true,
        secrets: {
          TVDB_API_KEY: previewSecret("TVDB_API_KEY"),
          TMDB_API_KEY: previewSecret("TMDB_API_KEY"),
          MOVIE_OF_THE_NIGHT_KEY: previewSecret("MOVIE_OF_THE_NIGHT_KEY"),
          WATCHMODE_API_KEY: previewSecret("WATCHMODE_API_KEY"),
          TASTEDIVE_API_KEY: previewSecret("TASTEDIVE_API_KEY"),
          AMC_API_KEY: previewSecret("AMC_API_KEY"),
          OPENROUTER_API_KEY: previewSecret("OPENROUTER_API_KEY"),
          OPENROUTER_BACKUP_KEY: previewSecret("OPENROUTER_BACKUP_KEY")
        }
      })
    }

    if (url.pathname.endsWith("/tmdb-proxy")) {
      const path = url.searchParams.get("path")

      if (!path) {
        return Response.json(
          { ok: false, error: "Missing TMDb path" },
          { status: 400 }
        )
      }

      const data = await tmdbProxy(path, url.searchParams)
      return Response.json(data)
    }

    if (url.pathname.endsWith("/tastedive-similar")) {
      const query = String(url.searchParams.get("q") ?? "").trim()
      const type = String(url.searchParams.get("type") ?? "movie").toLowerCase()
      const limit = String(url.searchParams.get("limit") ?? "20")

      if (!query) {
        return Response.json(
          { ok: false, error: "Missing TasteDive query" },
          { status: 400 }
        )
      }

      if (type !== "movie" && type !== "show") {
        return Response.json(
          { ok: false, error: "type must be movie or show" },
          { status: 400 }
        )
      }

      const results = await tasteDiveSimilar(query, type, limit)
      return Response.json({
        ok: true,
        source: "tastedive",
        query,
        type,
        results
      })
    }

    if (url.pathname.endsWith("/tmdb-collection-for-item")) {
      const id = Number(url.searchParams.get("id"))

      if (!Number.isFinite(id)) {
        return Response.json(
          { ok: false, error: "Missing or invalid movie id" },
          { status: 400 }
        )
      }

      const collection = await tmdbCollectionForMovie(id)

      return Response.json({
        ok: true,
        collection
      })
    }

    if (url.pathname.endsWith("/tmdb-collection")) {
      const id = Number(url.searchParams.get("id"))

      if (!Number.isFinite(id)) {
        return Response.json(
          { ok: false, error: "Missing or invalid collection id" },
          { status: 400 }
        )
      }

      const collection = await tmdbCollectionByID(id)

      return Response.json({
        ok: true,
        collection
      })
    }

    if (url.pathname.endsWith("/watchmode-sources")) {
      const tmdbID = Number(url.searchParams.get("tmdbID") ?? url.searchParams.get("id"))
      const rawKind = String(url.searchParams.get("kind") ?? "movie").toLowerCase()
      const country = String(url.searchParams.get("country") ?? "US").toUpperCase()

      if (!Number.isFinite(tmdbID) || tmdbID <= 0) {
        return Response.json(
          { ok: false, error: "Missing or invalid tmdbID" },
          { status: 400 }
        )
      }

      if (rawKind !== "movie" && rawKind !== "tv") {
        return Response.json(
          { ok: false, error: "kind must be movie or tv" },
          { status: 400 }
        )
      }

      const sources = await watchmodeSourcesForTMDbID(tmdbID, rawKind, country)

      return Response.json({
        ok: true,
        source: "watchmode",
        tmdbID,
        kind: rawKind,
        country,
        count: sources.length,
        sources
      })
    }

    if (url.pathname.endsWith("/ratings")) {
      const tmdbID = Number(url.searchParams.get("tmdbID") ?? url.searchParams.get("id"))
      const rawKind = String(url.searchParams.get("kind") ?? "movie").toLowerCase()
      const title = url.searchParams.get("title")
      const year = releaseYear(url.searchParams.get("year"))
      const userPrimaryKey = (url.searchParams.get("userKey") ?? "").trim()
      const userBackupKey = (url.searchParams.get("userBackupKey") ?? "").trim()
      const userKeys = [userPrimaryKey, userBackupKey].filter(k => k.length > 0)

      if (!Number.isFinite(tmdbID) || tmdbID <= 0) {
        return Response.json(
          { ok: false, error: "Missing or invalid tmdbID" },
          { status: 400 }
        )
      }

      if (rawKind !== "movie" && rawKind !== "tv") {
        return Response.json(
          { ok: false, error: "kind must be movie or tv" },
          { status: 400 }
        )
      }

      if (userKeys.length === 0) {
        return Response.json({ ok: true, source: "omdb", tmdbID, kind: rawKind, ratings: null })
      }

      const ratings = await omdbRatingsForTMDbID(tmdbID, rawKind, title, year, userKeys)

      return Response.json({
        ok: true,
        source: "omdb",
        tmdbID,
        kind: rawKind,
        ratings
      })
    }

    if (url.pathname.endsWith("/franchise-membership")) {
      const fallbackID = url.searchParams.get("id") ?? "unknown"
      const query = url.searchParams.get("query")

      if (!query) {
        return Response.json(
          { ok: false, error: "Missing query" },
          { status: 400 }
        )
      }

      const tvdbFranchise = await getTVDBFranchise(query, false)

      if (!tvdbFranchise) {
        return Response.json({
          ok: true,
          franchise: null
        })
      }

      return Response.json({
        ok: true,
        source: "tvdb",
        fallbackID,
        franchise: {
          id: tvdbFranchise.id,
          name: tvdbFranchise.name,
          overview: tvdbFranchise.overview,
          memberTitles: tvdbFranchise.memberTitles
        }
      })
    }
      
      if (url.pathname.endsWith("/debug-tvdb-franchise")) {
        const query = url.searchParams.get("query")

        if (!query) {
          return Response.json(
            { ok: false, error: "Missing query" },
            { status: 400 }
          )
        }

        const token = await getTVDBToken()
        const lists = await searchTVDBLists(query, token)

        const bestList = lists
          .filter((item: any) => typeof item.id === "number" && typeof (item.name ?? item.title ?? item.translations?.eng) === "string")
          .sort((a: any, b: any) => {
            const aName = String(a.name ?? a.title ?? a.translations?.eng ?? "")
            const bName = String(b.name ?? b.title ?? b.translations?.eng ?? "")
            return matchScore(bName, query) - matchScore(aName, query)
          })[0]

        if (!bestList) {
          return Response.json({
            ok: true,
            searchQueries: tvdbSearchQueries(query),
            list: null,
            searchResults: lists.slice(0, 20).map((item: any) => ({
              id: item.id,
              name: item.name ?? item.title ?? item.translations?.eng,
              type: item.type ?? item.recordType ?? item.record_type ?? null,
              keys: Object.keys(item),
              raw: item
            })),
            entities: []
          })
        }

        const extended = await fetchTVDB(`/lists/${bestList.id}/extended`, token)
        const entities = Array.isArray(extended.entities) ? extended.entities : []

        return Response.json({
          ok: true,
          searchQueries: tvdbSearchQueries(query),
          list: {
            id: bestList.id,
            name: bestList.name ?? bestList.title ?? bestList.translations?.eng,
            type: bestList.type ?? bestList.recordType ?? bestList.record_type ?? null,
            overview: bestList.overview ?? null,
            raw: bestList
          },
          extendedKeys: Object.keys(extended),
          entityCount: entities.length,
          firstEntities: entities.slice(0, 10).map((entity: any) => ({
            keys: Object.keys(entity),
            raw: entity
          }))
        })
      }

      if (url.pathname.endsWith("/franchise-recommendations")) {
        const fallbackID = url.searchParams.get("id") ?? "unknown"
        const query = url.searchParams.get("query")

        if (!query) {
          return Response.json(
            { ok: false, error: "Missing query" },
            { status: 400 }
          )
        }

        const tvdbFranchise = await getTVDBFranchise(query, true)

        const entityIDs = [
          ...(tvdbFranchise?.entities ?? []),
          ...(tvdbFranchise?.entityDetails ?? [])
        ]
          .map((entity: any) => tvdbEntityID(entity))
          .filter((id: number | null): id is number => Number.isFinite(id) && id !== null)

        const refsFromEmbeddedRemoteIDs = [
          ...extractTMDbRefs(tvdbFranchise?.entities ?? []),
          ...extractTMDbRefs(tvdbFranchise?.entityDetails ?? [])
        ]

        const refsFromTMDbFind: Array<{ id: number, kind: "movie" | "tv" }> = []

        for (const tvdbID of Array.from(new Set(entityIDs)).slice(0, 80)) {
          try {
            const refs = await findTMDbRefsByTVDBID(tvdbID)
            refsFromTMDbFind.push(...refs)
          } catch {
            continue
          }
        }

        const wikidataResult = refsFromEmbeddedRemoteIDs.length === 0 && refsFromTMDbFind.length === 0
          ? await getWikidataFranchiseRecommendations(query)
          : {
              franchise: null,
              refs: [] as Array<{ id: number, kind: "movie" | "tv" }>
            }

        const tmdbSearchRefs = refsFromEmbeddedRemoteIDs.length === 0 && refsFromTMDbFind.length === 0
          ? await searchTMDbUniverseRefs(query)
          : []

        const exactRefs = Array.from(
          new Map(
            [...refsFromEmbeddedRemoteIDs, ...refsFromTMDbFind, ...wikidataResult.refs, ...tmdbSearchRefs]
              .map((ref) => [`${ref.kind}-${ref.id}`, ref])
          ).values()
        )

        const results: any[] = []

        for (const ref of exactRefs.slice(0, 80)) {
          try {
            const detail = await fetchTMDb(`/${ref.kind}/${ref.id}`)
            results.push(ref.kind === "tv" ? tmdbTVDTO(detail) : tmdbMovieDTO(detail))
          } catch {
            continue
          }
        }

        const uniqueResults = Array.from(
          new Map(results.map((item) => [`${item.kind}-${item.id}`, item])).values()
        ).sort((a: any, b: any) => b.voteAverage - a.voteAverage)

        return Response.json({
          ok: true,
        source: wikidataResult.refs.length > 0 ? "wikidata-linked-franchise-to-tmdb" : "tvdb-id-to-tmdb-find",
          fallbackID,
          tvdbEntityIDCount: Array.from(new Set(entityIDs)).length,
          embeddedExactRefCount: refsFromEmbeddedRemoteIDs.length,
          tmdbFindRefCount: refsFromTMDbFind.length,
          wikidataFranchise: wikidataResult.franchise,
          wikidataExactRefCount: wikidataResult.refs.length,
          tmdbSearchRefCount: tmdbSearchRefs.length,
          exactRefCount: exactRefs.length,
          count: uniqueResults.length,
          results: uniqueResults
        })
      }

    if (url.pathname.endsWith("/amc-showtimes")) {
      const amcKey = Deno.env.get("AMC_API_KEY")
      if (!amcKey) {
        return Response.json({ ok: false, error: "AMC_API_KEY not configured" }, { status: 500 })
      }

      const filmTitle = (url.searchParams.get("title") ?? "").trim()
      const date = (url.searchParams.get("date") ?? "").trim()
      const lat = (url.searchParams.get("lat") ?? "").trim()
      const lon = (url.searchParams.get("lon") ?? "").trim()

      if (!filmTitle || !date || !lat || !lon) {
        return Response.json({ ok: false, error: "Missing required params: title, date, lat, lon" }, { status: 400 })
      }

      const amcURL = `https://api.amctheatres.com/v2/showtimes/views/current-location/${encodeURIComponent(date)}/${encodeURIComponent(lat)}/${encodeURIComponent(lon)}?page-size=100`

      // ?probe=1 hits a simple catalogue endpoint to check if the key has any access at all
      if (url.searchParams.get("probe") === "1") {
        const probeResp = await fetchWithTimeout("https://api.amctheatres.com/v2/theatres?page-size=1", {
          headers: { "X-AMC-Vendor-Key": amcKey, "Accept": "application/json" }
        }, 8000)
        const probeBody = await probeResp.text().catch(() => "(unreadable)")
        return Response.json({ ok: probeResp.ok, status: probeResp.status, body: probeBody })
      }

      const amcResp = await fetchWithTimeout(amcURL, {
        headers: {
          "X-AMC-Vendor-Key": amcKey,
          "Accept": "application/json"
        }
      }, 10000)

      if (!amcResp.ok) {
        const errBody = await amcResp.text().catch(() => "(unreadable)")
        return Response.json({ ok: false, error: `AMC API error: ${amcResp.status}`, amcBody: errBody }, { status: 502 })
      }

      const amcData = await amcResp.json()

      // Pass ?debug=1 to see the raw AMC response for response shape diagnosis
      if (url.searchParams.get("debug") === "1") {
        return Response.json({ ok: true, raw: amcData })
      }

      const allShowtimes: any[] = amcData?._embedded?.showtimes ?? []

      // Filter to only showtimes for the requested film
      const matching = allShowtimes.filter(st => {
        const name = st._embedded?.movie?.name ?? st.movieName ?? ""
        return matchScore(name, filmTitle) >= 60
      })

      // Group by theatre
      const theatreMap = new Map<string, { name: string; lat: number | null; lon: number | null; entries: any[] }>()

      for (const st of matching) {
        const theatreName: string = st._embedded?.theatre?.name ?? "AMC Theatre"
        if (!theatreMap.has(theatreName)) {
          const loc = st._embedded?.theatre?.location
          theatreMap.set(theatreName, {
            name: theatreName,
            lat: typeof loc?.latitude === "number" ? loc.latitude : null,
            lon: typeof loc?.longitude === "number" ? loc.longitude : null,
            entries: []
          })
        }

        // AMC returns local time without timezone; convert to a UTC-anchored ISO string
        // by treating the local time as-is (display only, not timezone-sensitive)
        const rawTime: string = st.showDateTimeLocal ?? st.showDateTime ?? ""

        // Format: AMC uses _embedded.movieVisitType.name or top-level movieVisitType
        const formatRaw: string | null =
          st._embedded?.movieVisitType?.name ??
          (typeof st.movieVisitType === "string" ? st.movieVisitType : null) ??
          null

        // Normalise common format names to short labels
        const format = normalizeAMCFormat(formatRaw)

        // Accessibility from attributes array (objects with `code` or `description`)
        const attrCodes: string[] = (st.attributes ?? [])
          .map((a: any) => (a.code ?? a.description ?? "").toString().toUpperCase())
          .filter((c: string) => c.length > 0)

        const knownAccessibility = ["CC", "OC", "AD", "AS", "HH", "HL"]
        const accessibility = attrCodes.filter(c => knownAccessibility.some(k => c.includes(k)))

        theatreMap.get(theatreName)!.entries.push({
          id: String(st.id ?? ""),
          startTime: rawTime,
          format,
          accessibility: accessibility.length > 0 ? accessibility : null,
          bookingURL: st.purchaseUrl ?? st._links?.["amc:purchase"]?.href ?? null
        })
      }

      const theaters = Array.from(theatreMap.values()).map(t => ({
        name: t.name,
        lat: t.lat,
        lon: t.lon,
        showtimes: t.entries.sort((a, b) => a.startTime.localeCompare(b.startTime))
      }))

      return Response.json({ ok: true, totalShowtimes: allShowtimes.length, matchedShowtimes: matching.length, theaters })
    }

    if (url.pathname.endsWith("/thematic-recommend")) {
      const aiKey = Deno.env.get("OPENROUTER_API_KEY")
      const aiKeyBackup = Deno.env.get("OPENROUTER_BACKUP_KEY")
      if (!aiKey) {
        return Response.json({ ok: false, error: "OPENROUTER_API_KEY not configured" }, { status: 500 })
      }

      const body = await req.json().catch(() => null)
      const query = typeof body?.query === "string" ? body.query.trim() : ""
      const filter = typeof body?.filter === "string" ? body.filter : "both"

      if (!query) {
        return Response.json({ ok: false, error: "Missing query" }, { status: 400 })
      }

      const mediaScope = filter === "movie" ? "movies only" : filter === "tv" ? "TV shows only" : "movies and TV shows"

      const systemPrompt = `You are a film and TV recommendation expert. Based on the user's description, list real, existing ${mediaScope} that best match.

Return one title per line in this exact format:
Title|Year

Rules:
- Return 20-25 titles. Must be real and actually exist.
- Lead with the strongest matches first.
- Prefer well-regarded titles. Vary directors, franchises, and eras.
- Return ONLY the list. No JSON, no markdown, no numbering, no explanations.`

      const openRouterBody = JSON.stringify({
        models: [
          "poolside/laguna-xs-2.1:free",
          "nvidia/nemotron-3.5-lightning:free",
          "liquid/lfm-2.5-2.6b:free"
        ],
        max_tokens: 800,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: query }
        ]
      })

      async function callOpenRouter(key: string): Promise<string | null> {
        try {
          const resp = await fetchWithTimeout("https://openrouter.ai/api/v1/chat/completions", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "Authorization": `Bearer ${key}`,
              "HTTP-Referer": "https://vestigo.app",
              "X-Title": "Vestigo"
            },
            body: openRouterBody
          }, 50000)
          if (!resp.ok) return null
          const data = await resp.json()
          return (data?.choices?.[0]?.message?.content ?? "").trim() || null
        } catch {
          return null
        }
      }

      let text = await callOpenRouter(aiKey)
      if (!text && aiKeyBackup) {
        text = await callOpenRouter(aiKeyBackup)
      }
      if (!text) {
        return Response.json({ ok: false, error: "Service is busy, please try again in a moment" }, { status: 503 })
      }

      const llmTitles = text
        .split('\n')
        .map((l: string) => l.replace(/^```[a-z]*/, '').replace(/^[0-9]+[.)]\s*/, '').replace(/^[-*•]\s*/, '').trim())
        .filter((l: string) => l.length > 0 && !l.startsWith('```') && l.includes('|'))
        .map((line: string) => {
          const pipeIdx = line.indexOf('|')
          const title = line.slice(0, pipeIdx).trim()
          const year = Number(line.slice(pipeIdx + 1).trim())
          return { title, year: Number.isFinite(year) && year > 1900 ? year : null }
        })
        .filter((item: any) => item.title.length > 0)

      if (llmTitles.length === 0) {
        return Response.json({ ok: false, error: "Service is busy, please try again in a moment" }, { status: 503 })
      }

      async function enrichOneTitle(item: any): Promise<any | null> {
        const titleStr = String(item.title ?? "").trim()
        if (!titleStr) return null
        try {
          if (filter === "tv") {
            const params: Record<string, string> = { query: titleStr, include_adult: "false" }
            if (typeof item.year === "number") params.first_air_date_year = String(item.year)
            const result = await fetchTMDb("/search/tv", params)
            const hit = Array.isArray(result.results) ? result.results[0] : null
            return hit && typeof hit.id === "number" ? { ...hit, media_type: "tv" } : null
          } else if (filter === "movie") {
            const params: Record<string, string> = { query: titleStr, include_adult: "false" }
            if (typeof item.year === "number") params.year = String(item.year)
            const result = await fetchTMDb("/search/movie", params)
            const hit = Array.isArray(result.results) ? result.results[0] : null
            return hit && typeof hit.id === "number" ? { ...hit, media_type: "movie" } : null
          } else {
            const result = await fetchTMDb("/search/multi", { query: titleStr, include_adult: "false" })
            const results = Array.isArray(result.results) ? result.results : []
            const hit = results.find((r: any) => r.media_type === "movie" || r.media_type === "tv") ?? null
            return hit && typeof hit.id === "number" ? hit : null
          }
        } catch {
          return null
        }
      }

      const enriched = await Promise.all(llmTitles.slice(0, 20).map(enrichOneTitle))
      const seen = new Set<string>()
      const titles = enriched.filter((item: any): item is NonNullable<typeof item> => {
        if (!item) return false
        const key = `${item.media_type ?? "unknown"}-${item.id}`
        if (seen.has(key)) return false
        seen.add(key)
        return true
      })

      await incrementAIUsage()
      return Response.json({ ok: true, titles })
    }

    if (url.pathname.endsWith("/groq-rerank")) {
      const aiKey = Deno.env.get("OPENROUTER_API_KEY")
      if (!aiKey) {
        return Response.json({ ok: false, error: "OPENROUTER_API_KEY not configured" }, { status: 500 })
      }

      const body = await req.json().catch(() => null)
      const query = typeof body?.query === "string" ? body.query.trim() : ""
      const candidates = Array.isArray(body?.candidates) ? body.candidates : []

      if (!query || candidates.length === 0) {
        return Response.json({ ok: false, error: "Missing query or candidates" }, { status: 400 })
      }

      const candidateList = candidates.map((c: any, i: number) => {
        const year = c.year ? ` (${c.year})` : ""
        const overview = typeof c.overview === "string" && c.overview ? ` — ${c.overview.slice(0, 180)}` : ""
        return `${i + 1}. ${c.title}${year}${overview}`
      }).join("\n")

      const rerankSystemPrompt = `Today's date is July 2026. The current year is 2026.
You are a film and TV recommendation expert. The user has described their preferences. From the candidate list, pick and order only the titles that holistically satisfy ALL the stated preferences together — genre_flavor first, then mood and secondary.

The preference format uses these fields:
- genre_flavor: HARD setting/genre requirement — if present, ONLY titles that genuinely fit this genre belong in the output. Example: "Space (set in outer space — spacecraft, astronauts, alien worlds)" means only titles actually set in space. Exclude any candidate that doesn't satisfy genre_flavor, regardless of how well it fits the mood.
- mood: primary emotional archetype. "Feel-Good" = uplifting/heartwarming; "Comedy" = primarily comedic; "Mystery" = whodunit/secrets; "Thriller" = tension/suspense/danger; "Smart people solving problems" = experts using intelligence; "Mission" = specific objective/operation/survival; "Heist" = robbery/con/caper; "Adventure" = exploration/excitement; "Character and Relationships" = relationship dynamics/personal growth; "Human Triumph" = underdog/resilience; "Epic / Spectacle" = grand scale/visuals; "Mind-Bending" = twists/unreliable narrators; "Horror" = fear/dread; "Thought-Provoking Sci-Fi" = idea-driven sci-fi; "War" = combat/military; "Historical" = stories during real historical events; "Documentary" = nonfiction only
- secondary: secondary mood layers to blend with the primary
- realism: how grounded vs fantastical
- release_window: era preference
- source: preferred source material type
- avoid: absolute exclusions — do NOT include any title from these categories, zero exceptions

Return ONLY a valid JSON object:
{ "rankings": [{"title": "Inception", "year": 2010}, {"title": "Prisoners", "year": 2013}] }

Rules:
- ONLY include titles from the provided candidate list. Never invent or add titles.
- genre_flavor is NON-NEGOTIABLE: exclude any candidate that doesn't genuinely fit, even if the mood match is excellent.
- Order best all-around match first — think like a knowledgeable film fan, not a keyword scorer.
- Return at most 35. Include all candidates that genuinely fit — don't be unnecessarily restrictive.
- Strictly exclude anything in "avoid". Zero exceptions.
- Return ONLY the raw JSON object, nothing else.`

      const rerankResp = await fetchWithTimeout("https://openrouter.ai/api/v1/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${aiKey}`,
          "HTTP-Referer": "https://vestigo.app",
          "X-Title": "Vestigo"
        },
        body: JSON.stringify({
          model: "poolside/laguna-xs-2.1:free",
          max_tokens: 2048,
          messages: [
            { role: "system", content: rerankSystemPrompt },
            { role: "user", content: `User preferences:\n${query}\n\nCandidates:\n${candidateList}` }
          ]
        })
      }, 15000)

      if (!rerankResp.ok) {
        const text = await rerankResp.text()
        return Response.json({ ok: false, error: `AI error: ${rerankResp.status} ${text}` }, { status: 502 })
      }

      const rerankData = await rerankResp.json()
      const rerankText = rerankData?.choices?.[0]?.message?.content ?? ""

      let rerankParsed: any
      try {
        rerankParsed = extractJSON(rerankText)
      } catch {
        return Response.json({ ok: false, error: "Failed to parse AI response as JSON", raw: rerankText }, { status: 502 })
      }

      const rankings = Array.isArray(rerankParsed?.rankings) ? rerankParsed.rankings : []
      await incrementAIUsage()
      return Response.json({ ok: true, rankings })
    }

    if (url.pathname.endsWith("/thematic-parse")) {
      const aiKey = Deno.env.get("OPENROUTER_API_KEY")
      if (!aiKey) {
        return Response.json({ ok: false, error: "OPENROUTER_API_KEY not configured" }, { status: 500 })
      }

      const body = await req.json().catch(() => null)
      const query = typeof body?.query === "string" ? body.query.trim() : ""

      if (!query) {
        return Response.json({ ok: false, error: "Missing query" }, { status: 400 })
      }

      const systemPrompt = `Today's date is July 2026. The current year is 2026.
You extract structured search parameters from movie or TV show requests.
Return ONLY a valid JSON object with exactly these fields (no extra text, no markdown):
{
  "similarToTitles": [],
  "avoidSimilarToTitles": [],
  "people": [],
  "positiveThemes": [],
  "negativeThemes": [],
  "genres": [],
  "excludedGenres": [],
  "releaseYear": null
}

Rules:
- Use your full real-world knowledge to identify people, events, and subjects from indirect descriptions.
  Examples: "sprinter at the 1936 Olympics" → people: ["Jesse Owens"]
            "Homer's poem" → people: ["Homer"], similarToTitles: ["The Odyssey"], positiveThemes: ["epic", "ancient Greece", "hero's journey"]
            "the painter who cut off his ear" → people: ["Vincent van Gogh"]
            "Nolan's mind-bending dream film" → similarToTitles: ["Inception"], people: ["Christopher Nolan"]
- Only populate similarToTitles when the user explicitly names a title OR you can directly identify the specific work they mean.
- "alien" as a common noun → positiveThemes: ["alien", "extraterrestrial"], genres: ["sci-fi"]. Only similarToTitles: ["Alien"] if user explicitly means the Ridley Scott franchise.
- "animated" / "cartoon" / "anime" → genres: ["animation"]
- "live action version" of an animated story → excludedGenres: ["animation"], animated source in similarToTitles (e.g. "live action Moana" → similarToTitles: ["Moana"], excludedGenres: ["animation"])
- "not animated" / "live action" → excludedGenres: ["animation"]
- "released this year" / "from this year" → releaseYear: 2026
- Specific year like "from 2019" → releaseYear: 2019
- Vague eras like "last five years" or "from the 80s" → releaseYear: null
- Infer themes from liked/disliked aspects: "I liked the heist planning" → positiveThemes: ["heist"]
- Return ONLY the raw JSON object, nothing else.`

      const aiResp = await fetchWithTimeout("https://openrouter.ai/api/v1/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${aiKey}`,
          "HTTP-Referer": "https://vestigo.app",
          "X-Title": "Vestigo"
        },
        body: JSON.stringify({
          model: "poolside/laguna-xs-2.1:free",
          max_tokens: 512,
          messages: [
            { role: "system", content: systemPrompt },
            { role: "user", content: query }
          ]
        })
      }, 15000)

      if (!aiResp.ok) {
        const text = await aiResp.text()
        return Response.json({ ok: false, error: `AI error: ${aiResp.status} ${text}` }, { status: 502 })
      }

      const aiData = await aiResp.json()
      const text = aiData?.choices?.[0]?.message?.content ?? ""

      let parsed: any
      try {
        parsed = extractJSON(text)
      } catch {
        return Response.json({ ok: false, error: "Failed to parse AI response as JSON", raw: text }, { status: 502 })
      }

      await incrementAIUsage()
      return Response.json({ ok: true, ...parsed })
    }

    if (url.pathname.endsWith("/brand-logo")) {
      const domain = url.searchParams.get("domain") ?? ""
      const w = url.searchParams.get("w") ?? "128"
      const h = url.searchParams.get("h") ?? "128"
      const clientId = Deno.env.get("BRANDFETCH_CLIENT_ID")

      if (!clientId) {
        return new Response("Missing BRANDFETCH_CLIENT_ID", { status: 500 })
      }

      if (!domain) {
        return new Response("Missing domain", { status: 400 })
      }

      const upstream = await fetchWithTimeout(
        `https://cdn.brandfetch.io/${domain}/w/${w}/h/${h}/fallback/404?c=${clientId}`
      )

      return new Response(upstream.body, {
        status: upstream.status,
        headers: {
          "Content-Type": upstream.headers.get("Content-Type") ?? "image/png",
          "Cache-Control": "public, max-age=86400",
        },
      })
    }

    return Response.json(
      {
        error: "Not found",
        path: url.pathname
      },
      {
        status: 404
      }
    )
  } catch (error) {
    return Response.json(
      {
        ok: false,
        error: error instanceof Error ? error.message : "Unknown error"
      },
      {
        status: 500
      }
    )
  }
})
