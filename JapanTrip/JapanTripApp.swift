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
    @StateObject private var activityRatings = ActivityRatingStore()
    @StateObject private var personalDiary = PersonalDiaryStore()
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
                .environmentObject(activityRatings)
                .environmentObject(personalDiary)
                .preferredColorScheme(.light)
                .task {
                    await authentication.authenticateAutomatically()
                    if authentication.isAuthenticated {
                        tripState.configureChecklistSharing(authentication: authentication)
                        await tripState.syncChecklist(authentication: authentication)
                        await activityRatings.sync(authentication: authentication)
                        await personalDiary.sync(authentication: authentication)
                    }
                    await notifications.refreshStatus()
                    if notifications.authorizationStatus == .authorized {
                        await notifications.enableAndSchedule(weatherSnapshots: weather.snapshots)
                    }
                }
                .onChange(of: authentication.isAuthenticated) { _, signedIn in
                    if signedIn {
                        tripState.configureChecklistSharing(authentication: authentication)
                        expenses.configureSharing(authentication: authentication)
                        photoJournal.configureSharing(authentication: authentication)
                        personalDiary.configure(authentication: authentication)
                        locationSharing.resumeIfNeeded(authentication: authentication)
                        Task {
                            await tripState.syncChecklist(authentication: authentication)
                            await activityRatings.sync(authentication: authentication)
                            await expenses.sync(authentication: authentication)
                            await photoJournal.sync(authentication: authentication)
                            await personalDiary.sync(authentication: authentication)
                        }
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
            } else if newPhase == .active {
                Task {
                    await authentication.authenticateAutomatically()
                    if authentication.isAuthenticated {
                        locationSharing.resumeIfNeeded(authentication: authentication)
                    }
                }
            }
        }
    }
}

@MainActor
final class TripState: ObservableObject {
    @Published private(set) var completedIDs: Set<String>
    @Published private(set) var checklistItems: [ChecklistItem]
    @Published private(set) var isSyncingChecklist = false
    @Published private(set) var checklistLastSyncedAt: Date?
    @Published var checklistErrorMessage: String?

    private let defaults: UserDefaults
    private let checklistService: any ChecklistSharingServicing
    private weak var authentication: AuthenticationManager?
    private var currentUserEmail: String?
    private var pendingUploadIDs: Set<String> = []
    private var pendingGeneralDeletionIDs: Set<String> = []
    private var pendingPersonalDeletionIDs: Set<String> = []

    private let legacyCompletedKey = "completedChecklistIDs"
    private let legacyItemsKey = "checklistItems"
    private let generalCompletedKey = "checklist.general.completed"
    private let generalItemsKey = "checklist.general.items"
    private let generalPendingUploadsKey = "checklist.general.pendingUploads"
    private let generalPendingDeletionsKey = "checklist.general.pendingDeletions"

    init(
        defaults: UserDefaults = .standard,
        checklistService: any ChecklistSharingServicing = SupabaseChecklistSharingService()
    ) {
        self.defaults = defaults
        self.checklistService = checklistService
        completedIDs = Set(defaults.stringArray(forKey: generalCompletedKey)
            ?? defaults.stringArray(forKey: legacyCompletedKey) ?? [])
        if let data = defaults.data(forKey: generalItemsKey) ?? defaults.data(forKey: legacyItemsKey),
           let items = try? JSONDecoder().decode([ChecklistItem].self, from: data) {
            checklistItems = items.map { .init(id: $0.id, title: $0.title, section: $0.section, scope: .general) }
        } else {
            checklistItems = TripData.checklist
        }
        pendingGeneralDeletionIDs = Set(defaults.stringArray(forKey: generalPendingDeletionsKey) ?? [])
        if let saved = defaults.stringArray(forKey: generalPendingUploadsKey) {
            pendingUploadIDs = Set(saved)
        } else {
            pendingUploadIDs = Set(checklistItems.map(\.id))
        }
        saveChecklist()
    }

    func items(in scope: ChecklistItem.Scope) -> [ChecklistItem] {
        checklistItems.filter { $0.scope == scope }
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
        pendingUploadIDs.insert(item.id)
        saveChecklist()
        synchronizeSoon()
    }

    func addChecklistItem(title: String, section: ChecklistItem.Section, scope: ChecklistItem.Scope) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = ChecklistItem(id: UUID().uuidString.lowercased(), title: trimmed, section: section, scope: scope)
        checklistItems.append(item)
        pendingUploadIDs.insert(item.id)
        saveChecklist()
        synchronizeSoon()
    }

    func updateChecklistItem(_ item: ChecklistItem, title: String, section: ChecklistItem.Section) {
        guard let index = checklistItems.firstIndex(where: { $0.id == item.id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        checklistItems[index] = .init(id: item.id, title: trimmed, section: section, scope: item.scope)
        pendingUploadIDs.insert(item.id)
        saveChecklist()
        synchronizeSoon()
    }

    func deleteChecklistItem(_ item: ChecklistItem) {
        checklistItems.removeAll { $0.id == item.id }
        completedIDs.remove(item.id)
        pendingUploadIDs.remove(item.id)
        if item.scope == .general {
            pendingGeneralDeletionIDs.insert(item.id)
        } else {
            pendingPersonalDeletionIDs.insert(item.id)
        }
        saveChecklist()
        synchronizeSoon()
    }

    func restoreDefaultChecklist(scope: ChecklistItem.Scope = .general) {
        let removedIDs = Set(items(in: scope).map(\.id))
        checklistItems.removeAll { $0.scope == scope }
        completedIDs.subtract(removedIDs)
        if scope == .general {
            pendingGeneralDeletionIDs.formUnion(removedIDs)
        } else {
            pendingPersonalDeletionIDs.formUnion(removedIDs)
        }
        if scope == .general {
            checklistItems.append(contentsOf: TripData.checklist)
            pendingUploadIDs.formUnion(TripData.checklist.map(\.id))
            pendingGeneralDeletionIDs.subtract(TripData.checklist.map(\.id))
        }
        saveChecklist()
        synchronizeSoon()
    }

    func configureChecklistSharing(authentication: AuthenticationManager) {
        self.authentication = authentication
        guard let email = authentication.authenticatedEmail, email != currentUserEmail else { return }

        if currentUserEmail != nil { saveChecklist() }
        let previousPersonalIDs = Set(items(in: .personal).map(\.id))
        completedIDs.subtract(previousPersonalIDs)
        pendingUploadIDs.subtract(previousPersonalIDs)
        checklistItems.removeAll { $0.scope == .personal }
        pendingPersonalDeletionIDs = []
        currentUserEmail = email

        if let data = defaults.data(forKey: personalItemsKey(email)),
           let personal = try? JSONDecoder().decode([ChecklistItem].self, from: data) {
            checklistItems.append(contentsOf: personal.map {
                .init(id: $0.id, title: $0.title, section: $0.section, scope: .personal)
            })
        }
        completedIDs.formUnion(defaults.stringArray(forKey: personalCompletedKey(email)) ?? [])
        pendingUploadIDs.formUnion(defaults.stringArray(forKey: personalPendingUploadsKey(email)) ?? items(in: .personal).map(\.id))
        pendingPersonalDeletionIDs = Set(defaults.stringArray(forKey: personalPendingDeletionsKey(email)) ?? [])
        saveChecklist()
    }

    func syncChecklist(authentication: AuthenticationManager) async {
        configureChecklistSharing(authentication: authentication)
        guard authentication.isAuthenticated, !isSyncingChecklist else { return }
        isSyncingChecklist = true
        defer { isSyncingChecklist = false }
        do {
            let token = try await authentication.accessTokenForAPI()
            for id in pendingGeneralDeletionIDs.union(pendingPersonalDeletionIDs) {
                try await checklistService.delete(id: id, accessToken: token)
                pendingGeneralDeletionIDs.remove(id)
                pendingPersonalDeletionIDs.remove(id)
            }
            guard let userID = authentication.authenticatedUserID,
                  let email = authentication.authenticatedEmail else { return }
            for item in checklistItems where pendingUploadIDs.contains(item.id) {
                let personal = item.scope == .personal
                try await checklistService.upsert(.init(
                    id: item.id,
                    title: item.title,
                    section: item.section.rawValue,
                    scope: item.scope.rawValue,
                    isCompleted: completedIDs.contains(item.id),
                    ownerUserID: personal ? userID : nil,
                    ownerEmail: personal ? email : nil
                ), accessToken: token)
                pendingUploadIDs.remove(item.id)
            }

            let records = try await checklistService.fetch(accessToken: token)
            checklistItems = records.compactMap(\.item)
            completedIDs = Set(records.filter(\.isCompleted).map(\.id))
            checklistLastSyncedAt = Date()
            checklistErrorMessage = nil
            saveChecklist()
        } catch {
            checklistErrorMessage = "Checklist guardada offline. Sincronização pendente: \(error.localizedDescription)"
            saveChecklist()
        }
    }

    private func saveChecklist() {
        if let data = try? JSONEncoder().encode(items(in: .general)) {
            defaults.set(data, forKey: generalItemsKey)
        }
        defaults.set(Array(completedIDs.intersection(items(in: .general).map(\.id))), forKey: generalCompletedKey)
        defaults.set(Array(pendingUploadIDs.intersection(items(in: .general).map(\.id))), forKey: generalPendingUploadsKey)
        defaults.set(Array(pendingGeneralDeletionIDs), forKey: generalPendingDeletionsKey)

        if let email = currentUserEmail {
            if let data = try? JSONEncoder().encode(items(in: .personal)) {
                defaults.set(data, forKey: personalItemsKey(email))
            }
            defaults.set(Array(completedIDs.intersection(items(in: .personal).map(\.id))), forKey: personalCompletedKey(email))
            defaults.set(Array(pendingUploadIDs.intersection(items(in: .personal).map(\.id))), forKey: personalPendingUploadsKey(email))
            defaults.set(Array(pendingPersonalDeletionIDs), forKey: personalPendingDeletionsKey(email))
        }
    }

    private func synchronizeSoon() {
        guard let authentication else { return }
        Task { await syncChecklist(authentication: authentication) }
    }

    private func personalItemsKey(_ email: String) -> String { "checklist.personal.items.\(email)" }
    private func personalCompletedKey(_ email: String) -> String { "checklist.personal.completed.\(email)" }
    private func personalPendingUploadsKey(_ email: String) -> String { "checklist.personal.pendingUploads.\(email)" }
    private func personalPendingDeletionsKey(_ email: String) -> String { "checklist.personal.pendingDeletions.\(email)" }
}
