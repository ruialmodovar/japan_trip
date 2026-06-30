import SwiftUI
import UserNotifications

struct TripNotification: Identifiable, Hashable {
    enum Kind: String { case agenda, reminder, hotel, flight, weather, special }

    let id: String
    let title: String
    let body: String
    let date: Date
    let kind: Kind
}

enum NotificationPreferenceKey {
    static let agenda = "notifications.agenda"
    static let reminders = "notifications.reminders"
    static let hotels = "notifications.hotels"
    static let weather = "notifications.weather"
}

enum TripNotificationPlanner {
    static func makePlan(
        now: Date = Date(),
        defaults: UserDefaults = .standard,
        weatherSnapshots: [City: WeatherSnapshot] = [:]
    ) -> [TripNotification] {
        var notifications: [TripNotification] = []

        if defaults.object(forKey: NotificationPreferenceKey.agenda) as? Bool ?? true {
            notifications += dailyAgenda(now: now)
        }
        if defaults.object(forKey: NotificationPreferenceKey.reminders) as? Bool ?? true {
            notifications += activityReminders(now: now)
            notifications += flightReminders(now: now)
            notifications.append(disneyReminder)
        }
        if defaults.object(forKey: NotificationPreferenceKey.hotels) as? Bool ?? true {
            notifications += checkoutReminders(now: now)
        }
        if defaults.object(forKey: NotificationPreferenceKey.weather) as? Bool ?? true {
            notifications += rainReminders(from: weatherSnapshots, now: now)
        }

        let future = notifications.filter { $0.date > now }.sorted { $0.date < $1.date }
        let essential = future.filter { $0.kind != .weather }.prefix(52)
        let weather = future.filter { $0.kind == .weather }.prefix(8)
        return (Array(essential) + Array(weather)).sorted { $0.date < $1.date }
    }

    private static func dailyAgenda(now: Date) -> [TripNotification] {
        TripData.days.compactMap { day in
            guard let date = makeDate(dayID: day.id, hour: 7, minute: 30, timeZone: timeZone(for: day)) else { return nil }
            let firstSteps = day.activities.prefix(3).map { "\($0.time) \($0.title)" }.joined(separator: " · ")
            return TripNotification(
                id: "agenda-\(day.id)",
                title: "Hoje: \(day.title)",
                body: firstSteps,
                date: date,
                kind: .agenda
            )
        }
    }

    private static func activityReminders(now: Date) -> [TripNotification] {
        TripData.days.flatMap { day in
            day.activities.compactMap { activity in
                guard activity.isCritical,
                      activity.kind != .flight,
                      let (hour, minute) = clock(from: activity.time),
                      let eventDate = makeDate(dayID: day.id, hour: hour, minute: minute, timeZone: timeZone(for: day)),
                      let alertDate = Calendar.current.date(byAdding: .minute, value: -40, to: eventDate) else { return nil }
                return TripNotification(
                    id: "activity-\(activity.id)",
                    title: "Próximo compromisso em 40 minutos",
                    body: "\(activity.time) · \(activity.title). \(activity.details)",
                    date: alertDate,
                    kind: .reminder
                )
            }
        }
    }

    private static func flightReminders(now: Date) -> [TripNotification] {
        let flights: [(id: String, day: Int, hour: Int, minute: Int, zone: String, route: String)] = [
            ("EK262", 8, 1, 5, "America/Sao_Paulo", "GRU → DXB"),
            ("EK312", 12, 7, 40, "Asia/Dubai", "DXB → HND"),
            ("EK317", 25, 23, 45, "Asia/Tokyo", "KIX → DXB")
        ]
        return flights.compactMap { flight in
            guard let departure = makeDate(day: flight.day, hour: flight.hour, minute: flight.minute, timeZone: flight.zone),
                  let alert = Calendar.current.date(byAdding: .hour, value: -3, to: departure) else { return nil }
            return .init(
                id: "flight-\(flight.id)",
                title: "Hora de seguir para o aeroporto",
                body: "O voo \(flight.id) \(flight.route) parte às \(String(format: "%02d:%02d", flight.hour, flight.minute)). Confere passaportes e bagagem.",
                date: alert,
                kind: .flight
            )
        }
    }

    private static var disneyReminder: TripNotification {
        .init(
            id: "special-disneysea",
            title: "DisneySea é amanhã 🎢",
            body: "Ingressos no app, baterias carregadas e saída do hotel às 07:00.",
            date: makeDate(day: 15, hour: 18, minute: 0, timeZone: "Asia/Tokyo")!,
            kind: .special
        )
    }

    private static func checkoutReminders(now: Date) -> [TripNotification] {
        let checkouts: [(id: String, hotel: String, day: Int, time: String, zone: String)] = [
            ("taj", "Taj Dubai", 12, "12:00", "Asia/Dubai"),
            ("blossom", "The Blossom Hibiya", 18, "11:00", "Asia/Tokyo"),
            ("doubletree", "DoubleTree Kyoto", 23, "11:00", "Asia/Tokyo"),
            ("osaka", "Osaka Station Hotel", 25, "12:00", "Asia/Tokyo")
        ]
        return checkouts.compactMap { checkout in
            guard let date = makeDate(day: checkout.day - 1, hour: 18, minute: 0, timeZone: checkout.zone) else { return nil }
            return .init(
                id: "checkout-\(checkout.id)",
                title: "Check-out amanhã às \(checkout.time)",
                body: "\(checkout.hotel): organizar malas, documentos e confirmar o transporte.",
                date: date,
                kind: .hotel
            )
        }
    }

    private static func rainReminders(from snapshots: [City: WeatherSnapshot], now: Date) -> [TripNotification] {
        snapshots.flatMap { (city, snapshot) -> [TripNotification] in
            let zone = city == .dubai ? "Asia/Dubai" : "Asia/Tokyo"
            return snapshot.daily.time.enumerated().compactMap { (index, dateText) -> TripNotification? in
                guard snapshot.daily.precipitationProbability.indices.contains(index),
                      snapshot.daily.precipitationProbability[index] >= 40,
                      let date = makeDate(isoDate: dateText, hour: 7, minute: 0, timeZone: zone) else { return nil }
                return TripNotification(
                    id: "rain-\(city.id)-\(dateText)",
                    title: "Hoje pode chover ☔️",
                    body: "Probabilidade de chuva em \(city.rawValue): \(snapshot.daily.precipitationProbability[index])%. Leva um guarda-chuva.",
                    date: date,
                    kind: .weather
                )
            }
        }
    }

    private static func timeZone(for day: TripDay) -> String {
        switch day.id {
        case "2026-07-08": "America/Sao_Paulo"
        case "2026-07-09"..."2026-07-11": "Asia/Dubai"
        case "2026-07-12": "Asia/Dubai"
        default: "Asia/Tokyo"
        }
    }

    private static func clock(from text: String) -> (Int, Int)? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return (hour, minute)
    }

    private static func makeDate(dayID: String, hour: Int, minute: Int, timeZone: String) -> Date? {
        makeDate(isoDate: dayID, hour: hour, minute: minute, timeZone: timeZone)
    }

    private static func makeDate(day: Int, hour: Int, minute: Int, timeZone: String) -> Date? {
        makeDate(isoDate: String(format: "2026-07-%02d", day), hour: hour, minute: minute, timeZone: timeZone)
    }

    private static func makeDate(isoDate: String, hour: Int, minute: Int, timeZone: String) -> Date? {
        let parts = isoDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let zone = TimeZone(identifier: timeZone) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(timeZone: zone, year: parts[0], month: parts[1], day: parts[2], hour: hour, minute: minute))
    }
}

@MainActor
final class NotificationManager: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var pendingCount = 0
    @Published private(set) var isScheduling = false
    @Published var errorMessage: String?

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func refreshStatus() async {
        authorizationStatus = await center.notificationSettings().authorizationStatus
        pendingCount = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("trip.") }.count
    }

    func enableAndSchedule(weatherSnapshots: [City: WeatherSnapshot]) async {
        isScheduling = true
        errorMessage = nil
        defer { isScheduling = false }

        do {
            if authorizationStatus == .notDetermined {
                _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            }
            await refreshStatus()
            guard authorizationStatus == .authorized || authorizationStatus == .provisional else {
                errorMessage = "As notificações estão desativadas nas Definições do iPhone."
                return
            }

            let plan = TripNotificationPlanner.makePlan(weatherSnapshots: weatherSnapshots)
            center.removePendingNotificationRequests(withIdentifiers: await pendingIdentifiers())
            for item in plan {
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.body
                content.sound = .default
                content.userInfo = ["kind": item.kind.rawValue, "notificationID": item.id]
                let components = Calendar.current.dateComponents(in: TimeZone.current, from: item.date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try await center.add(.init(identifier: "trip.\(item.id)", content: content, trigger: trigger))
            }
            await refreshStatus()
        } catch {
            errorMessage = "Não foi possível configurar os avisos. Tente novamente."
        }
    }

    func disable() async {
        center.removePendingNotificationRequests(withIdentifiers: await pendingIdentifiers())
        await refreshStatus()
    }

    private func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("trip.") }
    }
}

struct NotificationsView: View {
    @EnvironmentObject private var navigation: AppNavigationState
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var weather: WeatherStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(NotificationPreferenceKey.agenda) private var agenda = true
    @AppStorage(NotificationPreferenceKey.reminders) private var reminders = true
    @AppStorage(NotificationPreferenceKey.hotels) private var hotels = true
    @AppStorage(NotificationPreferenceKey.weather) private var weatherAlerts = true

    private var preview: [TripNotification] {
        Array(TripNotificationPlanner.makePlan(weatherSnapshots: weather.snapshots).prefix(8))
    }

    var body: some View {
        List {
            Section {
                statusHeader
            }
            Section("Tipos de aviso") {
                Toggle("Agenda de cada dia", systemImage: "calendar", isOn: $agenda)
                Toggle("Próximos passos e compromissos", systemImage: "clock.badge.fill", isOn: $reminders)
                Toggle("Check-outs dos hotéis", systemImage: "bed.double.fill", isOn: $hotels)
                Toggle("Chuva e guarda-chuva", systemImage: "cloud.rain.fill", isOn: $weatherAlerts)
            }
            Section("Próximos avisos") {
                if preview.isEmpty {
                    Text("Nenhum aviso futuro com as opções atuais.").foregroundStyle(.secondary)
                } else {
                    ForEach(preview) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.subheadline.weight(.semibold))
                            Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                            Text(item.body).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            Section {
                Button(role: .destructive) {
                    Task { await notifications.disable() }
                } label: {
                    Label("Remover avisos agendados", systemImage: "bell.slash.fill")
                }
            }
        }
        .navigationTitle("Notificações")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                    navigation.goHome()
                } label: { Label("Início", systemImage: "house.fill") }
            }
            ToolbarItem(placement: .topBarTrailing) { Button("Fechar") { dismiss() } }
        }
        .task { await notifications.refreshStatus() }
        .onChange(of: agenda) { _, _ in rescheduleIfAuthorized() }
        .onChange(of: reminders) { _, _ in rescheduleIfAuthorized() }
        .onChange(of: hotels) { _, _ in rescheduleIfAuthorized() }
        .onChange(of: weatherAlerts) { _, _ in rescheduleIfAuthorized() }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(statusTitle, systemImage: statusSymbol)
                .font(.headline)
                .foregroundStyle(statusColor)
            Text(statusMessage).font(.subheadline).foregroundStyle(.secondary)
            if notifications.authorizationStatus == .denied {
                Button("Abrir Definições do iPhone") {
                    openURL(URL(string: UIApplication.openNotificationSettingsURLString)!)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    Task { await notifications.enableAndSchedule(weatherSnapshots: weather.snapshots) }
                } label: {
                    HStack {
                        if notifications.isScheduling { ProgressView().tint(.white) }
                        Label("Ativar e agendar avisos", systemImage: "bell.badge.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(notifications.isScheduling)
            }
            if let error = notifications.errorMessage {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 8)
    }

    private var statusTitle: String {
        switch notifications.authorizationStatus {
        case .authorized, .provisional: "\(notifications.pendingCount) avisos agendados"
        case .denied: "Notificações desativadas"
        default: "Notificações ainda não ativadas"
        }
    }
    private var statusMessage: String {
        notifications.authorizationStatus == .authorized
            ? "Os avisos são gerados no aparelho e funcionam mesmo sem internet."
            : "O iPhone pedirá permissão antes de mostrar qualquer aviso."
    }
    private var statusSymbol: String { notifications.authorizationStatus == .authorized ? "bell.badge.fill" : "bell.slash.fill" }
    private var statusColor: Color { notifications.authorizationStatus == .authorized ? .green : .orange }

    private func rescheduleIfAuthorized() {
        guard notifications.authorizationStatus == .authorized else { return }
        Task { await notifications.enableAndSchedule(weatherSnapshots: weather.snapshots) }
    }
}
