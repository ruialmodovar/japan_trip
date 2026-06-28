import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var navigation: AppNavigationState
    @State private var previewDate = Date()

    private var today: TripDay? {
        TripData.days.first { TripDate.calendar.isDate($0.date, inSameDayAs: previewDate) }
    }

    private var countdown: Int {
        let start = TripDate.calendar.startOfDay(for: TripData.days[0].date)
        let current = TripDate.calendar.startOfDay(for: Date())
        return max(0, TripDate.calendar.dateComponents([.day], from: current, to: start).day ?? 0)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let today {
                    TripHeader(city: today.city, eyebrow: today.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "pt_BR"))), title: today.title, subtitle: "\(today.activities.count) momentos no roteiro")

                    FlightDayBanner(date: today.date)

                    WeatherMiniCard(city: today.city)

                    ExpectedClimateCard(day: today)

                    if let note = today.note {
                        Label(note, systemImage: "info.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(today.activities.enumerated()), id: \.element.id) { index, activity in
                            ActivityRow(activity: activity, color: today.city.color, isLast: index == today.activities.count - 1)
                        }
                    }
                    .padding(.horizontal)
                    .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
                } else {
                    TripHeader(city: .travel, eyebrow: "Dubai · Japão", title: countdown > 0 ? "Faltam \(countdown) dias" : "Viagem 2026", subtitle: "8 a 26 de julho · 6 viajantes")
                    TripCountdownCard()
                    EmptyStateCard(icon: "suitcase.rolling.fill", title: "A aventura está chegando", message: "Cada detalhe preparado agora vira uma memória inesquecível depois. Use a prévia abaixo para explorar a viagem.")
                }

                PreviewDatePicker(selection: $previewDate)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Hoje")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: navigation.homeRequestID) { _, _ in
            previewDate = Date()
        }
        .onChange(of: navigation.selectedTab) { _, selectedTab in
            if selectedTab == .today {
                previewDate = Date()
            }
        }
    }
}

private struct TripCountdownCard: View {
    private let departure: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 1, minute: 5))!
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, departure.timeIntervalSince(context.date))
            let days = Int(remaining) / 86_400
            let hours = (Int(remaining) % 86_400) / 3_600
            let minutes = (Int(remaining) % 3_600) / 60
            let seconds = Int(remaining) % 60

            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(remaining > 0 ? "A CONTAGEM REGRESSIVA COMEÇOU" : "A VIAGEM COMEÇOU")
                            .font(.caption.weight(.black))
                            .tracking(1.1)
                            .foregroundStyle(.white.opacity(0.82))
                        Text(remaining > 0 ? countdownMessage(days: days) : "É hora de viver esta história!")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Image(systemName: remaining > 0 ? "airplane.departure" : "sparkles")
                        .font(.system(size: 31))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, options: .repeating.speed(0.35))
                }

                if remaining > 0 {
                    HStack(spacing: 8) {
                        CountdownUnit(value: days, label: "DIAS")
                        separator
                        CountdownUnit(value: hours, label: "HORAS")
                        separator
                        CountdownUnit(value: minutes, label: "MIN")
                        separator
                        CountdownUnit(value: seconds, label: "SEG")
                    }
                }

                HStack(spacing: 7) {
                    Image(systemName: "location.fill")
                    Text("Próxima parada: Dubai")
                    Spacer()
                    Text("EK262 · 01:05")
                        .monospacedDigit()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
            }
            .padding(20)
            .background(
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.89, green: 0.29, blue: 0.40), Color(red: 0.95, green: 0.48, blue: 0.38), .purple.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Circle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 170, height: 170)
                        .offset(x: 145, y: -80)
                    Circle()
                        .stroke(.white.opacity(0.10), lineWidth: 18)
                        .frame(width: 130, height: 130)
                        .offset(x: -165, y: 95)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .pink.opacity(0.28), radius: 20, y: 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(remaining > 0 ? "Faltam \(days) dias, \(hours) horas, \(minutes) minutos e \(seconds) segundos para a viagem" : "A viagem começou")
        }
    }

    private var separator: some View {
        Text(":")
            .font(.title2.bold())
            .foregroundStyle(.white.opacity(0.55))
            .offset(y: -8)
    }

    private func countdownMessage(days: Int) -> String {
        switch days {
        case 0: "É hoje! Malas prontas?"
        case 1: "Amanhã começa a nossa história"
        case 2...7: "Já dá para sentir a viagem"
        case 8...30: "Está quase na hora de partir"
        default: "Um sonho cada vez mais perto"
        }
    }
}

private struct CountdownUnit: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 5) {
            Text(String(format: "%02d", value))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 9, weight: .black))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.68))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct PreviewDatePicker: View {
    @Binding var selection: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PRÉVIA DA VIAGEM")
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(TripData.days) { day in
                        Button {
                            selection = day.date
                        } label: {
                            VStack(spacing: 3) {
                                Text(day.date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "pt_BR"))))
                                    .font(.caption2.weight(.semibold))
                                Text(day.date.formatted(.dateTime.day()))
                                    .font(.title3.bold())
                            }
                            .frame(width: 48, height: 58)
                            .foregroundStyle(TripDate.calendar.isDate(day.date, inSameDayAs: selection) ? .white : .primary)
                            .background(TripDate.calendar.isDate(day.date, inSameDayAs: selection) ? day.city.color : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 8)
    }
}

struct ActivityRow: View {
    let activity: TripActivity
    let color: Color
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(color.opacity(0.14)).frame(width: 38, height: 38)
                    Image(systemName: activity.kind.symbol).font(.callout.weight(.semibold)).foregroundStyle(color)
                }
                if !isLast {
                    Rectangle().fill(color.opacity(0.18)).frame(width: 2, height: 52)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(activity.time).font(.caption.monospacedDigit().weight(.bold)).foregroundStyle(color)
                    if activity.isCritical {
                        Text("IMPORTANTE").font(.caption2.weight(.black)).foregroundStyle(.orange)
                    }
                }
                Text(activity.title).font(.headline)
                Text(activity.details).font(.subheadline).foregroundStyle(.secondary)
                if let query = activity.locationQuery,
                   let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://maps.apple.com/?q=\(encoded)") {
                    Link(destination: url) {
                        Label("Abrir no Mapas", systemImage: "location.fill").font(.caption.weight(.semibold))
                    }
                    .padding(.top, 3)
                }
            }
            .padding(.bottom, isLast ? 16 : 10)
            .padding(.top, 2)
        }
    }
}
