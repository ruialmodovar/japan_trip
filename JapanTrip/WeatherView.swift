import SwiftUI

struct WeatherView: View {
    @EnvironmentObject private var weather: WeatherStore
    @EnvironmentObject private var navigation: AppNavigationState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLocation = WeatherLocation.destinations[0]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                cityPicker

                if let snapshot = weather.snapshots[selectedLocation.city] {
                    CurrentWeatherCard(location: selectedLocation, snapshot: snapshot)
                    WeatherMetrics(snapshot: snapshot)
                    ForecastCard(snapshot: snapshot, color: selectedLocation.city.color)

                    if let date = weather.lastUpdated[selectedLocation.city] {
                        Text("Atualizado \(date.formatted(.relative(presentation: .named))) · Open-Meteo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if weather.loadingCities.contains(selectedLocation.city) {
                    ProgressView("A obter condições atuais…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    EmptyStateCard(icon: "wifi.exclamationmark", title: "Clima indisponível", message: weather.errors[selectedLocation.city] ?? "Puxe para atualizar quando tiver ligação.")
                }

                if let error = weather.errors[selectedLocation.city], weather.snapshots[selectedLocation.city] != nil {
                    Label(error, systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Clima")
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
        .refreshable { await weather.refresh(selectedLocation, force: true) }
        .task(id: selectedLocation.id) { await weather.refresh(selectedLocation) }
    }

    private var cityPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(WeatherLocation.destinations) { location in
                    Button {
                        selectedLocation = location
                    } label: {
                        Label(location.city.rawValue, systemImage: location.city.symbol)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .foregroundStyle(selectedLocation == location ? .white : location.city.color)
                            .background(selectedLocation == location ? location.city.color : location.city.color.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct CurrentWeatherCard: View {
    let location: WeatherLocation
    let snapshot: WeatherSnapshot

    var condition: WeatherCondition { .from(code: snapshot.current.weatherCode) }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Label("AGORA EM \(location.city.rawValue.uppercased())", systemImage: "location.fill")
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.82))
                Text("\(snapshot.current.temperature, specifier: "%.0f")°")
                    .font(.system(size: 66, weight: .thin, design: .rounded))
                    .foregroundStyle(.white)
                Text(condition.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Sensação de \(snapshot.current.apparentTemperature, specifier: "%.0f")°")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            Image(systemName: condition.symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 68))
        }
        .padding(24)
        .background(LinearGradient(colors: [location.city.color, location.city.color.opacity(0.62), .indigo.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: location.city.color.opacity(0.22), radius: 16, y: 8)
    }
}

private struct WeatherMetrics: View {
    let snapshot: WeatherSnapshot

    var body: some View {
        HStack(spacing: 0) {
            Metric(value: "\(snapshot.current.humidity)%", label: "Umidade", symbol: "humidity.fill")
            Divider().frame(height: 52)
            Metric(value: String(format: "%.0f km/h", snapshot.current.windSpeed), label: "Vento", symbol: "wind")
            Divider().frame(height: 52)
            Metric(value: String(format: "%.1f mm", snapshot.current.precipitation), label: "Chuva", symbol: "drop.fill")
        }
        .padding(.vertical, 16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private struct Metric: View {
        let value: String
        let label: String
        let symbol: String

        var body: some View {
            VStack(spacing: 5) {
                Image(systemName: symbol).foregroundStyle(.blue)
                Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.8)
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ForecastCard: View {
    let snapshot: WeatherSnapshot
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PRÓXIMOS 5 DIAS")
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            ForEach(snapshot.daily.time.indices, id: \.self) { index in
                let condition = WeatherCondition.from(code: snapshot.daily.weatherCode[index])
                HStack(spacing: 12) {
                    Text(dayLabel(snapshot.daily.time[index], index: index)).font(.subheadline.weight(.semibold)).frame(width: 48, alignment: .leading)
                    Image(systemName: condition.symbol).symbolRenderingMode(.multicolor).frame(width: 28)
                    Text(condition.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Label("\(snapshot.daily.precipitationProbability[index])%", systemImage: "drop.fill").font(.caption).foregroundStyle(.blue)
                    Text("\(snapshot.daily.minimumTemperature[index], specifier: "%.0f")°").foregroundStyle(.secondary)
                    Text("\(snapshot.daily.maximumTemperature[index], specifier: "%.0f")°").fontWeight(.semibold)
                }
                .padding(.vertical, 9)
                if index != snapshot.daily.time.indices.last { Divider() }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }

    private func dayLabel(_ string: String, index: Int) -> String {
        if index == 0 { return "Hoje" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: string) else { return string }
        return date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "pt_BR"))).capitalized
    }
}

struct WeatherMiniCard: View {
    @EnvironmentObject private var weather: WeatherStore
    let city: City

    var location: WeatherLocation? { WeatherLocation.location(for: city) }

    var body: some View {
        if let location {
            Group {
                if let snapshot = weather.snapshots[city] {
                    let condition = WeatherCondition.from(code: snapshot.current.weatherCode)
                    HStack(spacing: 14) {
                        Image(systemName: condition.symbol).symbolRenderingMode(.multicolor).font(.title)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clima agora em \(city.rawValue)").font(.caption).foregroundStyle(.secondary)
                            Text(condition.title).font(.headline)
                        }
                        Spacer()
                        Text("\(snapshot.current.temperature, specifier: "%.0f")°").font(.title.bold())
                    }
                    .padding()
                    .background(.background, in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .task { await weather.refresh(location) }
        }
    }
}

struct ExpectedClimateCard: View {
    let day: TripDay

    var body: some View {
        if let climate = ExpectedClimate.forDay(day) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label("CLIMA ESPERADO", systemImage: "calendar.badge.clock")
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(climate.city.color)
                    Spacer()
                    Text("\(climate.minimum)° – \(climate.maximum)°")
                        .font(.title3.bold())
                }

                Text(climate.summary)
                    .font(.subheadline)

                HStack(spacing: 8) {
                    Label(climate.rainChanceText, systemImage: "umbrella.fill")
                    Spacer()
                    Label("Média de julho", systemImage: "chart.line.uptrend.xyaxis")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Label(climate.advice, systemImage: "lightbulb.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            .padding()
            .background(climate.city.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(climate.city.color.opacity(0.16), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
