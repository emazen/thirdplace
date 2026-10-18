import XCTest
import ThirdPlaceCore
@testable import ThirdPlaceBackend

final class UploadsTests: XCTestCase {
    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testOnlyKeptPlacesAndMomentsLeaveThePhone() {
        let cafe = (51.5450, -0.0553)
        let home = (51.5560, -0.0560)
        let glasto = (51.1550, -2.5850)
        let cafeCell = Geohash.encode(latitude: cafe.0, longitude: cafe.1, precision: 7)
        let glastoArea5 = Geohash.encode(latitude: glasto.0, longitude: glasto.1, precision: 5)

        let points = [
            PhotoPoint(latitude: cafe.0, longitude: cafe.1, date: date(2025, 5, 15, 8, 47)),
            PhotoPoint(latitude: cafe.0, longitude: cafe.1, date: date(2025, 5, 15, 8, 12)),   // same hour: deduped
            PhotoPoint(latitude: home.0, longitude: home.1, date: date(2025, 5, 15, 22, 5)),   // home: dropped
            PhotoPoint(latitude: glasto.0, longitude: glasto.1, date: date(2025, 6, 28, 21, 30)),
            PhotoPoint(latitude: glasto.0, longitude: glasto.1, date: date(2025, 9, 1, 12, 0))  // outside the moment: dropped
        ]

        let rows = Uploads.presence(
            from: points,
            placeCells: [cafeCell],
            moments: [(area5: glastoArea5, start: date(2025, 6, 26, 0), end: date(2025, 6, 28, 0))]
        )

        XCTAssertEqual(rows, [
            PresenceUpload(area: cafeCell, hour: "2025-05-15T08:00:00Z"),
            PresenceUpload(area: Geohash.encode(latitude: glasto.0, longitude: glasto.1, precision: 7), hour: "2025-06-28T21:00:00Z")
        ])
    }

    func testDayFormat() {
        XCTAssertEqual(Uploads.day(date(2024, 12, 31, 23, 59)), "2024-12-31")
    }
}
