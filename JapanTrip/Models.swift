import Foundation
import SwiftUI

struct TripParticipant: Identifiable, Hashable {
    let email: String
    let name: String

    var id: String { email }
    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }

    static let all: [TripParticipant] = [
        .init(email: "ruialmodovar@gmail.com", name: "Rui Coelho"),
        .init(email: "ana.botinas@gmail.com", name: "Ana Botinas Coelho"),
        .init(email: "raquelbotinascoelho@gmail.com", name: "Raquel Botinas Coelho"),
        .init(email: "mateus80@gmail.com", name: "Pedro Mateus"),
        .init(email: "luestrellado@gmail.com", name: "Luciana Estrellado"),
        .init(email: "biaestrellado@gmail.com", name: "Beatriz Mateus")
    ]

    static func participant(for email: String) -> TripParticipant? {
        let canonical = normalizedEmail(email)
        return all.first { normalizedEmail($0.email) == canonical }
    }

    static func normalizedEmail(_ email: String) -> String {
        email
            .components(separatedBy: .whitespacesAndNewlines).joined()
            .components(separatedBy: .controlCharacters).joined()
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .lowercased()
    }
}

enum City: String, CaseIterable, Codable, Identifiable {
    case dubai = "Dubai"
    case tokyo = "Tóquio"
    case kyoto = "Kyoto"
    case osaka = "Osaka"
    case travel = "Em trânsito"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .dubai: .orange
        case .tokyo: .red
        case .kyoto: .purple
        case .osaka: .blue
        case .travel: .teal
        }
    }

    var symbol: String {
        switch self {
        case .dubai: "sun.max.fill"
        case .tokyo: "building.2.fill"
        case .kyoto: "building.columns.fill"
        case .osaka: "sparkles"
        case .travel: "airplane"
        }
    }
}

enum ActivityKind: String, Codable {
    case flight, hotel, food, attraction, transport, shopping, tour, luggage, rest

    var symbol: String {
        switch self {
        case .flight: "airplane"
        case .hotel: "bed.double.fill"
        case .food: "fork.knife"
        case .attraction: "camera.fill"
        case .transport: "tram.fill"
        case .shopping: "bag.fill"
        case .tour: "figure.walk"
        case .luggage: "suitcase.fill"
        case .rest: "moon.zzz.fill"
        }
    }
}

struct TripActivity: Identifiable, Codable, Hashable {
    let id: String
    let time: String
    let title: String
    let details: String
    let kind: ActivityKind
    var locationQuery: String?
    var isCritical: Bool = false
}

struct TripDay: Identifiable, Codable, Hashable {
    let id: String
    let date: Date
    let city: City
    let title: String
    let note: String?
    let activities: [TripActivity]
}

enum ReservationStatus: String, Codable {
    case confirmed = "Confirmado"
    case booked = "Reservado"
    case pending = "Pendente"

    var color: Color {
        switch self {
        case .confirmed: .green
        case .booked: .blue
        case .pending: .orange
        }
    }
}

struct Reservation: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let dateText: String
    let status: ReservationStatus
    let symbol: String
    let sensitiveNote: String?
}

struct ChecklistItem: Identifiable, Codable, Hashable {
    enum Scope: String, CaseIterable, Codable, Identifiable {
        case general
        case personal

        var id: String { rawValue }
        var title: String { self == .general ? "Geral" : "Pessoal" }
        var subtitle: String { self == .general ? "Partilhada com todo o grupo" : "Visível apenas para ti" }
        var symbol: String { self == .general ? "person.3.fill" : "person.fill" }
    }

    enum Section: String, CaseIterable, Codable {
        case urgent = "Fazer agora"
        case before = "Antes da viagem"
        case during = "Durante a viagem"
        case booked = "Já reservado"
    }

    let id: String
    let title: String
    let section: Section
    let scope: Scope

    init(id: String, title: String, section: Section, scope: Scope = .general) {
        self.id = id
        self.title = title
        self.section = section
        self.scope = scope
    }

    enum CodingKeys: String, CodingKey { case id, title, section, scope }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        section = try container.decode(Section.self, forKey: .section)
        scope = try container.decodeIfPresent(Scope.self, forKey: .scope) ?? .general
    }
}

enum TripDate {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    static func make(_ day: Int, month: Int = 7, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}
