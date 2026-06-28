import Foundation
import SwiftUI

struct WeatherLocation: Identifiable, Hashable {
    let city: City
    let latitude: Double
    let longitude: Double
    let timezone: String

    var id: String { city.rawValue }

    static let destinations: [WeatherLocation] = [
        .init(city: .dubai, latitude: 25.2048, longitude: 55.2708, timezone: "Asia/Dubai"),
        .init(city: .tokyo, latitude: 35.6762, longitude: 139.6503, timezone: "Asia/Tokyo"),
        .init(city: .kyoto, latitude: 35.0116, longitude: 135.7681, timezone: "Asia/Tokyo"),
        .init(city: .osaka, latitude: 34.6937, longitude: 135.5023, timezone: "Asia/Tokyo")
    ]

    static func location(for city: City) -> WeatherLocation? {
        destinations.first { $0.city == city }
    }
}

struct WeatherSnapshot: Codable {
    let current: CurrentWeather
    let daily: DailyWeather

    struct CurrentWeather: Codable {
        let time: String
        let temperature: Double
        let apparentTemperature: Double
        let humidity: Int
        let precipitation: Double
        let weatherCode: Int
        let cloudCover: Int
        let windSpeed: Double

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case humidity = "relative_humidity_2m"
            case precipitation
            case weatherCode = "weather_code"
            case cloudCover = "cloud_cover"
            case windSpeed = "wind_speed_10m"
        }
    }

    struct DailyWeather: Codable {
        let time: [String]
        let weatherCode: [Int]
        let maximumTemperature: [Double]
        let minimumTemperature: [Double]
        let precipitationProbability: [Int]
        let uvIndex: [Double]

        enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case maximumTemperature = "temperature_2m_max"
            case minimumTemperature = "temperature_2m_min"
            case precipitationProbability = "precipitation_probability_max"
            case uvIndex = "uv_index_max"
        }
    }
}

struct WeatherCondition {
    let title: String
    let symbol: String

    static func from(code: Int, isDay: Bool = true) -> WeatherCondition {
        switch code {
        case 0: .init(title: "Céu limpo", symbol: isDay ? "sun.max.fill" : "moon.stars.fill")
        case 1, 2: .init(title: "Parcialmente nublado", symbol: isDay ? "cloud.sun.fill" : "cloud.moon.fill")
        case 3: .init(title: "Nublado", symbol: "cloud.fill")
        case 45, 48: .init(title: "Nevoeiro", symbol: "cloud.fog.fill")
        case 51, 53, 55, 56, 57: .init(title: "Chuvisco", symbol: "cloud.drizzle.fill")
        case 61, 63, 65, 66, 67, 80, 81, 82: .init(title: "Chuva", symbol: "cloud.rain.fill")
        case 71, 73, 75, 77, 85, 86: .init(title: "Neve", symbol: "cloud.snow.fill")
        case 95, 96, 99: .init(title: "Trovoada", symbol: "cloud.bolt.rain.fill")
        default: .init(title: "Condições variáveis", symbol: "cloud.fill")
        }
    }
}

struct ExpectedClimate {
    let city: City
    let minimum: Int
    let maximum: Int
    let rainChanceText: String
    let summary: String
    let advice: String

    static func forDay(_ day: TripDay) -> ExpectedClimate? {
        let destination: City = switch day.id {
        case "2026-07-08": .dubai
        case "2026-07-12": .tokyo
        case "2026-07-18": .kyoto
        case "2026-07-22", "2026-07-25": .osaka
        default: day.city
        }

        return switch destination {
        case .dubai:
            .init(city: .dubai, minimum: 31, maximum: 41, rainChanceText: "Chuva muito improvável", summary: "Muito quente, seco e com radiação UV extrema.", advice: "Evitar o exterior entre 10h e 18h; água, chapéu e protetor solar sempre.")
        case .tokyo:
            .init(city: .tokyo, minimum: 22, maximum: 30, rainChanceText: "Pancadas possíveis", summary: "Quente e muito úmido, com possibilidade de chuva de verão.", advice: "Levar guarda-chuva compacto, água e fazer pausas em locais climatizados.")
        case .kyoto:
            .init(city: .kyoto, minimum: 24, maximum: 33, rainChanceText: "Pancadas possíveis", summary: "Calor intenso e abafado; a sensação térmica pode ser bem superior.", advice: "Visitar templos cedo, usar roupa leve e manter hidratação constante.")
        case .osaka:
            .init(city: .osaka, minimum: 25, maximum: 32, rainChanceText: "Pancadas possíveis", summary: "Quente, úmido e com noites abafadas.", advice: "Alternar passeios externos com centros comerciais e outras áreas cobertas.")
        case .travel:
            nil
        }
    }
}

@MainActor
final class WeatherStore: ObservableObject {
    @Published private(set) var snapshots: [City: WeatherSnapshot] = [:]
    @Published private(set) var loadingCities: Set<City> = []
    @Published private(set) var errors: [City: String] = [:]
    @Published private(set) var lastUpdated: [City: Date] = [:]

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        loadCache()
    }

    func refresh(_ location: WeatherLocation, force: Bool = false) async {
        if !force, let date = lastUpdated[location.city], Date().timeIntervalSince(date) < 900 {
            return
        }
        guard !loadingCities.contains(location.city) else { return }

        loadingCities.insert(location.city)
        errors[location.city] = nil
        defer { loadingCities.remove(location.city) }

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(location.latitude)),
            .init(name: "longitude", value: String(location.longitude)),
            .init(name: "timezone", value: location.timezone),
            .init(name: "forecast_days", value: "5"),
            .init(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,cloud_cover,wind_speed_10m"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,uv_index_max")
        ]

        do {
            let (data, response) = try await session.data(from: components.url!)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw URLError(.badServerResponse)
            }
            let snapshot = try JSONDecoder().decode(WeatherSnapshot.self, from: data)
            snapshots[location.city] = snapshot
            lastUpdated[location.city] = Date()
            saveCache(snapshot, city: location.city)
        } catch {
            errors[location.city] = snapshots[location.city] == nil
                ? "Não foi possível obter o clima. Verifique a ligação."
                : "Sem ligação — mostrando a última atualização."
        }
    }

    func refreshAll(force: Bool = false) async {
        await withTaskGroup(of: Void.self) { group in
            for location in WeatherLocation.destinations {
                group.addTask { await self.refresh(location, force: force) }
            }
        }
    }

    private func saveCache(_ snapshot: WeatherSnapshot, city: City) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: "weather.snapshot.\(city.rawValue)")
        UserDefaults.standard.set(lastUpdated[city], forKey: "weather.date.\(city.rawValue)")
    }

    private func loadCache() {
        for location in WeatherLocation.destinations {
            let city = location.city
            if let data = UserDefaults.standard.data(forKey: "weather.snapshot.\(city.rawValue)"),
               let snapshot = try? JSONDecoder().decode(WeatherSnapshot.self, from: data) {
                snapshots[city] = snapshot
                lastUpdated[city] = UserDefaults.standard.object(forKey: "weather.date.\(city.rawValue)") as? Date
            }
        }
    }
}
