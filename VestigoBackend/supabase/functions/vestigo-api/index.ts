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
    exists: Boolean(value),
    preview: value ? `${value.slice(0, 4)}...${value.slice(-4)}` : null
  }
}

function tmdbMovieDTO(result: any) {
  return {
    id: result.id,
    kind: "movie",
    title: result.title ?? result.original_title ?? "Untitled",
    overview: result.overview ?? "",
    posterPath: result.poster_path ?? null,
    backdropPath: result.backdrop_path ?? null,
    releaseDate: result.release_date ?? null,
    voteAverage: typeof result.vote_average === "number" ? result.vote_average : 0,
    genreIDs: Array.isArray(result.genre_ids) ? result.genre_ids : [],
    originalLanguage: result.original_language ?? null
  }
}

function tmdbTVDTO(result: any) {
  return {
    id: result.id,
    kind: "tv",
    title: result.name ?? result.original_name ?? "Untitled",
    overview: result.overview ?? "",
    posterPath: result.poster_path ?? null,
    backdropPath: result.backdrop_path ?? null,
    releaseDate: result.first_air_date ?? null,
    voteAverage: typeof result.vote_average === "number" ? result.vote_average : 0,
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

  const response = await fetch(url)

  if (!response.ok) {
    const text = await response.text()
    throw new Error(`TMDb request failed: ${response.status} ${text}`)
  }

  return await response.json()
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
    .map(tmdbMovieDTO)

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

Deno.serve(async (req) => {
  const url = new URL(req.url)

  try {
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
          WATCHMODE_API_KEY: previewSecret("WATCHMODE_API_KEY")
        }
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
