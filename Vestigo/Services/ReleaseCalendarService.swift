import Foundation

#if canImport(EventKit)
import EventKit

struct ReleaseCalendarService {
    private let eventStore = EKEventStore()

    @discardableResult
    func addReleaseEvent(for item: MediaItem, releaseDate: Date, replacing previousID: String? = nil) async throws -> String? {
        let granted = try await eventStore.requestWriteOnlyAccessToEvents()
        guard granted else {
            throw CalendarAddError.accessDenied
        }

        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw CalendarAddError.noCalendar
        }

        if let previousID,
           let existing = eventStore.event(withIdentifier: previousID) {
            try eventStore.remove(existing, span: .thisEvent)
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = calendarTitle(for: item)
        event.notes = calendarNotes(for: item)
        event.calendar = calendar
        event.isAllDay = true
        event.startDate = Calendar.current.startOfDay(for: releaseDate)
        event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: event.startDate) ?? event.startDate

        try eventStore.save(event, span: .thisEvent)
        return event.eventIdentifier
    }

    private func calendarTitle(for item: MediaItem) -> String {
        switch item.kind {
        case .movie:
            return "\(item.title) release"
        case .tv:
            return "\(item.title) season release"
        case .person:
            return item.title
        }
    }

    private func calendarNotes(for item: MediaItem) -> String {
        item.overview.isEmpty ? "Added by Vestigo." : "\(item.overview)\n\nAdded by Vestigo."
    }
}
#else
struct ReleaseCalendarService {
    @discardableResult
    func addReleaseEvent(for item: MediaItem, releaseDate: Date, replacing previousID: String? = nil) async throws -> String? {
        throw CalendarAddError.unavailable
    }
}
#endif

enum CalendarAddError: LocalizedError {
    case accessDenied
    case noCalendar
    case unavailable

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access was not granted."
        case .noCalendar:
            return "No writable calendar is available."
        case .unavailable:
            return "Calendar access is not available on this device."
        }
    }
}
