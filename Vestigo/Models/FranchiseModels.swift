import Foundation

struct FranchiseCollection: Identifiable, Hashable {
    let id: String
    let title: String
    let logoSystemName: String
    let logoURL: URL?
    let aliases: [String]
    let description: String
    let tvdbListQuery: String
    let tvdbListID: Int?
    let tvdbMemberTitles: Set<String>
    let usesTVDBMembership: Bool
    let tmdbCollectionID: Int?
    let exactMemberIDs: Set<String>

    init(
        id: String,
        title: String,
        logoSystemName: String,
        logoURL: URL? = nil,
        aliases: [String],
        description: String,
        tvdbListQuery: String,
        tvdbListID: Int? = nil,
        tvdbMemberTitles: Set<String> = [],
        usesTVDBMembership: Bool = false,
        tmdbCollectionID: Int? = nil,
        exactMemberIDs: Set<String> = []
    ) {
        self.id = id
        self.title = title
        self.logoSystemName = logoSystemName
        self.logoURL = logoURL
        self.aliases = aliases
        self.description = description
        self.tvdbListQuery = tvdbListQuery
        self.tvdbListID = tvdbListID
        self.tvdbMemberTitles = tvdbMemberTitles
        self.usesTVDBMembership = usesTVDBMembership
        self.tmdbCollectionID = tmdbCollectionID
        self.exactMemberIDs = exactMemberIDs
    }
}

struct ForYouSection: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let items: [MediaItem]
}
