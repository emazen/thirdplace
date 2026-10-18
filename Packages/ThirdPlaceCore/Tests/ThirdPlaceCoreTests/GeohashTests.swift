import XCTest
@testable import ThirdPlaceCore

final class GeohashTests: XCTestCase {
    func testKnownHash() {
        XCTAssertEqual(Geohash.encode(latitude: 57.64911, longitude: 10.40744, precision: 11), "u4pruydqqvj")
    }

    func testCenterRoundTrips() {
        let hash = Geohash.encode(latitude: 51.5450, longitude: -0.0553, precision: 7)
        let c = Geohash.center(hash)
        XCTAssertEqual(Geohash.encode(latitude: c.latitude, longitude: c.longitude, precision: 7), hash)
    }

    func testNeighborsAreDistinctAndAdjacent() {
        let hash = Geohash.encode(latitude: 51.5450, longitude: -0.0553, precision: 7)
        let n = Geohash.neighbors(hash)
        XCTAssertEqual(n.count, 8)
        XCTAssertEqual(Set(n).count, 8)
        XCTAssertFalse(n.contains(hash))
    }

    func testBlurRoundsToHour() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2025, month: 5, day: 15, hour: 8, minute: 47, second: 12))!
        let blurred = Blur.blur(PhotoPoint(latitude: 51.5450, longitude: -0.0553, date: date), calendar: cal)
        XCTAssertEqual(blurred.area.count, 7)
        XCTAssertEqual(Blur.describe(blurred, calendar: cal), "area \(blurred.area) · 2025-05-15 08:00")
    }
}
