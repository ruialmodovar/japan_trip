import SwiftUI

enum AppTab: Hashable {
    case today, itinerary, reservations, checklist, more
}

@MainActor
final class AppNavigationState: ObservableObject {
    @Published var selectedTab: AppTab = .today
    @Published var showsMobility = false
    @Published var showsFlights = false
    @Published var showsHotels = false
    @Published var showsWeather = false
    @Published var showsPhotos = false
    @Published var showsOffline = false
    @Published var showsNotifications = false
    @Published var showsDocumentVault = false
    @Published var showsLocationSharing = false
    @Published var showsExpenses = false
    @Published var showsShopping = false
    @Published var showsMenuTranslator = false
    @Published var showsPersonalDiary = false
    @Published var showsChangePassword = false
    @Published private(set) var homeRequestID = 0

    func goHome() {
        showsMobility = false
        showsFlights = false
        showsHotels = false
        showsWeather = false
        showsPhotos = false
        showsOffline = false
        showsNotifications = false
        showsDocumentVault = false
        showsLocationSharing = false
        showsExpenses = false
        showsShopping = false
        showsMenuTranslator = false
        showsPersonalDiary = false
        showsChangePassword = false
        selectedTab = .today
        homeRequestID += 1
    }
}

struct RootView: View {
    @EnvironmentObject private var navigation: AppNavigationState

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            NavigationStack { TodayView().appMenuToolbar() }
                .tabItem { Label("Home", systemImage: "house.fill") }
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

            NavigationStack { FeatureHubView() }
                .tabItem { Label("Mais", systemImage: "square.grid.2x2.fill") }
                .tag(AppTab.more)
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
        .sheet(isPresented: $navigation.showsHotels) {
            NavigationStack { HotelsView() }
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
        .sheet(isPresented: $navigation.showsOffline) {
            NavigationStack { OfflineView() }
                .environmentObject(navigation)
        }
        .sheet(isPresented: $navigation.showsNotifications) {
            NavigationStack { NotificationsView() }
                .environmentObject(navigation)
        }
        .sheet(isPresented: $navigation.showsDocumentVault) {
            NavigationStack { DocumentVaultView() }
                .environmentObject(navigation)
        }
        .sheet(isPresented: $navigation.showsLocationSharing) {
            NavigationStack { LocationSharingView() }
                .environmentObject(navigation)
        }
        .sheet(isPresented: $navigation.showsExpenses) {
            NavigationStack { ExpensesView() }
                .environmentObject(navigation)
        }
        .sheet(isPresented: $navigation.showsShopping) {
            NavigationStack { ShoppingView() }
                .environmentObject(navigation)
        }
        .sheet(isPresented: $navigation.showsMenuTranslator) {
            NavigationStack { MenuTranslatorView() }
                .environmentObject(navigation)
        }
        .sheet(isPresented: $navigation.showsPersonalDiary) {
            NavigationStack { PersonalDiaryView() }
                .environmentObject(navigation)
        }
        .sheet(isPresented: $navigation.showsChangePassword) {
            NavigationStack { ChangePasswordView() }
        }
    }
}

private struct AppMenuToolbarModifier: ViewModifier {
    @EnvironmentObject private var navigation: AppNavigationState

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    navigation.selectedTab = .more
                } label: {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.title3)
                        .accessibilityLabel("Todas as funcionalidades")
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
