import XCTest
@testable import ThirdPlaceCore

final class AnalyzerTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        c.firstWeekday = 2
        return c
    }()

    let home = (51.5560, -0.0560)
    let work = (51.5246, -0.0786)
    let cafe = (51.5450, -0.0553)
    let gym = (51.5270, -0.0550)
    let glasto = (51.1550, -2.5850)

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func point(_ place: (Double, Double), _ date: Date, jitter: Int = 0) -> PhotoPoint {
        let j = Double(jitter % 5) * 0.00005
        return PhotoPoint(latitude: place.0 + j, longitude: place.1 - j, date: date)
    }

    /// Forty weeks of a fairly ordinary London life.
    private func fixture() -> [PhotoPoint] {
        var pts: [PhotoPoint] = []
        let start = date(2025, 1, 6, 0) // a Monday
        for week in 0..<40 {
            let monday = cal.date(byAdding: .day, value: week * 7, to: start)!
            func day(_ offset: Int, _ hour: Int) -> Date { cal.date(byAdding: .hour, value: offset * 24 + hour, to: monday)! }
            // Home: evenings most days.
            for d in [0, 2, 4, 6] { pts.append(point(home, day(d, 22), jitter: d)) }
            // Work: weekday afternoons.
            for d in 0..<5 where (week + d) % 2 == 0 { pts.append(point(work, day(d, 14), jitter: d)) }
            // Café: weekday mornings.
            for d in [1, 3] { pts.append(point(cafe, day(d, 8), jitter: d)) }
            // Gym: Tuesday and Thursday evenings.
            if week % 2 == 0 {
                pts.append(point(gym, day(1, 19)))
                pts.append(point(gym, day(3, 19), jitter: 1))
            }
        }
        // Glastonbury: one big weekend.
        for d in 0..<3 {
            for i in 0..<10 { pts.append(point(glasto, date(2025, 6, 27 + d, 14 + i % 8, i), jitter: i)) }
        }
        return pts
    }

    func testFindsHomeAndWorkAndHidesThem() {
        let result = PlaceAnalyzer(calendar: cal).analyze(fixture())
        let roles = Set(result.hidden.map(\.role))
        XCTAssertEqual(roles, [.home, .work])
        let homeCell = Geohash.encode(latitude: home.0, longitude: home.1, precision: 7)
        XCTAssertTrue(result.hidden.first { $0.role == .home }!.cells.contains(homeCell))
        XCTAssertFalse(result.places.contains { $0.cells.contains(homeCell) })
    }

    func testFindsThirdPlacesWithRhythm() {
        let result = PlaceAnalyzer(calendar: cal).analyze(fixture())
        XCTAssertEqual(result.places.count, 2)
        let cafeCell = Geohash.encode(latitude: cafe.0, longitude: cafe.1, precision: 7)
        let gymCell = Geohash.encode(latitude: gym.0, longitude: gym.1, precision: 7)
        let cafePlace = result.places.first { $0.cells.contains(cafeCell) }
        let gymPlace = result.places.first { $0.cells.contains(gymCell) }
        XCTAssertNotNil(cafePlace)
        XCTAssertNotNil(gymPlace)
        XCTAssertEqual(cafePlace?.rhythm, "Tue and Thu mornings")
        XCTAssertEqual(gymPlace?.rhythm, "Tue and Thu evenings")
        // Café is visited more often, so it ranks first.
        XCTAssertEqual(result.places.first?.id, cafePlace?.id)
    }

    func testFindsFestivalAsOneMoment() {
        let result = PlaceAnalyzer(calendar: cal).analyze(fixture())
        XCTAssertEqual(result.moments.count, 1)
        XCTAssertEqual(result.moments.first?.photoCount, 30)
        XCTAssertEqual(result.moments.first?.dayCount, 3)
    }

    func testPeopleWhoMovedHaveTwoHomesAndBothStayHidden() {
        let oldHome = (51.5560, -0.0560)
        let newHome = (51.5000, -0.0200)
        let bar = (51.5300, -0.0700)
        var pts: [PhotoPoint] = []
        let start = date(2025, 1, 6, 0)
        for week in 0..<40 {
            let monday = cal.date(byAdding: .day, value: week * 7, to: start)!
            func day(_ offset: Int, _ hour: Int) -> Date { cal.date(byAdding: .hour, value: offset * 24 + hour, to: monday)! }
            let home = week < 20 ? oldHome : newHome
            for d in [0, 2, 4, 6] {
                pts.append(point(home, day(d, 22), jitter: d))
                pts.append(point(home, day(d + 1, 8), jitter: d))
            }
            // Friday and Saturday nights at the same bar: a third place, not a home.
            pts.append(point(bar, day(4, 23)))
            pts.append(point(bar, day(5, 23), jitter: 1))
        }
        let result = PlaceAnalyzer(calendar: cal).analyze(pts)
        let homeCells = result.hidden.filter { $0.role == .home }.flatMap(\.cells)
        XCTAssertTrue(homeCells.contains(Geohash.encode(latitude: oldHome.0, longitude: oldHome.1, precision: 7)), "old home hidden")
        XCTAssertTrue(homeCells.contains(Geohash.encode(latitude: newHome.0, longitude: newHome.1, precision: 7)), "new home hidden")
        let barCell = Geohash.encode(latitude: bar.0, longitude: bar.1, precision: 7)
        XCTAssertFalse(homeCells.contains(barCell), "the bar is not a home")
        XCTAssertTrue(result.places.contains { $0.cells.contains(barCell) }, "the bar is a third place")
    }

    func testPlacesCarryPhotoSpotsForTheMap() {
        let result = PlaceAnalyzer(calendar: cal).analyze(fixture())
        let cafe = result.places.first!
        XCTAssertFalse(cafe.spots.isEmpty)
        XCTAssertLessThanOrEqual(cafe.spots.count, 80)
        XCTAssertTrue(cafe.spots.allSatisfy { $0.hour == 8 }, "café photos were all taken at 8")
    }

    func testOneOffVisitsAreNotPlaces() {
        let pts = (0..<10).map { point(cafe, date(2025, 3, 1, 10, $0)) }
        let result = PlaceAnalyzer(calendar: cal).analyze(pts)
        XCTAssertTrue(result.places.isEmpty)
    }

    func testEmptyInput() {
        let result = PlaceAnalyzer(calendar: cal).analyze([])
        XCTAssertEqual(result.photosWithLocation, 0)
        XCTAssertTrue(result.places.isEmpty)
    }
}
