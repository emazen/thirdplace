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

    /// How sure the best venue has to be before it names a place; below this it's "Around <street>".
    private static let namingThreshold = 0.18

    /// Names a place from its photos. Venues are scored by how many photos sit close to them and
    /// whether the hours fit, not by distance to the average photo, which indoors lands across the
    /// street from where you actually were.
    static func describe(_ coordinate: Coordinate, spots: [Spot] = [], findVenue: Bool) async -> Name {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first

        var venue: MKMapItem?
        if findVenue {
            let ranked = await rankedVenues(around: coordinate, spots: spots)
            if let best = ranked.first, best.support >= namingThreshold {
                venue = best.item
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

    struct RankedVenue: Hashable {
        let item: MKMapItem
        /// 0...1: the share of photos that point at this venue, weighted by how well the hours fit.
        let support: Double
    }

    /// Hangouts near a place, most likely first.
    static func rankedVenues(around coordinate: Coordinate, spots: [Spot], radius: CLLocationDistance = 200) async -> [RankedVenue] {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: radius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: thirdPlaceCategories + pickerExtras)
        guard let items = try? await MKLocalSearch(request: request).start().mapItems else { return [] }
        let wanted = allowed.union(pickerExtras)
        let venues = items.filter { $0.pointOfInterestCategory.map(wanted.contains) ?? false }
        return rank(venues, spots: spots, center: location)
    }

    static func rank(_ items: [MKMapItem], spots: [Spot], center: CLLocation) -> [RankedVenue] {
        // With no photo spots (older saves), fall back to distance from the centre.
        let evidence = spots.isEmpty
            ? [Spot(latitude: center.coordinate.latitude, longitude: center.coordinate.longitude, hour: 12)]
            : spots
        let sigma = 30.0
        return items.map { item -> RankedVenue in
            guard let venueLocation = item.placemark.location else { return RankedVenue(item: item, support: 0) }
            let key = item.pointOfInterestCategory?.rawValue.replacingOccurrences(of: "MKPOICategory", with: "") ?? ""
            let large = largeCategories.contains(key)
            let reach = large ? sigma * 3 : sigma
            var total = 0.0
            for spot in evidence {
                let d = venueLocation.distance(from: CLLocation(latitude: spot.latitude, longitude: spot.longitude))
                total += exp(-(d * d) / (2 * reach * reach)) * timeFit(key, hour: spot.hour)
            }
            return RankedVenue(item: item, support: total / Double(evidence.count))
        }
        .sorted { $0.support > $1.support }
    }

    /// Bars at night, cafés by day. Being there at an odd hour still counts, just less.
    private static func timeFit(_ key: String, hour: Int) -> Double {
        let night = hour >= 18 || hour < 5
        switch key {
        case "Nightlife", "Brewery", "Winery", "Distillery", "MusicVenue":
            return night ? 1 : 0.35
        case "Cafe", "Bakery":
            return (6..<18).contains(hour) ? 1 : 0.45
        case "Restaurant":
            return (11..<15).contains(hour) || (18..<24).contains(hour) ? 1 : 0.6
        case "FitnessCenter", "RockClimbing", "Swimming":
            return (6..<23).contains(hour) ? 1 : 0.4
        default:
            return 1
        }
    }

    private static let largeCategories: Set<String> = ["Park", "NationalPark", "Beach", "Stadium", "Marina", "Campground", "University", "Zoo", "AmusementPark", "Fairground"]

    /// Searches for a venue by name near a place, for when Maps files it oddly.
    static func searchNear(_ query: String, coordinate: Coordinate) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
            latitudinalMeters: 1200, longitudinalMeters: 1200
        )
        let center = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
        return items
            .filter { distance($0, center) <= 1500 }
            .sorted { distance($0, center) < distance($1, center) }
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
