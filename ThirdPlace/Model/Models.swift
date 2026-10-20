import Foundation
import ThirdPlaceCore

enum Step: Int, CaseIterable, Codable {
    case welcome, how, privacy, scan, places, moments, reveal, account, basics, photos, prompts, verify, done, feed

    /// Position in the onboarding progress bar, or nil where the bar is hidden.
    var progress: Int? {
        switch self {
        case .welcome, .done, .feed: return nil
        default: return rawValue
        }
    }

    static let progressTotal = Step.verify.rawValue
}

enum PhotoAccess: String, Codable {
    case unknown, full, limited, denied
}

struct MyPlace: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var category: String
    var area: String
    var latitude: Double
    var longitude: Double
    var photoCount: Int?
    var visitDays: Int
    var rhythm: String?
    var monthly: [Int]
    var visitWeeks: [Int]
    var selected: Bool
    /// Every ~150 m cell in the cluster. Nil for places saved before cells were stored.
    var cells: [String]?
    /// The street the photos cluster on, for "Around <street>" names.
    var street: String?
    /// Where and at what hour the photos here were taken. Stays on the phone; drawn on the map.
    var spots: [Spot]?

    var allCells: [String] { cells ?? [id] }

    var meta: String { "\(category) · \(area)" }

    var detail: String {
        guard let rhythm else { return "Added by you" }
        guard visitDays > 0 else { return rhythm }
        return "\(visitDays) \(visitDays == 1 ? "visit" : "visits") · \(rhythm)"
    }

    var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }

    /// "café", "gym", "area", "spot" — for sentences like "Same café, weekday mornings."
    var noun: String {
        category == "Place" ? "spot" : category.lowercased()
    }
}

struct MyMoment: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var place: String
    var start: Date
    var end: Date
    var photoCount: Int
    var selected: Bool

    var dayCount: Int {
        (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) + 1
    }

    /// The ~5 km cell the moment happened in (moment ids start with it).
    var area5: String { String(id.prefix(5)) }

    var monthLabel: String { start.formatted(.dateTime.month(.abbreviated)).uppercased() }
    var yearLabel: String { start.formatted(.dateTime.year()) }

    var meta: String {
        let days = dayCount == 1 ? "1 day" : "\(dayCount) days"
        return "\(place) · \(days) · \(photoCount) photos"
    }

    var stamp: String {
        start.formatted(.dateTime.day().month(.abbreviated).year()).uppercased()
    }
}

struct HiddenPlace: Identifiable, Codable, Hashable {
    var id: String
    var role: PlaceRole
    var area: String

    var title: String { role == .home ? "Looks like home" : "Looks like work" }
    var detail: String { role == .home ? "Where most nights end · \(area)" : "Weekdays, 9 to 6 · \(area)" }
}

struct SavedState: Codable {
    var onboarded: Bool
    var access: PhotoAccess
    var places: [MyPlace]
    var moments: [MyMoment]
    var hidden: [HiddenPlace]
    var profile: LocalProfile
}

/// Normalised map marks for the scan animation (0...1 in both axes).
struct MapMark: Hashable {
    var x: Double
    var y: Double
    var label: String?
}

struct ScanState {
    var startedAt: Date?
    var running = false
    var finished = false
    var photosRead = 0
    var withLocation = 0
    var placeCount = 0
    var areaCount = 0
    var dots: [MapMark] = []
    var rings: [MapMark] = []
}
