import CoreLocation
import MapKit
import SwiftUI

struct SharedParticipantLocation: Identifiable, Decodable, Hashable {
    let userID: UUID
    let email: String
    let latitude: Double
    let longitude: Double
    let accuracy: Double?
    let updatedAt: String

    var id: UUID { userID }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var participant: TripParticipant? { TripParticipant.participant(for: email) }
    var updatedDate: Date? {
        ISO8601DateFormatter.locationSharing.date(from: updatedAt)
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case email, latitude, longitude, accuracy
        case updatedAt = "updated_at"
    }
}

private extension ISO8601DateFormatter {
    static let locationSharing: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

protocol LocationSharingServicing {
    func fetchLocations(accessToken: String) async throws -> [SharedParticipantLocation]
    func upsertLocation(userID: UUID, email: String, location: CLLocation, accessToken: String) async throws
    func removeLocation(userID: UUID, accessToken: String) async throws
}

struct SupabaseLocationSharingService: LocationSharingServicing {
    private let projectURL = URL(string: "https://oiprckdaqhgganwtxcui.supabase.co")!
    private let publishableKey = "sb_publishable_GYwIq70ROI6Rx6LzMyASJA_4DtkY5hL"
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func fetchLocations(accessToken: String) async throws -> [SharedParticipantLocation] {
        var components = URLComponents(url: projectURL.appending(path: "rest/v1/trip_locations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "select", value: "user_id,email,latitude,longitude,accuracy,updated_at"),
            .init(name: "order", value: "updated_at.desc")
        ]
        var request = authorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "GET"
        let data = try await perform(request)
        return try JSONDecoder().decode([SharedParticipantLocation].self, from: data)
    }

    func upsertLocation(userID: UUID, email: String, location: CLLocation, accessToken: String) async throws {
        var components = URLComponents(url: projectURL.appending(path: "rest/v1/trip_locations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "on_conflict", value: "user_id")]
        var request = authorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "POST"
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(LocationPayload(
            userID: userID,
            email: email,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracy: max(0, location.horizontalAccuracy)
        ))
        _ = try await perform(request)
    }

    func removeLocation(userID: UUID, accessToken: String) async throws {
        var components = URLComponents(url: projectURL.appending(path: "rest/v1/trip_locations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "user_id", value: "eq.\(userID.uuidString)")]
        var request = authorizedRequest(url: components.url!, accessToken: accessToken)
        request.httpMethod = "DELETE"
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
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
        guard let http = response as? HTTPURLResponse else { throw LocationSharingError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            if http.statusCode == 401 { throw SupabaseAuthError.invalidCredentials }
            let message = (try? JSONDecoder().decode(LocationServiceError.self, from: data).message)
            throw LocationSharingError.server(message ?? "Serviço de localização indisponível.")
        }
        return data
    }
}

private struct LocationPayload: Encodable {
    let userID: UUID
    let email: String
    let latitude: Double
    let longitude: Double
    let accuracy: Double

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case email, latitude, longitude, accuracy
    }
}

private struct LocationServiceError: Decodable { let message: String? }
private enum LocationSharingError: LocalizedError {
    case invalidResponse
    case server(String)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Resposta inválida do serviço de localização."
        case .server(let message): message
        }
    }
}

@MainActor
final class LocationSharingManager: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var isSharing: Bool
    @Published private(set) var locations: [SharedParticipantLocation] = []
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let locationManager: CLLocationManager
    private let service: any LocationSharingServicing
    private let sharingKey = "locationSharing.enabled"
    private weak var authentication: AuthenticationManager?
    private var lastUploadedLocation: CLLocation?
    private var lastUploadDate: Date?

    init(
        locationManager: CLLocationManager = CLLocationManager(),
        service: any LocationSharingServicing = SupabaseLocationSharingService(),
        defaults: UserDefaults = .standard
    ) {
        self.locationManager = locationManager
        self.service = service
        self.isSharing = defaults.bool(forKey: sharingKey)
        self.authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 50
    }

    func setSharing(_ enabled: Bool, authentication: AuthenticationManager) async {
        self.authentication = authentication
        errorMessage = nil
        if enabled {
            guard authentication.authenticatedUserID != nil else {
                errorMessage = "Sessão inválida. Entre novamente."
                return
            }
            isSharing = true
            UserDefaults.standard.set(true, forKey: sharingKey)
            switch locationManager.authorizationStatus {
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                locationManager.startUpdatingLocation()
            case .denied, .restricted:
                isSharing = false
                UserDefaults.standard.set(false, forKey: sharingKey)
                errorMessage = "Permita o acesso à localização nas Definições do iPhone."
            @unknown default: break
            }
        } else {
            isSharing = false
            UserDefaults.standard.set(false, forKey: sharingKey)
            locationManager.stopUpdatingLocation()
            await removeOwnLocation(authentication: authentication)
        }
    }

    func resumeIfNeeded(authentication: AuthenticationManager) {
        self.authentication = authentication
        if isSharing, [.authorizedWhenInUse, .authorizedAlways].contains(locationManager.authorizationStatus) {
            locationManager.startUpdatingLocation()
        }
    }

    func pauseUpdates() {
        locationManager.stopUpdatingLocation()
    }

    func refresh(authentication: AuthenticationManager) async {
        guard authentication.isAuthenticated else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let token = try await authentication.accessTokenForAPI()
            locations = try await service.fetchLocations(accessToken: token)
                .filter {
                    TripParticipant.participant(for: $0.email) != nil
                    && ($0.updatedDate.map { Date().timeIntervalSince($0) < 21_600 } ?? false)
                }
        } catch {
            errorMessage = "Não foi possível atualizar as localizações."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isSharing, [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) {
            manager.startUpdatingLocation()
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            isSharing = false
            UserDefaults.standard.set(false, forKey: sharingKey)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations newLocations: [CLLocation]) {
        guard isSharing, let location = newLocations.last, location.horizontalAccuracy >= 0 else { return }
        let recentlyUploaded = lastUploadDate.map { Date().timeIntervalSince($0) < 45 } ?? false
        let barelyMoved = lastUploadedLocation.map { location.distance(from: $0) < 50 } ?? false
        guard !(recentlyUploaded && barelyMoved), let authentication else { return }
        lastUploadDate = Date()
        lastUploadedLocation = location
        Task { await upload(location, authentication: authentication) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard (error as? CLError)?.code != .locationUnknown else { return }
        errorMessage = "Não foi possível obter a localização atual."
    }

    private func upload(_ location: CLLocation, authentication: AuthenticationManager) async {
        guard let userID = authentication.authenticatedUserID,
              let email = authentication.authenticatedEmail else { return }
        do {
            let token = try await authentication.accessTokenForAPI()
            try await service.upsertLocation(userID: userID, email: email, location: location, accessToken: token)
            await refresh(authentication: authentication)
        } catch {
            errorMessage = "Não foi possível partilhar a localização."
        }
    }

    private func removeOwnLocation(authentication: AuthenticationManager) async {
        guard let userID = authentication.authenticatedUserID else { return }
        do {
            let token = try await authentication.accessTokenForAPI()
            try await service.removeLocation(userID: userID, accessToken: token)
            locations.removeAll { $0.userID == userID }
        } catch {
            errorMessage = "A partilha foi desligada no aparelho, mas não foi possível remover o último ponto do servidor. Tente novamente com internet."
        }
    }
}

struct LocationSharingView: View {
    @EnvironmentObject private var navigation: AppNavigationState
    @EnvironmentObject private var authentication: AuthenticationManager
    @EnvironmentObject private var sharing: LocationSharingManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var mapPosition: MapCameraPosition = .automatic

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                sharingCard
                mapCard
                participantList
                privacyCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Localização do grupo")
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
        .task {
            sharing.resumeIfNeeded(authentication: authentication)
            await sharing.refresh(authentication: authentication)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await sharing.refresh(authentication: authentication)
            }
        }
    }

    private var sharingCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Toggle(isOn: Binding(
                get: { sharing.isSharing },
                set: { value in Task { await sharing.setSharing(value, authentication: authentication) } }
            )) {
                Label(sharing.isSharing ? "A partilhar a minha localização" : "Partilha desligada", systemImage: sharing.isSharing ? "location.fill" : "location.slash.fill")
                    .font(.headline)
            }
            .tint(.green)
            Text(sharing.isSharing
                 ? "A posição aproximada é atualizada enquanto o app está aberto."
                 : "Ninguém recebe a tua posição. Ao desligar, o último ponto é removido do Supabase.")
                .font(.subheadline).foregroundStyle(.secondary)
            if sharing.authorizationStatus == .denied {
                Button("Abrir Definições") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                    .buttonStyle(.bordered)
            }
            if let error = sharing.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }

    private var mapCard: some View {
        Map(position: $mapPosition) {
            ForEach(sharing.locations) { location in
                Marker(location.participant?.firstName ?? "Participante", coordinate: location.coordinate)
                    .tint(location.email == authentication.authenticatedEmail ? .green : .indigo)
            }
        }
        .mapControls { MapCompass(); MapScaleView(); MapUserLocationButton() }
        .frame(height: 330)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(alignment: .topTrailing) {
            Button { Task { await sharing.refresh(authentication: authentication) } } label: {
                if sharing.isLoading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: Circle())
            .padding(10)
        }
    }

    private var participantList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PARTICIPANTES VISÍVEIS").font(.caption.bold()).tracking(1).foregroundStyle(.secondary)
            if sharing.locations.isEmpty {
                ContentUnavailableView("Ninguém está visível", systemImage: "person.3", description: Text("Cada pessoa precisa entrar no app e ativar a partilha."))
            } else {
                ForEach(sharing.locations) { location in
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(location.participant?.name ?? location.email).font(.subheadline.weight(.semibold))
                            Text(lastSeen(location.updatedDate)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if location.email == authentication.authenticatedEmail {
                            Text("TU").font(.caption2.bold()).foregroundStyle(.green)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }

    private var privacyCard: some View {
        Label("A localização é partilhada apenas com os seis utilizadores autenticados. Não existe rastreamento em segundo plano nesta versão.", systemImage: "hand.raised.fill")
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }

    private func lastSeen(_ date: Date?) -> String {
        guard let date else { return "Atualização desconhecida" }
        return "Atualizado " + date.formatted(.relative(presentation: .named))
    }
}
