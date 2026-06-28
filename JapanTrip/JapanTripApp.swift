import SwiftUI

@main
struct JapanTripApp: App {
    @StateObject private var tripState = TripState()
    @StateObject private var authentication = AuthenticationManager()
    @StateObject private var weather = WeatherStore()
    @StateObject private var navigation = AppNavigationState()
    @StateObject private var photoJournal = PhotoJournalStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AuthenticationGate()
                .environmentObject(tripState)
                .environmentObject(authentication)
                .environmentObject(weather)
                .environmentObject(navigation)
                .environmentObject(photoJournal)
                .preferredColorScheme(.light)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                authentication.lockIfAllowed()
            }
        }
    }
}

@MainActor
final class TripState: ObservableObject {
    @Published private(set) var completedIDs: Set<String>

    private let defaultsKey = "completedChecklistIDs"

    init() {
        completedIDs = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
    }

    func isCompleted(_ item: ChecklistItem) -> Bool {
        completedIDs.contains(item.id)
    }

    func toggle(_ item: ChecklistItem) {
        if completedIDs.contains(item.id) {
            completedIDs.remove(item.id)
        } else {
            completedIDs.insert(item.id)
        }
        UserDefaults.standard.set(Array(completedIDs), forKey: defaultsKey)
    }
}
