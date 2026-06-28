import SwiftUI

enum AppTab: Hashable {
    case today, itinerary, reservations, checklist
}

@MainActor
final class AppNavigationState: ObservableObject {
    @Published var selectedTab: AppTab = .today
    @Published var showsMobility = false
    @Published var showsFlights = false
    @Published var showsWeather = false
    @Published var showsPhotos = false
    @Published private(set) var homeRequestID = 0

    func goHome() {
        showsMobility = false
        showsFlights = false
        showsWeather = false
        showsPhotos = false
        selectedTab = .today
        homeRequestID += 1
    }
}

struct RootView: View {
    @EnvironmentObject private var navigation: AppNavigationState

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            NavigationStack { TodayView().appMenuToolbar() }
                .tabItem { Label("Hoje", systemImage: "sun.max.fill") }
                .tag(AppTab.today)

            NavigationStack { ItineraryView().appMenuToolbar() }
                .tabItem { Label("Viagem", systemImage: "map.fill") }
                .tag(AppTab.itinerary)

            NavigationStack { ReservationsView().appMenuToolbar() }
                .tabItem { Label("Reservas", systemImage: "ticket.fill") }
                .tag(AppTab.reservations)

            NavigationStack { ChecklistView().appMenuToolbar() }
                .tabItem { Label("Checklist", systemImage: "checklist") }
                .tag(AppTab.checklist)
        }
        .tint(.indigo)
        .sheet(isPresented: $navigation.showsMobility) {
            NavigationStack { MobilityView() }
                .environmentObject(navigation)
        }
        .sheet(isPresented: $navigation.showsFlights) {
            NavigationStack { FlightsView() }
                .environmentObject(navigation)
        }
        .sheet(isPresented: $navigation.showsWeather) {
            NavigationStack { WeatherView() }
                .environmentObject(navigation)
        }
        .sheet(isPresented: $navigation.showsPhotos) {
            NavigationStack { PhotoJournalView() }
                .environmentObject(navigation)
        }
    }
}

private struct AppMenuToolbarModifier: ViewModifier {
    @EnvironmentObject private var navigation: AppNavigationState

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        navigation.goHome()
                    } label: {
                        Label("Tela inicial", systemImage: "house.fill")
                    }
                    Button {
                        navigation.showsMobility = true
                    } label: {
                        Label("Mobilidade", systemImage: "tram.fill")
                    }
                    Button {
                        navigation.showsFlights = true
                    } label: {
                        Label("Voos", systemImage: "airplane")
                    }
                    Button {
                        navigation.showsPhotos = true
                    } label: {
                        Label("Registros fotográficos", systemImage: "photo.on.rectangle.angled")
                    }
                    Divider()
                    Button {
                        navigation.selectedTab = .itinerary
                    } label: {
                        Label("Roteiro", systemImage: "map.fill")
                    }
                    Button {
                        navigation.showsWeather = true
                    } label: {
                        Label("Clima", systemImage: "cloud.sun.fill")
                    }
                    Button {
                        navigation.selectedTab = .reservations
                    } label: {
                        Label("Reservas", systemImage: "ticket.fill")
                    }
                    Button {
                        navigation.selectedTab = .checklist
                    } label: {
                        Label("Checklist", systemImage: "checklist")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.circle.fill")
                        .font(.title3)
                        .accessibilityLabel("Menu principal")
                }
            }
        }
    }
}

extension View {
    func appMenuToolbar() -> some View {
        modifier(AppMenuToolbarModifier())
    }
}

struct TripHeader: View {
    let city: City
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(eyebrow.uppercased(), systemImage: city.symbol)
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.85))
            Text(title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.84))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            LinearGradient(colors: [city.color, city.color.opacity(0.65), .indigo.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: city.color.opacity(0.22), radius: 16, y: 8)
    }
}

struct EmptyStateCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(.indigo)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
