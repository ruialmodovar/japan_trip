import SwiftUI

struct MobilityView: View {
    @EnvironmentObject private var navigation: AppNavigationState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selectedCity: City = .tokyo
    @State private var origin = ""
    @State private var destination = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                transportPlanner
                cityGuide
                shinkansenCard
                safetyCard
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Mobilidade")
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

    private var transportPlanner: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Planejar deslocamento", systemImage: "map.fill")
                .font(.headline)

            TextField("Origem — vazio usa a localização atual", text: $origin)
                .textFieldStyle(.roundedBorder)
            TextField("Destino", text: $destination)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.route)

            HStack(spacing: 10) {
                MobilityAction(title: "Metrô / trem", symbol: "tram.fill", color: .indigo, enabled: !destination.isEmpty) {
                    if let url = mapsTransitURL { openURL(url) }
                }
                MobilityAction(title: "Uber", symbol: "car.fill", color: .black, enabled: !destination.isEmpty) {
                    if let url = uberURL { openURL(url) }
                }
            }

            if selectedCity == .dubai {
                Button {
                    openURL(URL(string: "https://www.careem.com/en-AE/")!)
                } label: {
                    Label("Abrir Careem para Dubai", systemImage: "car.side.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }

    private var cityGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("COMO SE DESLOCAR")
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(City.allCases.filter { $0 != .travel }) { city in
                        Button {
                            selectedCity = city
                        } label: {
                            Text(city.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .foregroundStyle(selectedCity == city ? .white : city.color)
                                .background(selectedCity == city ? city.color : city.color.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let guide = guideForSelectedCity
            Label(guide.title, systemImage: guide.symbol)
                .font(.headline)
                .foregroundStyle(selectedCity.color)
            ForEach(guide.tips, id: \.self) { tip in
                Label(tip, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }

    private var shinkansenCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("Shinkansen NOZOMI 53", systemImage: "tram.fill")
                    .font(.headline)
                Spacer()
                Text("RESERVADO").font(.caption2.bold()).foregroundStyle(.green)
            }
            HStack {
                station("Tokyo", time: "17:12")
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "arrow.right").foregroundStyle(.blue)
                    Text("2h11").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                station("Kyoto", time: "19:23")
            }
            Divider()
            Label("Green Car 8 · Lugares 7-C, 7-D, 8-A, 8-B, 8-C e 8-D", systemImage: "person.3.fill")
                .font(.subheadline)
            Label("Chegar à Tokyo Station entre 16:30 e 16:40", systemImage: "clock.fill")
                .font(.subheadline)
            Text("No embarque: usar QR Ticket ou o cartão IC atribuído a cada passageiro. Se forem bilhetes físicos, retirá-los antes de passar pelas catracas do Shinkansen.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link(destination: URL(string: "https://smart-ex.jp/en/entraining/")!) {
                Label("Guia oficial de embarque", systemImage: "safari.fill")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding()
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
    }

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Para um grupo de seis", systemImage: "person.3.sequence.fill")
                .font(.headline)
            Text("No Japão, o Uber normalmente chama táxis licenciados. Para seis pessoas e malas, compare duas viaturas com um transfer privado. Confirme sempre placa, motorista e destino antes de entrar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 22))
    }

    private func station(_ name: String, time: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(time).font(.title2.bold().monospacedDigit())
            Text(name).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var mapsTransitURL: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")!
        var items = [URLQueryItem(name: "daddr", value: destination), .init(name: "dirflg", value: "r")]
        if !origin.isEmpty { items.append(.init(name: "saddr", value: origin)) }
        components.queryItems = items
        return components.url
    }

    private var uberURL: URL? {
        var components = URLComponents(string: "https://m.uber.com/ul/")!
        components.queryItems = [
            .init(name: "action", value: "setPickup"),
            .init(name: "pickup", value: "my_location"),
            .init(name: "dropoff[formatted_address]", value: destination)
        ]
        return components.url
    }

    private var guideForSelectedCity: (title: String, symbol: String, tips: [String]) {
        switch selectedCity {
        case .dubai:
            ("Dubai Metro, Careem e táxi", "tram.fill", [
                "Usar o Metro para trajetos ao longo das linhas principais; adquirir um cartão Nol.",
                "Careem ou táxi é mais prático para seis pessoas, souks e deslocamentos com malas.",
                "Evitar caminhadas longas durante o dia por causa do calor extremo."
            ])
        case .tokyo:
            ("Tokyo Metro, Toei e JR", "tram.fill", [
                "Suica ou PASMO funciona nas principais redes e também em lojas de conveniência.",
                "Tokyo Subway Ticket cobre Tokyo Metro e Toei; não cobre linhas JR.",
                "Conferir o número da saída da estação antes de chegar — algumas ficam muito distantes."
            ])
        case .kyoto:
            ("Metrô, ônibus e táxi", "bus.fill", [
                "Usar trem para Arashiyama e Fushimi Inari sempre que possível.",
                "Ônibus podem ficar lotados; para seis pessoas, dois táxis poupam tempo e calor.",
                "ICOCA/Suica/PASMO são aceitos na maior parte dos transportes urbanos."
            ])
        case .osaka:
            ("Osaka Metro e JR", "tram.fill", [
                "Umeda e Namba são os dois grandes centros de conexão.",
                "Usar ICOCA, Suica ou PASMO nas catracas; manter saldo suficiente.",
                "Para KIX com muitas malas, comparar Haruka Express com transfer privado."
            ])
        case .travel:
            ("Em trânsito", "airplane", [])
        }
    }
}

private struct MobilityAction: View {
    let title: String
    let symbol: String
    let color: Color
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .disabled(!enabled)
    }
}
