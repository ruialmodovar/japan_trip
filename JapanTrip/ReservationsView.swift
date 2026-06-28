import SwiftUI

struct ReservationsView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    SummaryMetric(value: "\(TripData.reservations.filter { $0.status != .pending }.count)", label: "confirmadas", color: .green)
                    Divider()
                    SummaryMetric(value: "\(TripData.reservations.filter { $0.status == .pending }.count)", label: "pendentes", color: .orange)
                }
                .frame(height: 72)
            }

            ForEach(ReservationStatus.allCasesCompat, id: \.rawValue) { status in
                let reservations = TripData.reservations.filter { $0.status == status }
                if !reservations.isEmpty {
                    Section(status.rawValue) {
                        ForEach(reservations) { reservation in
                            HStack(spacing: 13) {
                                Image(systemName: reservation.symbol)
                                    .frame(width: 38, height: 38)
                                    .foregroundStyle(status.color)
                                    .background(status.color.opacity(0.12), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(reservation.title).font(.headline)
                                    Text(reservation.subtitle).font(.subheadline).foregroundStyle(.secondary)
                                    if let note = reservation.sensitiveNote {
                                        Label(note, systemImage: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(reservation.dateText).font(.caption.weight(.semibold)).foregroundStyle(status.color)
                            }
                            .padding(.vertical, 5)
                        }
                    }
                }
            }
        }
        .navigationTitle("Reservas")
        .listStyle(.insetGrouped)
    }
}

private extension ReservationStatus {
    static let allCasesCompat: [ReservationStatus] = [.pending, .booked, .confirmed]
}

private struct SummaryMetric: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.title.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
