import Foundation

struct SharedPhotoRecord: Codable, Hashable {
    let id: UUID
    let ownerUserID: UUID
    let ownerEmail: String
    let storagePath: String
    let caption: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserID = "owner_user_id"
        case ownerEmail = "owner_email"
        case storagePath = "storage_path"
        case caption
        case createdAt = "created_at"
    }
}

protocol TripSharingServicing {
    func fetchExpenses(accessToken: String) async throws -> [TripExpense]
    func upsertExpense(_ expense: TripExpense, ownerUserID: UUID, ownerEmail: String, accessToken: String) async throws
    func deleteExpense(id: UUID, accessToken: String) async throws

    func fetchPhotos(accessToken: String) async throws -> [SharedPhotoRecord]
    func uploadPhoto(_ data: Data, path: String, accessToken: String) async throws
    func downloadPhoto(path: String, accessToken: String) async throws -> Data
    func upsertPhoto(_ record: SharedPhotoRecord, accessToken: String) async throws
    func deletePhoto(id: UUID, path: String, accessToken: String) async throws
}

struct SupabaseTripSharingService: TripSharingServicing {
    private let projectURL = URL(string: "https://oiprckdaqhgganwtxcui.supabase.co")!
    private let publishableKey = "sb_publishable_GYwIq70ROI6Rx6LzMyASJA_4DtkY5hL"
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        encoder = JSONEncoder.supabase
        decoder = JSONDecoder.supabase
    }

    func fetchExpenses(accessToken: String) async throws -> [TripExpense] {
        var components = URLComponents(url: projectURL.appending(path: "rest/v1/trip_expenses"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "select", value: "id,title,amount,currency,expense_date,category,payer_email,participant_emails,note,owner_email"),
            .init(name: "order", value: "expense_date.desc,created_at.desc")
        ]
        var request = authorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "GET"
        let data = try await perform(request)
        return try decoder.decode([ExpenseRecord].self, from: data).compactMap(\.expense)
    }

    func upsertExpense(_ expense: TripExpense, ownerUserID: UUID, ownerEmail: String, accessToken: String) async throws {
        var components = URLComponents(url: projectURL.appending(path: "rest/v1/trip_expenses"), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "on_conflict", value: "id")]
        var request = authorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(ExpenseRecord(expense: expense, ownerUserID: ownerUserID, ownerEmail: ownerEmail))
        _ = try await perform(request)
    }

    func deleteExpense(id: UUID, accessToken: String) async throws {
        var components = URLComponents(url: projectURL.appending(path: "rest/v1/trip_expenses"), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "id", value: "eq.\(id.uuidString)")]
        var request = authorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "DELETE"
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        _ = try await perform(request)
    }

    func fetchPhotos(accessToken: String) async throws -> [SharedPhotoRecord] {
        var components = URLComponents(url: projectURL.appending(path: "rest/v1/trip_photos"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "select", value: "id,owner_user_id,owner_email,storage_path,caption,created_at"),
            .init(name: "order", value: "created_at.desc")
        ]
        var request = authorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "GET"
        return try decoder.decode([SharedPhotoRecord].self, from: try await perform(request))
    }

    func uploadPhoto(_ data: Data, path: String, accessToken: String) async throws {
        let url = projectURL.appending(path: "storage/v1/object/trip-photos/\(path)")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = data
        _ = try await perform(request)
    }

    func downloadPhoto(path: String, accessToken: String) async throws -> Data {
        let url = projectURL.appending(path: "storage/v1/object/authenticated/trip-photos/\(path)")
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "GET"
        return try await perform(request)
    }

    func upsertPhoto(_ record: SharedPhotoRecord, accessToken: String) async throws {
        var components = URLComponents(url: projectURL.appending(path: "rest/v1/trip_photos"), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "on_conflict", value: "id")]
        var request = authorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(record)
        _ = try await perform(request)
    }

    func deletePhoto(id: UUID, path: String, accessToken: String) async throws {
        var metadata = URLComponents(url: projectURL.appending(path: "rest/v1/trip_photos"), resolvingAgainstBaseURL: false)!
        metadata.queryItems = [.init(name: "id", value: "eq.\(id.uuidString)")]
        var metadataRequest = authorizedRequest(url: metadata.url!, accessToken: accessToken)
        metadataRequest.httpMethod = "DELETE"
        _ = try await perform(metadataRequest)

        let objectURL = projectURL.appending(path: "storage/v1/object/trip-photos/\(path)")
        var objectRequest = authorizedRequest(url: objectURL, accessToken: accessToken)
        objectRequest.httpMethod = "DELETE"
        _ = try await perform(objectRequest)
    }

    private func authorizedRequest(url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TripSharingError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            if http.statusCode == 401 { throw SupabaseAuthError.invalidCredentials }
            let message = (try? JSONDecoder().decode(SharingServiceError.self, from: data).message)
            throw TripSharingError.server(message ?? "Não foi possível sincronizar os dados da viagem.")
        }
        return data
    }
}

private struct ExpenseRecord: Codable {
    let id: UUID
    let title: String
    let amount: Double
    let currency: String
    let expenseDate: Date
    let category: String
    let payerEmail: String
    let participantEmails: [String]
    let note: String
    let ownerUserID: UUID?
    let ownerEmail: String

    init(expense: TripExpense, ownerUserID: UUID, ownerEmail: String) {
        id = expense.id
        title = expense.title
        amount = expense.amount
        currency = expense.currency.rawValue
        expenseDate = expense.date
        category = expense.category.rawValue
        payerEmail = expense.payerEmail
        participantEmails = expense.participantEmails.sorted()
        note = expense.note
        self.ownerUserID = ownerUserID
        self.ownerEmail = expense.createdByEmail ?? ownerEmail
    }

    var expense: TripExpense? {
        guard let currency = TripCurrency(rawValue: currency),
              let category = TripExpense.Category(rawValue: category) else { return nil }
        return .init(
            id: id, title: title, amount: amount, currency: currency, date: expenseDate,
            category: category, payerEmail: payerEmail, participantEmails: Set(participantEmails),
            note: note, createdByEmail: ownerEmail
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, title, amount, currency, category, note
        case expenseDate = "expense_date"
        case payerEmail = "payer_email"
        case participantEmails = "participant_emails"
        case ownerUserID = "owner_user_id"
        case ownerEmail = "owner_email"
    }
}

private struct SharingServiceError: Decodable { let message: String? }
private enum TripSharingError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Resposta inválida do serviço de partilha."
        case .server(let message): message
        }
    }
}

private extension JSONEncoder {
    static var supabase: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}

private extension JSONDecoder {
    static var supabase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
