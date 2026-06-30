import SwiftUI

struct HotelStay: Identifiable, Hashable {
    let id: String
    let name: String
    let city: String
    let citySymbol: String
    let color: Color
    let dates: String
    let checkIn: String
    let checkOut: String
    let nights: Int
    let address: String
    let phone: String
    let officialURL: URL
    let bookingURL: URL
    let tip: String

    var mapURL: URL {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: "\(name), \(address)")]
        return components.url!
    }

    var telephoneURL: URL? {
        let number = phone.filter { $0.isNumber || $0 == "+" }
        return URL(string: "tel:\(number)")
    }

    static let trip: [HotelStay] = [
        .init(
            id: "taj-dubai",
            name: "Taj Dubai",
            city: "Dubai",
            citySymbol: "building.2.fill",
            color: .orange,
            dates: "8 – 12 jul",
            checkIn: "15:00",
            checkOut: "12:00",
            nights: 4,
            address: "Downtown Burj Khalifa Street, Dubai",
            phone: "+971 4 438 3100",
            officialURL: URL(string: "https://www.tajhotels.com/en-in/hotels/taj-dubai")!,
            bookingURL: URL(string: "https://www.booking.com/hotel/ae/taj-dubai.html")!,
            tip: "No Downtown Dubai, perto do Burj Khalifa. Para o aeroporto, reserva margem adicional nas horas de maior trânsito."
        ),
        .init(
            id: "blossom-hibiya",
            name: "The Blossom Hibiya",
            city: "Tóquio",
            citySymbol: "building.fill",
            color: .pink,
            dates: "12 – 18 jul",
            checkIn: "15:00",
            checkOut: "11:00",
            nights: 6,
            address: "1-1-13 Shinbashi, Tokyo 105-0004",
            phone: "+81 3 3591 8702",
            officialURL: URL(string: "https://www.jrk-hotels.co.jp/Hibiya/en/")!,
            bookingURL: URL(string: "https://www.booking.com/hotel/jp/the-blossom-hibiya.html")!,
            tip: "Boa base entre Shinbashi e Hibiya. A estação de Shinbashi facilita as ligações JR e metro pela cidade."
        ),
        .init(
            id: "doubletree-kyoto",
            name: "DoubleTree by Hilton Kyoto Higashiyama",
            city: "Kyoto",
            citySymbol: "building.columns.fill",
            color: .indigo,
            dates: "18 – 23 jul",
            checkIn: "15:00",
            checkOut: "11:00",
            nights: 5,
            address: "1-45 Honmachi, Higashiyama-ku, Kyoto 605-0981",
            phone: "+81 75 533 7070",
            officialURL: URL(string: "https://www.hilton.com/en/hotels/itmdtdi-doubletree-kyoto-higashiyama/")!,
            bookingURL: URL(string: "https://www.booking.com/hotel/jp/double-tree-by-hilton-kyoto-higashiyama.html")!,
            tip: "Em Higashiyama, perto da estação Keihan Shichijo. É uma zona prática para templos e passeios junto ao rio Kamo."
        ),
        .init(
            id: "osaka-station",
            name: "THE OSAKA STATION HOTEL, Autograph Collection",
            city: "Osaka",
            citySymbol: "tram.fill",
            color: .blue,
            dates: "23 – 25 jul",
            checkIn: "15:00",
            checkOut: "12:00",
            nights: 2,
            address: "3-2-2 Umeda, Kita-ku, Osaka 530-0001",
            phone: "+81 6 6105 1874",
            officialURL: URL(string: "https://www.marriott.com/en-us/hotels/osaak-the-osaka-station-hotel-autograph-collection/overview/")!,
            bookingURL: URL(string: "https://www.booking.com/hotel/jp/osaka-autograph-collection.html")!,
            tip: "Ligado diretamente à estação JR Osaka, no JP Tower Osaka. Excelente para a partida rumo ao aeroporto de Kansai."
        )
    ]
}

struct HotelsView: View {
    @EnvironmentObject private var navigation: AppNavigationState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                overview
                ForEach(HotelStay.trip) { stay in
                    HotelCard(stay: stay)
                }
                privacyNote
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Hotéis")
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

    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Alojamento da viagem", systemImage: "bed.double.fill")
                .font(.title2.bold())
            HStack {
                metric("4", "hotéis")
                Divider().frame(height: 44)
                metric("17", "noites")
                Divider().frame(height: 44)
                metric("4", "cidades")
            }
            Text("8 a 25 de julho de 2026")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            LinearGradient(colors: [.indigo.opacity(0.18), .pink.opacity(0.09)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22)
        )
    }

    private var privacyNote: some View {
        Label("As referências das reservas permanecem protegidas no comprovativo original do KAYAK/Booking.com.", systemImage: "lock.shield.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HotelCard: View {
    let stay: HotelStay

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: stay.citySymbol)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(stay.color.gradient, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(stay.city.uppercased())
                        .font(.caption.bold())
                        .tracking(1)
                        .foregroundStyle(stay.color)
                    Text(stay.name)
                        .font(.headline)
                    Text("\(stay.dates) · \(stay.nights) noites")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                timeBox("CHECK-IN", stay.checkIn, "rectangle.portrait.and.arrow.right")
                timeBox("CHECK-OUT", stay.checkOut, "rectangle.portrait.and.arrow.forward")
            }

            Label(stay.address, systemImage: "mappin.and.ellipse")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Label(stay.tip, systemImage: "lightbulb.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Link(destination: stay.mapURL) {
                    action("Mapa", "map.fill")
                }
                if let telephoneURL = stay.telephoneURL {
                    Link(destination: telephoneURL) {
                        action("Ligar", "phone.fill")
                    }
                }
            }
            HStack(spacing: 10) {
                Link(destination: stay.officialURL) {
                    action("Site oficial", "safari.fill")
                }
                Link(destination: stay.bookingURL) {
                    action("Booking.com", "photo.on.rectangle.angled")
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }

    private func timeBox(_ label: String, _ time: String, _ symbol: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).foregroundStyle(stay.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption2.bold()).foregroundStyle(.secondary)
                Text(time).font(.headline.monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(stay.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func action(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(stay.color.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))
    }
}
