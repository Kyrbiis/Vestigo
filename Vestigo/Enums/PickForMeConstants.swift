// Pick For Me keyword/genre signal constants
import Foundation

let pickForMeHistoricalTrueEventSignals: [String] = [
    "true story",
    "based on true",
    "based on actual",
    "real events",
    "real-life",
    "true events",
    "actual events",
    "based on the life",
    "biopic"
]

let pickForMeHistoricalContextSignals: [String] = [
    "political history",
    "historical event",
    "world war",
    "world war i",
    "world war ii",
    "wwi",
    "wwii",
    "civil war",
    "cold war",
    "holocaust",
    "nazi",
    "revolution",
    "president",
    "prime minister",
    "queen",
    "king",
    "roman empire",
    "tudor",
    "dynasty"
]

let pickForMeNonHistoricalDocumentarySignals: [String] = [
    "nature",
    "wildlife",
    "planet",
    "climate",
    "environment",
    "ocean",
    "animal",
    "animals",
    "music",
    "concert",
    "sports",
    "stand-up",
    "comedy special"
]

let pickForMeHumanTriumphSignals: [String] = [
    "overcome",
    "overcoming",
    "triumph",
    "perseverance",
    "resilience",
    "underdog",
    "against the odds",
    "inspiring",
    "inspirational",
    "determination",
    "adversity",
    "achievement",
    "champion",
    "courage",
    "barrier",
    "barriers",
    "obstacle",
    "obstacles",
    "disability",
    "disabled",
    "redemption",
    "breakthrough"
]

let pickForMeWarDealBreakerSignals: [String] = [
    "war",
    "wartime",
    "battlefield",
    "soldier",
    "troops",
    "military",
    "armed forces",
    "front line",
    "invasion",
    "invades",
    "invading",
    "occupation",
    "occupied",
    "resistance fighter",
    "armed resistance",
    "guerrilla",
    "enemy forces",
    "foreign army",
    "paratrooper"
]

let pickForMeEpicSpectacleSignals: [String] = pipeSeparatedStrings(
    "epic|space|disaster|war|planet|galaxy|future|battle|large-scale|world|worlds|kingdom|empire|invasion|apocalypse|catastrophe|quest|adventure|survival|civilization|high stakes|save the world|global"
)

let pickForMeHistoricalGenreIDs: Set<Int> = [36]
let pickForMeWarGenreIDs: Set<Int> = [10752, 10768]

let moreLikeThisWeakSimilarityGenreIDs: Set<Int> = [18, 35, 28]

private func pipeSeparatedStrings(_ value: String) -> [String] {
    value.split(separator: "|").map(String.init)
}
