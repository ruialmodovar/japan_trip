import SwiftUI

struct FlightLeg: Identifiable, Hashable {
    let id: String
    let flightNumber: String
    let dateText: String
    let departureAirport: String
    let departureCity: String
    let departureTime: String
    let arrivalAirport: String
    let arrivalCity: String
    let arrivalTime: String
    let duration: String
    let aircraftNote: String?
    let isDateConfirmed: Bool

    static let trip: [FlightLeg] = [
        .init(id: "EK262", flightNumber: "EK262", dateText: "Qua, 8 jul", departureAirport: "GRU", departureCity: "São Paulo", departureTime: "01:05", arrivalAirport: "DXB", arrivalCity: "Dubai", arrivalTime: "23:00", duration: "14h55", aircraftNote: nil, isDateConfirmed: true),
        .init(id: "EK312", flightNumber: "EK312", dateText: "Dom, 12 jul", departureAirport: "DXB", departureCity: "Dubai", departureTime: "07:40", arrivalAirport: "HND", arrivalCity: "Tóquio", arrivalTime: "22:20", duration: "9h40", aircraftNote: nil, isDateConfirmed: true),
        .init(id: "EK317", flightNumber: "EK317", dateText: "Sáb, 25 jul", departureAirport: "KIX", departureCity: "Osaka", departureTime: "23:45", arrivalAirport: "DXB", arrivalCity: "Dubai", arrivalTime: "04:15 +1", duration: "9h30", aircraftNote: nil, isDateConfirmed: true),
        .init(id: "EK261", flightNumber: "EK261", dateText: "Dom, 26 jul", departureAirport: "DXB", departureCity: "Dubai", departureTime: "09:05", arrivalAirport: "GRU", arrivalCity: "São Paulo", arrivalTime: "17:15", duration: "15h10", aircraftNote: "Conexão de 4h50 em Dubai.", isDateConfirmed: true)
    ]
}

struct FlightsView: View {
    @EnvironmentObject private var navigation: AppNavigationState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                overview
                ForEach(FlightLeg.trip) { flight in
                    FlightCard(flight: flight)
                }
                travelRules
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Voos")
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
            Label("Emirates", systemImage: "airplane")
                .font(.title2.bold())
            HStack {
                metric("4", "trechos")
                Divider().frame(height: 44)
                metric("2", "conexões DXB")
                Divider().frame(height: 44)
                metric("30 kg", "bagagem/pessoa")
            }
            Link(destination: URL(string: "https://www.emirates.com/br/portuguese/manage-booking/")!) {
                Label("Gerenciar reserva na Emirates", systemImage: "safari.fill")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(LinearGradient(colors: [.red.opacity(0.16), .orange.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
    }

    private var travelRules: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("ANTES DE EMBARCAR").font(.caption.bold()).tracking(1).foregroundStyle(.secondary)
            rule("Chegar ao aeroporto com pelo menos 3 horas de antecedência.", "clock.fill")
            rule("Power banks e baterias devem viajar na bagagem de mão.", "battery.100percent")
            rule("Separar passaportes, comprovantes e medicamentos essenciais.", "person.text.rectangle.fill")
            rule("Confirmar franquia e peso final das malas no bilhete emitido.", "suitcase.fill")
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func rule(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
    }
}

private struct FlightCard: View {
    let flight: FlightLeg

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(flight.flightNumber).font(.headline)
                Text(flight.dateText).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(flight.isDateConfirmed ? "CONFIRMADO" : "CONFIRMAR")
                    .font(.caption2.bold())
                    .foregroundStyle(flight.isDateConfirmed ? .green : .orange)
            }

            HStack(alignment: .center) {
                airport(flight.departureAirport, city: flight.departureCity, time: flight.departureTime, alignment: .leading)
                Spacer()
                VStack(spacing: 5) {
                    Image(systemName: "airplane").foregroundStyle(.red)
                    Rectangle().fill(.red.opacity(0.3)).frame(height: 1)
                    Text(flight.duration).font(.caption).foregroundStyle(.secondary)
                }
                .frame(width: 82)
                Spacer()
                airport(flight.arrivalAirport, city: flight.arrivalCity, time: flight.arrivalTime, alignment: .trailing)
            }

            if let note = flight.aircraftNote {
                Label(note, systemImage: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(flight.isDateConfirmed ? Color.clear : .orange.opacity(0.25), lineWidth: 1)
        }
    }

    private func airport(_ code: String, city: String, time: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(time).font(.title2.bold().monospacedDigit())
            Text(code).font(.title3.weight(.heavy)).foregroundStyle(.red)
            Text(city).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct FlightDayBanner: View {
    let date: Date

    private var flight: FlightLeg? {
        let day = TripDate.calendar.component(.day, from: date)
        return switch day {
        case 8: FlightLeg.trip[0]
        case 12: FlightLeg.trip[1]
        case 25: FlightLeg.trip[2]
        case 26: FlightLeg.trip[3]
        default: nil
        }
    }

    var body: some View {
        if let flight {
            HStack(spacing: 14) {
                Image(systemName: "airplane.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(flight.flightNumber) · \(flight.departureAirport) → \(flight.arrivalAirport)")
                        .font(.headline)
                    Text("Saída \(flight.departureTime) · chegada \(flight.arrivalTime) · \(flight.duration)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        }
    }
}
