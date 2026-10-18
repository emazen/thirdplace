import Foundation

/// What actually leaves the phone: a ~150 m area code and the hour, nothing else.
public struct BlurredPoint: Sendable, Hashable, Codable {
    public let area: String
    public let hour: Date
}

public enum Blur {
    public static let precision = 7

    public static func blur(_ point: PhotoPoint, calendar: Calendar = .current) -> BlurredPoint {
        let area = Geohash.encode(latitude: point.latitude, longitude: point.longitude, precision: precision)
        let hour = calendar.dateInterval(of: .hour, for: point.date)?.start ?? point.date
        return BlurredPoint(area: area, hour: hour)
    }

    /// The exact line shown on the "See exactly what gets sent" screen.
    public static func describe(_ point: BlurredPoint, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:00"
        return "area \(point.area) · \(formatter.string(from: point.hour))"
    }
}
