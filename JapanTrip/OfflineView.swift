import MapKit
import SwiftUI

struct OfflineMapDestination: Identifiable, Hashable {
    let id: String
    let city: City
    let subtitle: String
    let latitude: Double
    let longitude: Double
    let latitudeDelta: Double
    let longitudeDelta: Double

    static let trip: [OfflineMapDestination] = [
        .init(id: "dubai", city: .dubai, subtitle: "Downtown, aeroporto e Taj Dubai", latitude: 25.2048, longitude: 55.2708, latitudeDelta: 0.20, longitudeDelta: 0.20),
        .init(id: "tokyo", city: .tokyo, subtitle: "Hibiya, Shinbashi e principais bairros", latitude: 35.6762, longitude: 139.6503, latitudeDelta: 0.22, longitudeDelta: 0.22),
        .init(id: "kyoto", city: .kyoto, subtitle: "Higashiyama, Kyoto Station e templos", latitude: 35.0116, longitude: 135.7681, latitudeDelta: 0.16, longitudeDelta: 0.16),
        .init(id: "osaka", city: .osaka, subtitle: "Umeda, Osaka Station e ligação a KIX", latitude: 34.6937, longitude: 135.5023, latitudeDelta: 0.18, longitudeDelta: 0.18)
    ]
}

struct EmergencyContact: Identifiable, Hashable {
    let id: String
    let country: String
    let service: String
    let number: String
    let symbol: String

    static let trip: [EmergencyContact] = [
        .init(id: "uae-police", country: "Emirados Árabes Unidos", service: "Polícia", number: "999", symbol: "shield.fill"),
        .init(id: "uae-ambulance", country: "Emirados Árabes Unidos", service: "Ambulância", number: "998", symbol: "cross.case.fill"),
        .init(id: "uae-fire", country: "Emirados Árabes Unidos", service: "Bombeiros", number: "997", symbol: "flame.fill"),
        .init(id: "japan-police", country: "Japão", service: "Polícia", number: "110", symbol: "shield.fill"),
        .init(id: "japan-ambulance", country: "Japão", service: "Ambulância e bombeiros", number: "119", symbol: "cross.case.fill")
    ]
}

@MainActor
final class OfflineStore: ObservableObject {
    @Published private(set) var isPreparing = false
    @Published private(set) var preparedMapIDs: Set<String> = []
    @Published var errorMessage: String?

    private let directory: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.directory = base.appendingPathComponent("JapanTripOffline", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        reloadStatus()
    }

    var isReady: Bool { preparedMapIDs.count == OfflineMapDestination.trip.count }

    var storedSizeText: String {
        let bytes = OfflineMapDestination.trip.reduce(Int64(0)) { result, destination in
            let size = (try? FileManager.default.attributesOfItem(atPath: mapURL(for: destination).path)[.size] as? NSNumber)?.int64Value ?? 0
            return result + size
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func image(for destination: OfflineMapDestination) -> UIImage? {
        UIImage(contentsOfFile: mapURL(for: destination).path)
    }

    func prepareMaps() async {
        guard !isPreparing else { return }
        isPreparing = true
        errorMessage = nil
        defer { isPreparing = false }

        for destination in OfflineMapDestination.trip {
            do {
                let options = MKMapSnapshotter.Options()
                options.region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: destination.latitude, longitude: destination.longitude),
                    span: MKCoordinateSpan(latitudeDelta: destination.latitudeDelta, longitudeDelta: destination.longitudeDelta)
                )
                options.size = CGSize(width: 900, height: 560)
                options.scale = 2
                let snapshot = try await MKMapSnapshotter(options: options).start()
                guard let data = snapshot.image.jpegData(compressionQuality: 0.86) else { continue }
                try data.write(to: mapURL(for: destination), options: .atomic)
                preparedMapIDs.insert(destination.id)
            } catch {
                errorMessage = "Não foi possível guardar todos os mapas. Verifique a ligação e tente novamente."
            }
        }
        reloadStatus()
    }

    private func reloadStatus() {
        preparedMapIDs = Set(OfflineMapDestination.trip.compactMap {
            FileManager.default.fileExists(atPath: mapURL(for: $0).path) ? $0.id : nil
        })
    }

    private func mapURL(for destination: OfflineMapDestination) -> URL {
        directory.appendingPathComponent("map-\(destination.id).jpg")
    }
}

struct OfflineView: View {
    @EnvironmentObject private var navigation: AppNavigationState
    @EnvironmentObject private var offlineStore: OfflineStore
    @EnvironmentObject private var weather: WeatherStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                statusCard
                includedCard
                mapsSection
                hotelContacts
                emergencyContacts
                limitationsCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Modo Offline")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                    navigation.goHome()
                } label: {
                    Label("Início", systemImage: "house.fill")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Fechar") { dismiss() }
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 13) {
                Image(systemName: offlineStore.isReady ? "checkmark.icloud.fill" : "icloud.and.arrow.down.fill")
                    .font(.largeTitle)
                    .foregroundStyle(offlineStore.isReady ? .green : .indigo)
                VStack(alignment: .leading, spacing: 3) {
                    Text(offlineStore.isReady ? "Pacote offline preparado" : "Preparar antes da viagem")
                        .font(.title3.bold())
                    Text(offlineStore.isReady ? "Mapas guardados · \(offlineStore.storedSizeText)" : "Roteiro e reservas já estão disponíveis")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                Task {
                    async let maps: Void = offlineStore.prepareMaps()
                    async let forecast: Void = weather.refreshAll(force: true)
                    _ = await (maps, forecast)
                }
            } label: {
                HStack {
                    if offlineStore.isPreparing { ProgressView().tint(.white) }
                    Label(offlineStore.isReady ? "Atualizar pacote" : "Descarregar mapas e clima", systemImage: "arrow.down.circle.fill")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(offlineStore.isPreparing)

            if let error = offlineStore.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }

    private var includedCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("SEMPRE DISPONÍVEL").font(.caption.bold()).tracking(1).foregroundStyle(.secondary)
            available("Roteiro completo dos 18 dias", "calendar")
            available("Voos, hotéis e reservas", "ticket.fill")
            available("Clima esperado e última previsão obtida", "cloud.sun.fill")
            available("Contactos dos hotéis e emergências", "phone.fill")
            available("Guias de metrô, Shinkansen e mobilidade", "tram.fill")
        }
        .padding()
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
    }

    private var mapsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MAPAS DE REFERÊNCIA").font(.caption.bold()).tracking(1).foregroundStyle(.secondary)
            ForEach(OfflineMapDestination.trip) { destination in
                VStack(alignment: .leading, spacing: 9) {
                    if let image = offlineStore.image(for: destination) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    HStack {
                        Label(destination.city.rawValue, systemImage: destination.city.symbol)
                            .font(.headline)
                            .foregroundStyle(destination.city.color)
                        Spacer()
                        Image(systemName: offlineStore.preparedMapIDs.contains(destination.id) ? "checkmark.circle.fill" : "arrow.down.circle")
                            .foregroundStyle(offlineStore.preparedMapIDs.contains(destination.id) ? .green : .secondary)
                    }
                    Text(destination.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                .padding()
                .background(.background, in: RoundedRectangle(cornerRadius: 20))
            }
        }
    }

    private var hotelContacts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CONTACTOS DOS HOTÉIS").font(.caption.bold()).tracking(1).foregroundStyle(.secondary)
            ForEach(HotelStay.trip) { hotel in
                if let url = hotel.telephoneURL {
                    Link(destination: url) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hotel.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                Text("\(hotel.city) · \(hotel.phone)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "phone.circle.fill").font(.title2)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }

    private var emergencyContacts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EMERGÊNCIAS").font(.caption.bold()).tracking(1).foregroundStyle(.secondary)
            ForEach(EmergencyContact.trip) { contact in
                Link(destination: URL(string: "tel:\(contact.number)")!) {
                    HStack {
                        Image(systemName: contact.symbol).foregroundStyle(.red).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.service).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text(contact.country).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(contact.number).font(.headline.monospacedDigit())
                    }
                }
            }
        }
        .padding()
        .background(.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 22))
    }

    private var limitationsCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("Antes de sair do Wi-Fi", systemImage: "wifi.exclamationmark")
                .font(.headline)
            Text("Os mapas acima são imagens de referência. Rotas, trânsito, metrô em tempo real, Uber e clima atual exigem internet.")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("No Apple Maps, abra a fotografia do perfil → Mapas Offline e descarregue Dubai, Tóquio, Kyoto e Osaka para ter navegação completa sem rede.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button {
                openURL(URL(string: "maps://")!)
            } label: {
                Label("Abrir Apple Maps", systemImage: "map.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 22))
    }

    private func available(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
    }
}
