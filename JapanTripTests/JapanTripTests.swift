import XCTest
import UIKit
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

    func testReturnDateConflictRemainsVisible() {
        let returnLeg = FlightLeg.trip.first { $0.flightNumber == "EK317" }
        XCTAssertNotNil(returnLeg)
        XCTAssertFalse(returnLeg?.isDateConfirmed ?? true)
        XCTAssertTrue(returnLeg?.dateText.contains("confirmar") ?? false)
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
    func testSharedPasswordUnlocksAndWrongPasswordFails() {
        let authentication = AuthenticationManager()
        XCTAssertFalse(authentication.authenticate(password: "rakeru"), "A senha deve respeitar maiúsculas")
        XCTAssertFalse(authentication.isAuthenticated)
        XCTAssertTrue(authentication.authenticate(password: "Rakeru"))
        XCTAssertTrue(authentication.isAuthenticated)
    }

    func testHomeResetsNavigationState() {
        let navigation = AppNavigationState()
        navigation.selectedTab = .checklist
        navigation.showsFlights = true
        navigation.showsMobility = true
        let previousRequest = navigation.homeRequestID

        navigation.goHome()

        XCTAssertEqual(navigation.selectedTab, .today)
        XCTAssertFalse(navigation.showsFlights)
        XCTAssertFalse(navigation.showsMobility)
        XCTAssertEqual(navigation.homeRequestID, previousRequest + 1)
    }
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
