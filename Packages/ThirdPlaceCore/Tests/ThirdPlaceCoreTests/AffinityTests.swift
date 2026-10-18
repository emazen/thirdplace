import XCTest
@testable import ThirdPlaceCore

final class AffinityTests: XCTestCase {
    func testSharedNumberOnePlaceBeatsOneThatIsLowDown() {
        let me = PlaceProfile(visitDays: ["gym": 30, "cafe": 10, "park": 5])
        let sameTop = PlaceProfile(visitDays: ["gym": 25, "bar": 8])
        let lowDown = PlaceProfile(visitDays: ["bar": 30, "pool": 12, "gym": 3])
        XCTAssertEqual(me.topPlace, "gym")
        XCTAssertGreaterThan(Affinity.score(me, sameTop), Affinity.score(me, lowDown))
    }

    func testSpecificPlacesCountMoreThanPopularOnes() {
        let me = PlaceProfile(visitDays: ["bigpark": 10, "bookshop": 10])
        let parkPerson = PlaceProfile(visitDays: ["bigpark": 10, "other": 10])
        let bookPerson = PlaceProfile(visitDays: ["bookshop": 10, "other": 10])
        let spec = [
            "bigpark": Affinity.specificity(visitors: 900, totalUsers: 1000),
            "bookshop": Affinity.specificity(visitors: 5, totalUsers: 1000),
            "other": Affinity.specificity(visitors: 50, totalUsers: 1000)
        ]
        XCTAssertGreaterThan(Affinity.similarity(me, bookPerson, specificity: spec),
                             Affinity.similarity(me, parkPerson, specificity: spec))
    }

    func testNothingInCommonIsZero() {
        let a = PlaceProfile(visitDays: ["a": 3])
        let b = PlaceProfile(visitDays: ["b": 3])
        XCTAssertEqual(Affinity.similarity(a, b), 0)
    }

    func testCopresenceAddsButSaturates() {
        let a = PlaceProfile(visitDays: ["gym": 10])
        XCTAssertGreaterThan(Affinity.score(a, a, sharedHours: 5), Affinity.score(a, a, sharedHours: 0) - 0.0001)
        XCTAssertLessThanOrEqual(Affinity.score(a, a, sharedHours: 500), 1)
        XCTAssertLessThan(Affinity.copresence(sharedHours: 40) - Affinity.copresence(sharedHours: 20), 0.01)
    }
}
