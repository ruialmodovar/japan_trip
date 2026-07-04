import Foundation
import SwiftUI

struct ActivityRating: Identifiable, Codable, Hashable {
    let activityID: String
    let userID: UUID
    let email: String
    let stars: Int
    let updatedAt: String?

    var id: String { "\(activityID)-\(userID.uuidString)" }

    enum CodingKeys: String, CodingKey {
        case activityID = "activity_id"
        case userID = "user_id"
        case email, stars
        case updatedAt = "updated_at"
    }
}

struct ActivityRatingSummary: Identifiable, Hashable {
    let activity: TripActivity
    let average: Double
    let count: Int

    var id: String { activity.id }
}

protocol ActivityRatingServicing {
    func fetch(accessToken: String) async throws -> [ActivityRating]
    func upsert(activityID: String, userID: UUID, email: String, stars: Int, accessToken: String) async throws
}

struct SupabaseActivityRatingService: ActivityRatingServicing {
    private let projectURL = URL(string: "https://oiprckdaqhgganwtxcui.supabase.co")!
    private let publishableKey = "sb_publishable_GYwIq70ROI6Rx6LzMyASJA_4DtkY5hL"
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func fetch(accessToken: String) async throws -> [ActivityRating] {
        var components = URLComponents(url: projectURL.appending(path: "rest/v1/trip_activity_ratings"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "select", value: "activity_id,user_id,email,stars,updated_at"),
            .init(name: "order", value: "updated_at.desc")
        ]
        var request = authorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "GET"
        return try JSONDecoder().decode([ActivityRating].self, from: try await perform(request))
    }

    func upsert(activityID: String, userID: UUID, email: String, stars: Int, accessToken: String) async throws {
        var components = URLComponents(url: projectURL.appending(path: "rest/v1/trip_activity_ratings"), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "on_conflict", value: "activity_id,user_id")]
        var request = authorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(ActivityRating(
            activityID: activityID,
            userID: userID,
            email: email,
            stars: stars,
            updatedAt: nil
        ))
        _ = try await perform(request)
    }

    private func authorizedRequest(url: URL, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ActivityRatingError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            if http.statusCode == 401 { throw SupabaseAuthError.invalidCredentials }
            let message = (try? JSONDecoder().decode(ActivityRatingServiceError.self, from: data).message)
            throw ActivityRatingError.server(message ?? "Não foi possível sincronizar a avaliação.")
        }
        return data
    }
}

@MainActor
final class ActivityRatingStore: ObservableObject {
    @Published private(set) var ratings: [ActivityRating] = []
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncedAt: Date?
    @Published var errorMessage: String?

    private let service: any ActivityRatingServicing
    private let defaults: UserDefaults
    private let cacheKey = "activityRatings.cache"
    private let pendingKey = "activityRatings.pendingRatingIDs"
    private var pendingRatingIDs: Set<String>

    init(
        service: any ActivityRatingServicing = SupabaseActivityRatingService(),
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.defaults = defaults
        pendingRatingIDs = Set(defaults.stringArray(forKey: pendingKey) ?? [])
        if let data = defaults.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([ActivityRating].self, from: data) {
            ratings = cached
        }
    }

    func rating(for activityID: String, email: String?) -> Int? {
        guard let email else { return nil }
        return ratings.first { $0.activityID == activityID && $0.email == email }?.stars
    }

    func summary(for activityID: String) -> (average: Double, count: Int)? {
        let values = ratings.filter { $0.activityID == activityID }.map(\.stars)
        guard !values.isEmpty else { return nil }
        return (Double(values.reduce(0, +)) / Double(values.count), values.count)
    }

    var ranking: [ActivityRatingSummary] {
        TripData.days.flatMap(\.activities).compactMap { activity in
            guard let summary = summary(for: activity.id) else { return nil }
            return .init(activity: activity, average: summary.average, count: summary.count)
        }
        .sorted {
            if $0.average == $1.average { return $0.count > $1.count }
            return $0.average > $1.average
        }
    }

    func rate(activity: TripActivity, stars: Int, authentication: AuthenticationManager) async {
        guard 1...5 ~= stars,
              let userID = authentication.authenticatedUserID,
              let email = authentication.authenticatedEmail else { return }
        ratings.removeAll { $0.activityID == activity.id && $0.userID == userID }
        let rating = ActivityRating(activityID: activity.id, userID: userID, email: email, stars: stars, updatedAt: nil)
        ratings.append(rating)
        pendingRatingIDs.insert(rating.id)
        save()
        await sync(authentication: authentication)
    }

    func sync(authentication: AuthenticationManager) async {
        guard authentication.isAuthenticated, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let token = try await authentication.accessTokenForAPI()
            guard let userID = authentication.authenticatedUserID,
                  let email = authentication.authenticatedEmail else { return }
            for rating in ratings where rating.userID == userID && pendingRatingIDs.contains(rating.id) {
                try await service.upsert(
                    activityID: rating.activityID,
                    userID: userID,
                    email: email,
                    stars: rating.stars,
                    accessToken: token
                )
                pendingRatingIDs.remove(rating.id)
            }
            let remote = try await service.fetch(accessToken: token)
            let stillPending = ratings.filter { pendingRatingIDs.contains($0.id) }
            let pendingIDs = Set(stillPending.map(\.id))
            ratings = remote.filter { !pendingIDs.contains($0.id) } + stillPending
            lastSyncedAt = Date()
            errorMessage = nil
            save()
        } catch {
            errorMessage = "Avaliação guardada offline. Sincronização pendente: \(error.localizedDescription)"
            save()
        }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(ratings), forKey: cacheKey)
        defaults.set(Array(pendingRatingIDs), forKey: pendingKey)
    }
}

private struct ActivityRatingServiceError: Decodable { let message: String? }
private enum ActivityRatingError: LocalizedError {
    case invalidResponse
    case server(String)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Resposta inválida do serviço de avaliações."
        case .server(let message): message
        }
    }
}
