import SwiftUI
import Foundation

// MARK: - OMDb Usage Bar

struct OMDbUsageBar: View {
    let settings: AppSettings

    private var todayCount: Int {
        let today = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()))
        return settings.omdbLastRequestDate == today ? settings.omdbDailyRequestCount : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(todayCount.formatted()) calls")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("All time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(settings.omdbTotalRequestCount.formatted()) calls")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }
}
