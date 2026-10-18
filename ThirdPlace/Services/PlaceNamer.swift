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
        var street: String?
    }

    /// Busy streets have a restaurant every 20 m, so a venue only names a place when the photos
    /// sit right on it. Big places (parks, beaches, stadiums) get more room.
    private static let venueRadius: CLLocationDistance = 50
    private static let largeVenueRadius: CLLocationDistance = 150
    private static let largeCategories: Set<String> = ["Park", "NationalPark", "Beach", "Stadium", "Marina", "Campground", "University", "Zoo", "AmusementPark", "Fairground"]

    static func describe(_ coordinate: Coordinate, findVenue: Bool) async -> Name {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first

        var venue: MKMapItem?
        if findVenue {
            let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: largeVenueRadius)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: thirdPlaceCategories)
            if let response = try? await MKLocalSearch(request: request).start() {
                venue = response.mapItems
                    .filter { item in
                        guard let category = item.pointOfInterestCategory, allowed.contains(category) else { return false }
                        let key = category.rawValue.replacingOccurrences(of: "MKPOICategory", with: "")
                        let limit = largeCategories.contains(key) ? largeVenueRadius : venueRadius
                        return distance(item, location) <= limit
                    }
                    .min { distance($0, location) < distance($1, location) }
            }
        }

        let area = placemark?.subLocality ?? placemark?.locality ?? placemark?.administrativeArea ?? "Nearby"
        let street = placemark?.thoroughfare
        let name = venue?.name ?? "Around \(street ?? area)"
        return Name(
            name: name,
            category: venue == nil ? "Area" : category(for: venue?.pointOfInterestCategory),
            area: area,
            locality: placemark?.locality ?? placemark?.administrativeArea ?? placemark?.country,
            street: street
        )
    }

    /// Everything someone might hang out at within a short walk, nearest first, for the "fix it" sheet.
    static func nearbyVenues(_ coordinate: Coordinate) async -> [MKMapItem] {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: 300)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: thirdPlaceCategories + pickerExtras)
        guard let items = try? await MKLocalSearch(request: request).start().mapItems else { return [] }
        // Maps doesn't always honour the filter, so check categories here too.
        let wanted = allowed.union(pickerExtras)
        return Array(items
            .filter { $0.pointOfInterestCategory.map(wanted.contains) ?? false }
            .sorted { distance($0, location) < distance($1, location) }
            .prefix(12))
    }

    static func distanceLabel(_ item: MKMapItem, from coordinate: Coordinate) -> String {
        let meters = distance(item, CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        return meters < 1000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1000)
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

    /// Also offered when someone fixes a place by hand: bookshops and schools are real hangouts for some.
    private static let pickerExtras: [MKPointOfInterestCategory] = ["Bookstore", "School"]
        .map { MKPointOfInterestCategory(rawValue: "MKPOICategory\($0)") }

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
        "Store": "Shop", "University": "Campus", "School": "School", "Bookstore": "Bookshop"
    ]
}
