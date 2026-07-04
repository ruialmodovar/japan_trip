import SwiftUI

struct ItineraryView: View {
    @EnvironmentObject private var ratings: ActivityRatingStore
    @EnvironmentObject private var authentication: AuthenticationManager
    @State private var selectedCity: City?
    @State private var showsRanking = false

    private var filteredDays: [TripDay] {
        guard let selectedCity else { return TripData.days }
        return TripData.days.filter { $0.city == selectedCity }
    }

    var body: some View {
        List {
            Section {
                Button { showsRanking = true } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "trophy.fill")
                            .font(.title2)
                            .foregroundStyle(.yellow)
                            .frame(width: 42, height: 42)
                            .background(.orange.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Ranking da viagem").font(.headline)
                            Text(ratings.ranking.isEmpty
                                 ? "Avaliem as atividades para criar o ranking"
                                 : "\(ratings.ranking.count) atividades avaliadas")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        FilterChip(title: "Tudo", color: .indigo, selected: selectedCity == nil) { selectedCity = nil }
                        ForEach(City.allCases.filter { $0 != .travel }) { city in
                            FilterChip(title: city.rawValue, color: city.color, selected: selectedCity == city) { selectedCity = city }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            ForEach(filteredDays) { day in
                NavigationLink(value: day) {
                    HStack(spacing: 14) {
                        VStack(spacing: 1) {
                            Text(day.date.formatted(.dateTime.day())).font(.title2.bold())
                            Text(day.date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "pt_BR")))).font(.caption).textCase(.uppercase)
                        }
                        .frame(width: 48, height: 55)
                        .foregroundStyle(.white)
                        .background(day.city.color, in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(day.title).font(.headline)
                            Label(day.city.rawValue, systemImage: day.city.symbol).font(.caption).foregroundStyle(day.city.color)
                            HStack(spacing: 8) {
                                Text("\(day.activities.count) atividades")
                                if let climate = ExpectedClimate.forDay(day) {
                                    Text("·")
                                    Label("\(climate.minimum)°–\(climate.maximum)°", systemImage: "thermometer.medium")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Viagem")
        .navigationDestination(for: TripDay.self) { DayDetailView(day: $0) }
        .task { await ratings.sync(authentication: authentication) }
        .sheet(isPresented: $showsRanking) {
            NavigationStack { ActivityRankingView() }
        }
    }
}

private struct ActivityRankingView: View {
    @EnvironmentObject private var ratings: ActivityRatingStore
    @EnvironmentObject private var authentication: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if ratings.ranking.isEmpty {
                ContentUnavailableView(
                    "Ranking ainda vazio",
                    systemImage: "star.bubble.fill",
                    description: Text("Abra uma atividade e atribua de 1 a 5 estrelas.")
                )
            } else {
                List(Array(ratings.ranking.enumerated()), id: \.element.id) { index, summary in
                    HStack(spacing: 13) {
                        Text("\(index + 1)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(index < 3 ? .orange : .secondary)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(summary.activity.title).font(.headline)
                            Text(summary.activity.details)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Label(summary.average.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                                .font(.headline).foregroundStyle(.orange)
                            Text("\(summary.count) \(summary.count == 1 ? "avaliação" : "avaliações")")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .navigationTitle("Ranking")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { Task { await ratings.sync(authentication: authentication) } } label: {
                    if ratings.isSyncing { ProgressView() } else { Image(systemName: "arrow.triangle.2.circlepath") }
                }
                .disabled(ratings.isSyncing)
            }
            ToolbarItem(placement: .topBarTrailing) { Button("Fechar") { dismiss() } }
        }
        .task { await ratings.sync(authentication: authentication) }
    }
}

private struct FilterChip: View {
    let title: String
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(selected ? .white : color)
                .background(selected ? color : color.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct DayDetailView: View {
    let day: TripDay

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                TripHeader(city: day.city, eyebrow: day.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "pt_BR"))), title: day.title, subtitle: day.city.rawValue)
                if let note = day.note {
                    Label(note, systemImage: note.lowercased().contains("conflito") || note.lowercased().contains("confirm") ? "exclamationmark.triangle.fill" : "lightbulb.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                }
                ExpectedClimateCard(day: day)
                VStack(spacing: 0) {
                    ForEach(Array(day.activities.enumerated()), id: \.element.id) { index, activity in
                        ActivityRow(activity: activity, city: day.city, color: day.city.color, isLast: index == day.activities.count - 1)
                    }
                }
                .padding()
                .background(.background, in: RoundedRectangle(cornerRadius: 22))
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
    }
}
