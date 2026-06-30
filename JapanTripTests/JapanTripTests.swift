import XCTest
import UIKit
import CryptoKit
@testable import JapanTrip

final class TripDataTests: XCTestCase {
    func testItineraryContainsEveryTravelDayInOrder() {
        XCTAssertEqual(TripData.days.count, 18)
        XCTAssertEqual(TripData.days.first?.id, "2026-07-08")
        XCTAssertEqual(TripData.days.last?.id, "2026-07-25")
        XCTAssertEqual(Set(TripData.days.map(\.id)).count, TripData.days.count)

        let dates = TripData.days.map(\.date)
        XCTAssertEqual(dates, dates.sorted())
    }

    func testEveryDayHasActivitiesAndUniqueActivityIDs() {
        XCTAssertTrue(TripData.days.allSatisfy { !$0.activities.isEmpty })
        let activities = TripData.days.flatMap(\.activities)
        XCTAssertEqual(Set(activities.map(\.id)).count, activities.count)
    }

    func testExpectedClimateExistsForEveryDay() {
        for day in TripData.days {
            let climate = ExpectedClimate.forDay(day)
            XCTAssertNotNil(climate, "Clima ausente em \(day.id)")
            XCTAssertLessThan(climate?.minimum ?? 100, climate?.maximum ?? 0)
        }
    }

    func testChecklistIDsAreUnique() {
        XCTAssertEqual(Set(TripData.checklist.map(\.id)).count, TripData.checklist.count)
    }

    func testReservationIDsAreUnique() {
        XCTAssertEqual(Set(TripData.reservations.map(\.id)).count, TripData.reservations.count)
    }
}

final class FlightTests: XCTestCase {
    func testAllExpectedEmiratesLegsExist() {
        XCTAssertEqual(FlightLeg.trip.map(\.flightNumber), ["EK262", "EK312", "EK317", "EK261"])
        XCTAssertEqual(FlightLeg.trip.first?.departureAirport, "GRU")
        XCTAssertEqual(FlightLeg.trip.last?.arrivalAirport, "GRU")
    }

    func testReturnFlightsMatchLatestTravelDocument() {
        let returnLeg = FlightLeg.trip.first { $0.flightNumber == "EK317" }
        XCTAssertNotNil(returnLeg)
        XCTAssertTrue(returnLeg?.isDateConfirmed ?? false)
        XCTAssertEqual(returnLeg?.arrivalTime, "04:15 +1")
        XCTAssertEqual(returnLeg?.duration, "9h30")
    }
}

final class HotelTests: XCTestCase {
    func testAllHotelStaysArePresentInOrder() {
        XCTAssertEqual(HotelStay.trip.map(\.city), ["Dubai", "Tóquio", "Kyoto", "Osaka"])
        XCTAssertEqual(HotelStay.trip.map(\.nights).reduce(0, +), 17)
        XCTAssertEqual(Set(HotelStay.trip.map(\.id)).count, 4)
    }

    func testEveryHotelHasUsefulActions() {
        for hotel in HotelStay.trip {
            XCTAssertFalse(hotel.address.isEmpty)
            XCTAssertNotNil(hotel.telephoneURL)
            XCTAssertEqual(hotel.officialURL.scheme, "https")
            XCTAssertEqual(hotel.bookingURL.host, "www.booking.com")
            XCTAssertEqual(hotel.mapURL.host, "maps.apple.com")
        }
    }
}

final class WeatherTests: XCTestCase {
    func testOpenMeteoResponseDecodes() throws {
        let json = #"""
        {
          "current": {
            "time": "2026-07-12T12:00",
            "temperature_2m": 31.2,
            "apparent_temperature": 36.4,
            "relative_humidity_2m": 71,
            "precipitation": 0.2,
            "weather_code": 2,
            "cloud_cover": 44,
            "wind_speed_10m": 12.3
          },
          "daily": {
            "time": ["2026-07-12"],
            "weather_code": [2],
            "temperature_2m_max": [33.0],
            "temperature_2m_min": [24.0],
            "precipitation_probability_max": [30],
            "uv_index_max": [8.1]
          }
        }
        """#

        let snapshot = try JSONDecoder().decode(WeatherSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.current.temperature, 31.2)
        XCTAssertEqual(snapshot.current.humidity, 71)
        XCTAssertEqual(snapshot.daily.maximumTemperature, [33.0])
    }

    func testWeatherCodesProduceReadableConditions() {
        XCTAssertEqual(WeatherCondition.from(code: 0).title, "Céu limpo")
        XCTAssertEqual(WeatherCondition.from(code: 63).title, "Chuva")
        XCTAssertEqual(WeatherCondition.from(code: 95).title, "Trovoada")
        XCTAssertFalse(WeatherCondition.from(code: 999).title.isEmpty)
    }

    func testAllDestinationsHaveCoordinates() {
        XCTAssertEqual(WeatherLocation.destinations.count, 4)
        for location in WeatherLocation.destinations {
            XCTAssertNotEqual(location.latitude, 0)
            XCTAssertNotEqual(location.longitude, 0)
        }
    }
}

@MainActor
final class AuthenticationAndNavigationTests: XCTestCase {
    func testSupabaseLoginUnlocksAndWrongPasswordFails() async {
        let authentication = makeAuthentication()
        let wrongPasswordResult = await authentication.authenticate(email: "ruialmodovar@gmail.com", password: "wrong-password")
        XCTAssertFalse(wrongPasswordResult)
        XCTAssertFalse(authentication.isAuthenticated)
        let validResult = await authentication.authenticate(email: " RUIALMODOVAR@GMAIL.COM ", password: "valid-test-password")
        XCTAssertTrue(validResult)
        XCTAssertTrue(authentication.isAuthenticated)
        XCTAssertEqual(authentication.authenticatedEmail, "ruialmodovar@gmail.com")
        XCTAssertEqual(authentication.authenticatedName, "Rui Coelho")
        authentication.signOut()
    }

    func testOnlyAuthorizedSupabaseUsersUnlock() async {
        let authentication = makeAuthentication()
        let authorized = [
            ("ruialmodovar@gmail.com", "Rui Coelho"),
            ("ana.botinas@gmail.com", "Ana Botinas Coelho"),
            ("raquelbotinascoelho@gmail.com", "Raquel Botinas Coelho"),
            ("mateus80@gmail.com", "Pedro Mateus"),
            ("luestrellado@gmail.com", "Luciana Estrellado"),
            ("biaestrellado@gmail.com", "Beatriz Mateus")
        ]

        for (email, name) in authorized {
            let result = await authentication.authenticate(email: email, password: "valid-test-password")
            XCTAssertTrue(result, email)
            XCTAssertEqual(authentication.authenticatedName, name)
            authentication.signOut()
            XCTAssertNil(authentication.authenticatedName)
        }
        let unauthorizedResult = await authentication.authenticate(email: "intruso@example.com", password: "valid-test-password")
        XCTAssertFalse(unauthorizedResult)
    }

    func testHomeResetsNavigationState() {
        let navigation = AppNavigationState()
        navigation.selectedTab = .checklist
        navigation.showsFlights = true
        navigation.showsHotels = true
        navigation.showsOffline = true
        navigation.showsNotifications = true
        navigation.showsDocumentVault = true
        navigation.showsLocationSharing = true
        navigation.showsExpenses = true
        navigation.showsShopping = true
        navigation.showsMobility = true
        let previousRequest = navigation.homeRequestID

        navigation.goHome()

        XCTAssertEqual(navigation.selectedTab, .today)
        XCTAssertFalse(navigation.showsFlights)
        XCTAssertFalse(navigation.showsHotels)
        XCTAssertFalse(navigation.showsOffline)
        XCTAssertFalse(navigation.showsNotifications)
        XCTAssertFalse(navigation.showsDocumentVault)
        XCTAssertFalse(navigation.showsLocationSharing)
        XCTAssertFalse(navigation.showsExpenses)
        XCTAssertFalse(navigation.showsShopping)
        XCTAssertFalse(navigation.showsMobility)
        XCTAssertEqual(navigation.homeRequestID, previousRequest + 1)
    }

    private func makeAuthentication() -> AuthenticationManager {
        AuthenticationManager(
            authService: MockSupabaseAuthService(),
            sessionStore: InMemorySessionStore()
        )
    }
}

final class OfflineDataTests: XCTestCase {
    func testOfflinePackCoversEveryDestination() {
        XCTAssertEqual(OfflineMapDestination.trip.map(\.city), [.dubai, .tokyo, .kyoto, .osaka])
        XCTAssertEqual(Set(OfflineMapDestination.trip.map(\.id)).count, 4)
    }

    func testEmergencyContactsIncludeBothCountries() {
        XCTAssertTrue(EmergencyContact.trip.contains { $0.country == "Japão" && $0.number == "110" })
        XCTAssertTrue(EmergencyContact.trip.contains { $0.country == "Japão" && $0.number == "119" })
        XCTAssertTrue(EmergencyContact.trip.contains { $0.country == "Emirados Árabes Unidos" && $0.number == "999" })
        XCTAssertTrue(EmergencyContact.trip.contains { $0.country == "Emirados Árabes Unidos" && $0.number == "998" })
    }
}

final class NotificationPlannerTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: NotificationPreferenceKey.agenda)
        defaults.set(true, forKey: NotificationPreferenceKey.reminders)
        defaults.set(true, forKey: NotificationPreferenceKey.hotels)
        defaults.set(true, forKey: NotificationPreferenceKey.weather)
    }

    func testPlanIncludesAgendaFlightsHotelsAndDisney() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-29T12:00:00Z"))
        let plan = TripNotificationPlanner.makePlan(now: now, defaults: defaults)
        XCTAssertTrue(plan.contains { $0.id == "special-disneysea" })
        XCTAssertTrue(plan.contains { $0.id == "checkout-blossom" && $0.title.contains("11:00") })
        XCTAssertTrue(plan.contains { $0.id == "flight-EK317" })
        XCTAssertTrue(plan.contains { $0.kind == .agenda })
        XCTAssertEqual(Set(plan.map(\.id)).count, plan.count)
        XCTAssertLessThanOrEqual(plan.count, 60)
    }

    func testDisabledCategoriesAreNotPlanned() throws {
        defaults.set(false, forKey: NotificationPreferenceKey.agenda)
        defaults.set(false, forKey: NotificationPreferenceKey.hotels)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-29T12:00:00Z"))
        let plan = TripNotificationPlanner.makePlan(now: now, defaults: defaults)
        XCTAssertFalse(plan.contains { $0.kind == .agenda })
        XCTAssertFalse(plan.contains { $0.kind == .hotel })
    }
}

@MainActor
final class DocumentVaultTests: XCTestCase {
    private var directory: URL!
    private var store: DocumentVaultStore!
    private let key = SymmetricKey(size: .bits256)

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = DocumentVaultStore(directory: directory)
        try store.unlockForTesting(with: key)
    }

    override func tearDown() async throws {
        store.lock()
        try? FileManager.default.removeItem(at: directory)
        store = nil
    }

    func testEncryptedImportPreviewAndPersistence() throws {
        let secret = Data("PASSAPORTE-TESTE-123".utf8)
        try store.addDocument(data: secret, name: "Passaporte", category: .passport, fileExtension: "pdf")
        let document = try XCTUnwrap(store.documents.first)

        let encryptedURL = directory.appendingPathComponent(document.encryptedFilename)
        let encrypted = try Data(contentsOf: encryptedURL)
        XCTAssertNotEqual(encrypted, secret)
        XCTAssertFalse(String(decoding: encrypted, as: UTF8.self).contains("PASSAPORTE"))

        let preview = try store.previewURL(for: document)
        XCTAssertEqual(try Data(contentsOf: preview), secret)
        store.cleanupPreview(preview)
        XCTAssertFalse(FileManager.default.fileExists(atPath: preview.path))

        let reloaded = DocumentVaultStore(directory: directory)
        try reloaded.unlockForTesting(with: key)
        XCTAssertEqual(reloaded.documents.first?.name, "Passaporte")
    }

    func testDeleteRemovesEncryptedDocument() throws {
        try store.addDocument(data: Data("QR".utf8), name: "QR Disney", category: .qrCode, fileExtension: "png")
        let document = try XCTUnwrap(store.documents.first)
        let encryptedURL = directory.appendingPathComponent(document.encryptedFilename)
        store.delete(document)
        XCTAssertTrue(store.documents.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: encryptedURL.path))
    }
}

final class LocationSharingDataTests: XCTestCase {
    func testAllSixParticipantsHaveUniqueAccountsAndNames() {
        XCTAssertEqual(TripParticipant.all.count, 6)
        XCTAssertEqual(Set(TripParticipant.all.map(\.email)).count, 6)
        XCTAssertTrue(TripParticipant.all.allSatisfy { !$0.name.isEmpty })
    }

    func testSharedLocationDecodesSupabasePayload() throws {
        let json = #"""
        {
          "user_id": "00000000-0000-0000-0000-000000000001",
          "email": "ruialmodovar@gmail.com",
          "latitude": 35.6762,
          "longitude": 139.6503,
          "accuracy": 42.0,
          "updated_at": "2026-07-13T10:15:30.123Z"
        }
        """#
        let location = try JSONDecoder().decode(SharedParticipantLocation.self, from: Data(json.utf8))
        XCTAssertEqual(location.participant?.name, "Rui Coelho")
        XCTAssertEqual(location.coordinate.latitude, 35.6762)
        XCTAssertNotNil(location.updatedDate)
    }
}

@MainActor
final class ExpenseStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ExpenseStore!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = ExpenseStore(directory: directory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        store = nil
    }

    func testConversionSplitAndBalances() {
        let participants = Set(TripParticipant.all.prefix(2).map(\.email))
        let payer = TripParticipant.all[0].email
        let expense = TripExpense(id: UUID(), title: "Jantar", amount: 2_750, currency: .JPY, date: TripDate.make(13), category: .food, payerEmail: payer, participantEmails: participants, note: "")
        store.add(expense)

        let value = store.amountInBRL(expense)
        XCTAssertEqual(store.totalBRL(), value, accuracy: 0.001)
        XCTAssertEqual(store.balancesBRL()[payer] ?? 0, value / 2, accuracy: 0.001)
        XCTAssertEqual(store.balancesBRL()[TripParticipant.all[1].email] ?? 0, -value / 2, accuracy: 0.001)
    }

    func testExpensesPersistAndDelete() {
        let expense = TripExpense(id: UUID(), title: "Metrô", amount: 20, currency: .AED, date: TripDate.make(9), category: .transport, payerEmail: TripParticipant.all[0].email, participantEmails: Set(TripParticipant.all.map(\.email)), note: "")
        store.add(expense)
        let reloaded = ExpenseStore(directory: directory)
        XCTAssertEqual(reloaded.expenses.first?.title, "Metrô")
        reloaded.delete(expense)
        XCTAssertTrue(reloaded.expenses.isEmpty)
    }
}

final class PriceOCRParserTests: XCTestCase {
    func testRecognizesJapaneseAndInternationalPriceFormats() {
        let text = "SPECIAL PRICE ¥12,800\nAED 249.50\nUSD 79.99\n€65,00"
        let prices = PriceOCRParser.prices(in: text)
        XCTAssertTrue(prices.contains { $0.currency == .JPY && $0.amount == 12_800 })
        XCTAssertTrue(prices.contains { $0.currency == .AED && $0.amount == 249.50 })
        XCTAssertTrue(prices.contains { $0.currency == .USD && $0.amount == 79.99 })
        XCTAssertTrue(prices.contains { $0.currency == .EUR && $0.amount == 65 })
    }

    func testUsesDefaultCurrencyForUnlabelledPrice() {
        let prices = PriceOCRParser.prices(in: "SALE 9,800", defaultCurrency: .JPY)
        XCTAssertEqual(prices.first?.currency, .JPY)
        XCTAssertEqual(prices.first?.amount, 9_800)
    }
}

@MainActor
final class ShoppingStoreTests: XCTestCase {
    func testShoppingItemPersistsAndCanBePurchased() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ShoppingStore(directory: directory)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
            UIColor.systemYellow.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        try store.add(name: "Onitsuka Tiger", image: image, amount: 22_000, currency: .JPY, storeName: "Ginza", taxFreeEnabled: true)
        let item = try XCTUnwrap(store.items.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.imageURL(for: item).path))
        store.markPurchased(item)
        XCTAssertTrue(store.items.first?.isPurchased ?? false)
        XCTAssertEqual(ShoppingStore(directory: directory).items.first?.name, "Onitsuka Tiger")
    }
}

private struct MockSupabaseAuthService: SupabaseAuthenticating {
    func signIn(email: String, password: String) async throws -> SupabaseSession {
        guard password == "valid-test-password" else {
            throw SupabaseAuthError.invalidCredentials
        }
        return makeSession(email: email)
    }

    func refreshSession(refreshToken: String) async throws -> SupabaseSession {
        makeSession(email: "ruialmodovar@gmail.com")
    }

    func signOut(accessToken: String) async {}

    private func makeSession(email: String) -> SupabaseSession {
        .init(
            accessToken: "test-access-token",
            refreshToken: "test-refresh-token",
            expiresIn: 3_600,
            expiresAt: Int(Date().addingTimeInterval(3_600).timeIntervalSince1970),
            user: .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, email: email)
        )
    }
}

private final class InMemorySessionStore: SecureSessionStoring {
    private var session: SupabaseSession?

    func load() -> SupabaseSession? { session }
    func save(_ session: SupabaseSession) throws { self.session = session }
    func clear() { session = nil }
}

@MainActor
final class PhotoJournalTests: XCTestCase {
    private var directory: URL!
    private var store: PhotoJournalStore!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = PhotoJournalStore(directory: directory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        store = nil
    }

    func testCaptureCaptionPersistenceAndDeletion() {
        store.saveCapturedImage(makeTestImage())
        XCTAssertEqual(store.entries.count, 1)

        let entry = try! XCTUnwrap(store.entries.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.imageURL(for: entry).path))

        store.updateCaption(for: entry, caption: "Primeira memória")
        XCTAssertEqual(store.entries.first?.caption, "Primeira memória")

        let reloaded = PhotoJournalStore(directory: directory)
        XCTAssertEqual(reloaded.entries.first?.caption, "Primeira memória")

        store.delete(store.entries[0])
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.imageURL(for: entry).path))
    }

    private func makeTestImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
    }
}
