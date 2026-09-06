import Foundation
import SwiftUI

struct PickForMeRecentSearch: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var answers: PickForMeAnswers
}
