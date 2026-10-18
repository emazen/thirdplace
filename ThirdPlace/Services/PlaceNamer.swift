import MapKit
import ThirdPlaceCore

/// Turns a cluster centre into something a person recognises, using Apple Maps.
/// Runs on the phone; only the coordinate of a cluster centre is looked up, never a photo.
enum PlaceNamer {
    struct Name: Sendable {
        var name: String
        var category: String
        var area: String
        var locality: String?
    }

    static func describe(_ coordinate: Coordinate, findVenue: Bool) async -> Name {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first

        var venue: MKMapItem?
        if findVenue {
            let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: 200)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: thirdPlaceCategories)
            if let response = try? await MKLocalSearch(request: request).start() {
                venue = response.mapItems
                    .filter { item in
                        guard let category = item.pointOfInterestCategory else { return false }
                        return allowed.contains(category) && distance(item, location) <= 200
                    }
                    .min { distance($0, location) < distance($1, location) }
            }
        }

        let area = placemark?.subLocality ?? placemark?.locality ?? placemark?.administrativeArea ?? "Nearby"
        let name = venue?.name
            ?? placemark?.thoroughfare.map { "Near \($0)" }
            ?? area
        return Name(
            name: name,
            category: category(for: venue?.pointOfInterestCategory),
            area: area,
            locality: placemark?.locality ?? placemark?.administrativeArea ?? placemark?.country
        )
    }

    static func search(_ query: String) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        return (try? await MKLocalSearch(request: request).start().mapItems) ?? []
    }

    static func category(for poi: MKPointOfInterestCategory?) -> String {
        guard let raw = poi?.rawValue else { return "Place" }
        let key = raw.replacingOccurrences(of: "MKPOICategory", with: "")
        return labels[key] ?? "Place"
    }

    /// Places people return to and could meet someone. Shops, services and transport are left out.
    private static let thirdPlaceCategories: [MKPointOfInterestCategory] = [
        "Cafe", "Bakery", "Restaurant", "Brewery", "Winery", "Distillery", "Nightlife", "MusicVenue",
        "FitnessCenter", "RockClimbing", "Swimming", "Bowling", "Golf", "MiniGolf", "Tennis",
        "Soccer", "Basketball", "Volleyball", "Skating", "SkatePark", "Surfing", "Kayaking", "Hiking",
        "Park", "NationalPark", "Beach", "Marina", "Campground", "Library", "Museum", "Theater",
        "MovieTheater", "Stadium", "Zoo", "Aquarium", "Planetarium", "University"
    ].map { MKPointOfInterestCategory(rawValue: "MKPOICategory\($0)") }

    // The filter alone isn't reliable on every iOS version, so results are checked again.
    private static let allowed = Set(thirdPlaceCategories)

    private static func distance(_ item: MKMapItem, _ location: CLLocation) -> CLLocationDistance {
        item.placemark.location?.distance(from: location) ?? .greatestFiniteMagnitude
    }

    // Keyed by raw value so newer categories work without availability checks.
    private static let labels: [String: String] = [
        "Cafe": "Café", "Bakery": "Bakery", "Restaurant": "Restaurant", "Brewery": "Brewery",
        "Winery": "Wine bar", "Distillery": "Distillery", "Nightlife": "Bar", "MusicVenue": "Music venue",
        "FitnessCenter": "Gym", "RockClimbing": "Climbing gym", "Swimming": "Pool", "Spa": "Spa",
        "Bowling": "Bowling", "Golf": "Golf", "MiniGolf": "Mini golf", "Tennis": "Tennis club",
        "Soccer": "Pitch", "Basketball": "Court", "Volleyball": "Court", "Skating": "Rink",
        "SkatePark": "Skate park", "Surfing": "Surf spot", "Kayaking": "Waterfront", "Hiking": "Trail",
        "Park": "Park", "NationalPark": "Park", "Beach": "Beach", "Marina": "Marina", "Campground": "Campsite",
        "Library": "Library", "Museum": "Museum", "Theater": "Theatre", "MovieTheater": "Cinema",
        "Stadium": "Stadium", "ConventionCenter": "Venue", "Fairground": "Fairground",
        "AmusementPark": "Theme park", "Zoo": "Zoo", "Aquarium": "Aquarium", "Planetarium": "Planetarium",
        "Landmark": "Landmark", "Castle": "Landmark", "NationalMonument": "Landmark",
        "Store": "Shop", "University": "Campus", "School": "School"
    ]
}
