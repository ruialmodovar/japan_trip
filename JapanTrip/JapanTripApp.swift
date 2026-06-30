import SwiftUI

@main
struct JapanTripApp: App {
    @StateObject private var tripState = TripState()
    @StateObject private var authentication = AuthenticationManager()
    @StateObject private var weather = WeatherStore()
    @StateObject private var navigation = AppNavigationState()
    @StateObject private var photoJournal = PhotoJournalStore()
    @StateObject private var offlineStore = OfflineStore()
    @StateObject private var notifications = NotificationManager()
    @StateObject private var documentVault = DocumentVaultStore()
    @StateObject private var locationSharing = LocationSharingManager()
    @StateObject private var expenses = ExpenseStore()
    @StateObject private var shopping = ShoppingStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AuthenticationGate()
                .environmentObject(tripState)
                .environmentObject(authentication)
                .environmentObject(weather)
                .environmentObject(navigation)
                .environmentObject(photoJournal)
                .environmentObject(offlineStore)
                .environmentObject(notifications)
                .environmentObject(documentVault)
                .environmentObject(locationSharing)
                .environmentObject(expenses)
                .environmentObject(shopping)
                .preferredColorScheme(.light)
                .task {
                    await notifications.refreshStatus()
                    if notifications.authorizationStatus == .authorized {
                        await notifications.enableAndSchedule(weatherSnapshots: weather.snapshots)
                    }
                }
                .onChange(of: authentication.isAuthenticated) { _, signedIn in
                    if signedIn {
                        locationSharing.resumeIfNeeded(authentication: authentication)
                    } else {
                        locationSharing.pauseUpdates()
                    }
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                authentication.lockIfAllowed()
                documentVault.lock()
                locationSharing.pauseUpdates()
            } else if newPhase == .active, authentication.isAuthenticated {
                locationSharing.resumeIfNeeded(authentication: authentication)
            }
        }
    }
}

@MainActor
final class TripState: ObservableObject {
    @Published private(set) var completedIDs: Set<String>
    @Published private(set) var checklistItems: [ChecklistItem]

    private let defaultsKey = "completedChecklistIDs"
    private let itemsKey = "checklistItems"

    init() {
        completedIDs = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
        if let data = UserDefaults.standard.data(forKey: itemsKey),
           let items = try? JSONDecoder().decode([ChecklistItem].self, from: data) {
            checklistItems = items
        } else {
            checklistItems = TripData.checklist
        }
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

    func addChecklistItem(title: String, section: ChecklistItem.Section) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        checklistItems.append(.init(id: UUID().uuidString, title: trimmed, section: section))
        saveChecklist()
    }

    func updateChecklistItem(_ item: ChecklistItem, title: String, section: ChecklistItem.Section) {
        guard let index = checklistItems.firstIndex(where: { $0.id == item.id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        checklistItems[index] = .init(id: item.id, title: trimmed, section: section)
        saveChecklist()
    }

    func deleteChecklistItem(_ item: ChecklistItem) {
        checklistItems.removeAll { $0.id == item.id }
        completedIDs.remove(item.id)
        UserDefaults.standard.set(Array(completedIDs), forKey: defaultsKey)
        saveChecklist()
    }

    func restoreDefaultChecklist() {
        checklistItems = TripData.checklist
        completedIDs = []
        UserDefaults.standard.set([], forKey: defaultsKey)
        saveChecklist()
    }

    private func saveChecklist() {
        if let data = try? JSONEncoder().encode(checklistItems) {
            UserDefaults.standard.set(data, forKey: itemsKey)
        }
    }
}
