import Foundation

/// The two things Third Place reads from a photo: where and when.
public struct PhotoPoint: Sendable, Hashable {
    public let latitude: Double
    public let longitude: Double
    public let date: Date

    public init(latitude: Double, longitude: Double, date: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.date = date
    }
}

public struct Coordinate: Sendable, Hashable, Codable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum PlaceRole: String, Sendable, Codable {
    /// First place. Detected so it can be hidden, never used for matching.
    case home
    /// Second place. Same treatment as home.
    case work
    /// A place you keep returning to. These are what matching runs on.
    case third
}

public struct PlaceCluster: Identifiable, Sendable, Hashable, Codable {
    /// The geohash-7 cell at the cluster's peak. Doubles as the place key for matching.
    public let id: String
    public let center: Coordinate
    public let cells: [String]
    public let photoCount: Int
    /// Distinct calendar days with at least one photo here.
    public let visitDays: Int
    public let firstVisit: Date
    public let lastVisit: Date
    /// A human description such as "Weekday mornings" or "Tue and Thu evenings".
    public let rhythm: String
    /// Visit days per month for the last eight months, oldest first.
    public let monthlyVisits: [Int]
    /// Index of each week (0 = the first week of the last 52) with a visit.
    public let visitWeeks: Set<Int>
    public let role: PlaceRole
}

/// A one-off occasion: a festival, a trip, a big night somewhere far from your usual places.
public struct Moment: Identifiable, Sendable, Hashable, Codable {
    public let id: String
    public let center: Coordinate
    public let start: Date
    public let end: Date
    public let photoCount: Int

    public var dayCount: Int {
        let days = Calendar(identifier: .gregorian).dateComponents([.day], from: start, to: end).day ?? 0
        return days + 1
    }
}

public struct PlaceAnalysis: Sendable {
    public let photosWithLocation: Int
    /// Third places, strongest first.
    public let places: [PlaceCluster]
    /// Home and work, hidden from everyone.
    public let hidden: [PlaceCluster]
    public let moments: [Moment]
    /// Roughly how many cities the photos span (distinct ~40 km cells).
    public let areaCount: Int
}
