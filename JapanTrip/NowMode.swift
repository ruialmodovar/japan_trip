import Foundation

struct ScheduledTripActivity: Identifiable, Hashable {
    let day: TripDay
    let activity: TripActivity
    let date: Date

    var id: String { activity.id }
}

struct LiveTripMoment: Hashable {
    enum Phase: Hashable { case beforeTrip, happening, upcoming, completed }

    let phase: Phase
    let entry: ScheduledTripActivity?
    let referenceDate: Date

    var countdown: TimeInterval? {
        guard let entry, phase == .beforeTrip || phase == .upcoming else { return nil }
        return max(0, entry.date.timeIntervalSince(referenceDate))
    }
}

enum NowModePlanner {
    static func moment(at date: Date = Date(), calendar sourceCalendar: Calendar = .current) -> LiveTripMoment {
        let entries = scheduledEntries(calendar: sourceCalendar)
        guard let first = entries.first, let last = entries.last else {
            return .init(phase: .completed, entry: nil, referenceDate: date)
        }
        if date < first.date {
            return .init(phase: .beforeTrip, entry: first, referenceDate: date)
        }
        if date > last.date.addingTimeInterval(4 * 60 * 60) {
            return .init(phase: .completed, entry: last, referenceDate: date)
        }

        if let nextIndex = entries.firstIndex(where: { $0.date > date }) {
            if nextIndex > 0 {
                let previous = entries[nextIndex - 1]
                let naturalEnd = min(entries[nextIndex].date, previous.date.addingTimeInterval(3 * 60 * 60))
                if date < naturalEnd {
                    return .init(phase: .happening, entry: previous, referenceDate: date)
                }
            }
            return .init(phase: .upcoming, entry: entries[nextIndex], referenceDate: date)
        }
        return .init(phase: .happening, entry: last, referenceDate: date)
    }

    static func scheduledEntries(calendar sourceCalendar: Calendar = .current) -> [ScheduledTripActivity] {
        var calendar = sourceCalendar
        calendar.locale = Locale(identifier: "pt_BR")
        var entries: [ScheduledTripActivity] = []

        for day in TripData.days {
            let dayComponents = TripDate.calendar.dateComponents([.year, .month, .day], from: day.date)
            var previousDate: Date?
            for (index, activity) in day.activities.enumerated() {
                let time = timeComponents(activity.time, index: index)
                var components = DateComponents(
                    year: dayComponents.year,
                    month: dayComponents.month,
                    day: dayComponents.day,
                    hour: time.hour,
                    minute: time.minute
                )
                var scheduled = calendar.date(from: components) ?? day.date
                if let previousDate, scheduled < previousDate {
                    components.day = (components.day ?? 1) + 1
                    scheduled = calendar.date(from: components) ?? scheduled.addingTimeInterval(86_400)
                }
                previousDate = scheduled
                entries.append(.init(day: day, activity: activity, date: scheduled))
            }
        }
        return entries.sorted { $0.date < $1.date }
    }

    private static func timeComponents(_ text: String, index: Int) -> (hour: Int, minute: Int) {
        let parts = text.split(separator: ":")
        if parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) {
            return (hour, minute)
        }
        switch text.lowercased() {
        case "manhã": return (9, index * 5)
        case "abertura": return (8, 0)
        case "dia todo": return (9, 0)
        case "noite": return (19, 0)
        default: return (9 + index * 2, 0)
        }
    }
}
