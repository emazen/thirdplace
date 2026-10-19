import SwiftUI
import MapKit
import ThirdPlaceCore
import ThirdPlaceBackend

@MainActor
@Observable
final class AppModel {
    var step: Step = .welcome
    private(set) var history: [Step] = []
    private(set) var direction: Edge = .trailing

    var access: PhotoAccess = .unknown
    var scan = ScanState()
    var places: [MyPlace] = []
    var moments: [MyMoment] = []
    var hidden: [HiddenPlace] = []
    var profile = LocalProfile()
    var profilePhotos: [UIImage] = []
    var likesLeft = 8

    /// Nil when no Supabase.json is bundled: the app then runs on-device with demo people.
    let backend: BackendClient? = BackendLoader.load()
    /// This session's photo points, kept in memory only, for the blurred presence upload.
    var scanPoints: [PhotoPoint] = []
    var preview: OverlapPreview?
    /// The reveal couldn't reach the server; it offers a retry instead of a misleading zero.
    var previewFailed = false
    var remotePeople: [FeedPerson]?
    var matches: [MatchRow] = []
    /// Set when an email sign-in link was opened, so the email sheet can close itself.
    var authLinkCompleted = false
    /// True while an existing account re-runs the scan from the You screen.
    var rescanning = false
    var working = false
    var errorMessage: String?

    let store = ProfileStore()

    init() {
        guard let saved = store.load() else { return }
        access = saved.access
        places = saved.places
        moments = saved.moments
        hidden = saved.hidden
        profile = saved.profile
        profilePhotos = store.loadPhotos()
        // Online, the feed needs an account; local data from demo mode alone isn't enough.
        let hasAccount = backend == nil || backend?.currentUserID != nil
        if saved.onboarded && hasAccount { step = .feed }
    }

    var people: [FeedPerson] {
        backend == nil ? DemoPeople.make(places: places, moments: moments) : (remotePeople ?? [])
    }

    /// How many people share the user's places: real counts when online, demo people otherwise.
    var overlapCount: Int {
        backend == nil ? people.count : (remotePeople?.count ?? preview?.total ?? 0)
    }

    // MARK: Navigation

    func go(_ next: Step) {
        history.append(step)
        direction = .trailing
        withAnimation(.smooth(duration: 0.35)) { step = next }
    }

    func back() {
        guard let previous = history.popLast() else { return }
        direction = .leading
        withAnimation(.smooth(duration: 0.35)) { step = previous }
    }

    /// Starts a fresh run of the flow at `next`, with nothing to go back to.
    func restartFlow(at next: Step) {
        history = []
        direction = .trailing
        withAnimation(.smooth(duration: 0.35)) { step = next }
    }

    func finishOnboarding() {
        persist(onboarded: true)
        history = []
        direction = .trailing
        withAnimation(.smooth(duration: 0.35)) { step = .feed }
    }

    func reset() {
        store.reset()
        access = .unknown
        scan = ScanState()
        places = []
        moments = []
        hidden = []
        profile = LocalProfile()
        profilePhotos = []
        likesLeft = 8
        scanPoints = []
        preview = nil
        remotePeople = nil
        matches = []
        rescanning = false
        history = []
        direction = .leading
        withAnimation(.smooth(duration: 0.35)) { step = .welcome }
    }

    func persist(onboarded: Bool) {
        store.save(SavedState(onboarded: onboarded, access: access, places: places, moments: moments, hidden: hidden, profile: profile))
        store.savePhotos(profilePhotos)
    }

    // MARK: Photos

    func requestPhotoAccess() async {
        access = await PhotoLibraryReader.requestAccess()
        if access == .denied {
            places = []
            moments = []
            go(.places)
        } else {
            scan = ScanState()
            go(.scan)
        }
    }

    func runScan() async {
        guard !scan.running, !scan.finished else { return }
        scan = ScanState(startedAt: .now, running: true)

        let result = await PhotoLibraryReader.read()
        scan.photosRead = result.photosRead
        scan.withLocation = result.points.count
        scanPoints = result.points
        scan.dots = MapProjection.dots(for: MapProjection.focus(result.points))

        let points = result.points
        let analysis = await Task.detached(priority: .userInitiated) {
            PlaceAnalyzer().analyze(points)
        }.value
        scan.placeCount = analysis.places.count
        scan.areaCount = analysis.areaCount

        // Name everything in parallel, a few at a time so Apple Maps doesn't throttle us.
        async let namedPlaces = namePlaces(analysis.places)
        async let namedMoments = nameMoments(analysis.moments)
        async let namedHidden = nameHidden(analysis.hidden)
        places = await namedPlaces
        moments = await namedMoments
        hidden = await namedHidden

        let focus = MapProjection.focus(result.points)
        let rings = places.prefix(3).enumerated().map { index, place in
            MapProjection.mark(latitude: place.latitude, longitude: place.longitude, in: focus,
                               label: index == 0 ? "#1 · \(place.name)" : nil)
        }
        scan.rings = rings
        scan.running = false
        scan.finished = true
    }

    private func namePlaces(_ clusters: [PlaceCluster]) async -> [MyPlace] {
        let named = await describeAll(clusters.map(\.center), findVenue: true)
        return clusters.enumerated().map { index, cluster in
            let n = named[index]
            return MyPlace(
                id: cluster.id, name: n.name, category: n.category, area: n.area,
                latitude: cluster.center.latitude, longitude: cluster.center.longitude,
                photoCount: cluster.photoCount, visitDays: cluster.visitDays, rhythm: cluster.rhythm,
                monthly: cluster.monthlyVisits, visitWeeks: cluster.visitWeeks.sorted(),
                selected: index < 6, cells: cluster.cells, street: n.street
            )
        }
    }

    private func nameHidden(_ clusters: [PlaceCluster]) async -> [HiddenPlace] {
        let named = await describeAll(clusters.map(\.center), findVenue: false)
        return clusters.enumerated().map { index, cluster in
            HiddenPlace(id: cluster.id, role: cluster.role, area: named[index].area)
        }
    }

    private func nameMoments(_ found: [Moment]) async -> [MyMoment] {
        let named = await describeAll(found.map(\.center), findVenue: false)
        return found.enumerated().map { index, moment in
            let n = named[index]
            return MyMoment(
                id: moment.id, title: n.locality ?? n.area, place: n.area,
                start: moment.start, end: moment.end, photoCount: moment.photoCount, selected: true
            )
        }
    }

    private func describeAll(_ coordinates: [Coordinate], findVenue: Bool) async -> [PlaceNamer.Name] {
        var results = [PlaceNamer.Name?](repeating: nil, count: coordinates.count)
        await withTaskGroup(of: (Int, PlaceNamer.Name).self) { group in
            var nextIndex = 0
            func addNext() {
                guard nextIndex < coordinates.count else { return }
                let index = nextIndex
                let coordinate = coordinates[index]
                group.addTask { (index, await PlaceNamer.describe(coordinate, findVenue: findVenue)) }
                nextIndex += 1
            }
            for _ in 0..<3 { addNext() }
            for await (index, name) in group {
                results[index] = name
                addNext()
            }
        }
        return results.map { $0 ?? PlaceNamer.Name(name: "A place you return to", category: "Place", area: "Nearby", locality: nil) }
    }

    // MARK: Editing

    func togglePlace(_ id: String) {
        guard let index = places.firstIndex(where: { $0.id == id }) else { return }
        places[index].selected.toggle()
    }

    func addManualPlace(_ item: MKMapItem) {
        let c = item.placemark.coordinate
        let id = Geohash.encode(latitude: c.latitude, longitude: c.longitude, precision: 7)
        guard !places.contains(where: { $0.id == id }) else { return }
        places.append(MyPlace(
            id: id,
            name: item.name ?? "A place you love",
            category: PlaceNamer.category(for: item.pointOfInterestCategory),
            area: item.placemark.subLocality ?? item.placemark.locality ?? "Nearby",
            latitude: c.latitude, longitude: c.longitude,
            photoCount: nil, visitDays: 0, rhythm: nil, monthly: [], visitWeeks: [],
            selected: true
        ))
    }

    var selectedPlaceCount: Int { places.filter(\.selected).count }

    /// The person's own correction of what a place is.
    func renamePlace(_ id: String, name: String, category: String) {
        guard let index = places.firstIndex(where: { $0.id == id }) else { return }
        places[index].name = name
        places[index].category = category
        preview = nil
    }
}

/// Projects photo coordinates into a 0...1 square for the scan animation,
/// zoomed to the user's home turf (the busiest ~40 km area and its neighbours).
enum MapProjection {
    private struct Box { var minLat, maxLat, minLon, maxLon: Double }

    static func focus(_ points: [PhotoPoint]) -> [PhotoPoint] {
        var counts: [String: Int] = [:]
        for p in points { counts[Geohash.encode(latitude: p.latitude, longitude: p.longitude, precision: 4), default: 0] += 1 }
        guard let top = counts.max(by: { $0.value < $1.value })?.key else { return points }
        let keep = Set([top] + Geohash.neighbors(top))
        return points.filter { keep.contains(Geohash.encode(latitude: $0.latitude, longitude: $0.longitude, precision: 4)) }
    }

    private static func box(for points: [PhotoPoint]) -> Box? {
        guard points.count > 1 else { return nil }
        // Trim the outer few percent so one stray photo doesn't zoom the map out.
        let lats = points.map(\.latitude).sorted()
        let lons = points.map(\.longitude).sorted()
        let lo = Int(Double(points.count) * 0.03)
        let hi = max(lo, points.count - 1 - lo)
        return Box(minLat: lats[lo], maxLat: lats[hi], minLon: lons[lo], maxLon: lons[hi])
    }

    private static func project(_ lat: Double, _ lon: Double, _ b: Box) -> (Double, Double) {
        let midLat = (b.minLat + b.maxLat) / 2 * .pi / 180
        let width = max((b.maxLon - b.minLon) * cos(midLat), 0.0001)
        let height = max(b.maxLat - b.minLat, 0.0001)
        let span = max(width, height)
        let x = ((lon - b.minLon) * cos(midLat) + (span - width) / 2) / span
        let y = 1 - ((lat - b.minLat) + (span - height) / 2) / span
        return (min(max(x, 0), 1), min(max(y, 0), 1))
    }

    static func dots(for points: [PhotoPoint]) -> [MapMark] {
        guard let b = box(for: points) else { return [] }
        var seen = Set<String>()
        var marks: [MapMark] = []
        for p in points.sorted(by: { $0.date < $1.date }) {
            let cell = Geohash.encode(latitude: p.latitude, longitude: p.longitude, precision: 8)
            guard seen.insert(cell).inserted else { continue }
            let (x, y) = project(p.latitude, p.longitude, b)
            marks.append(MapMark(x: x, y: y))
            if marks.count >= 400 { break }
        }
        return marks
    }

    static func mark(latitude: Double, longitude: Double, in points: [PhotoPoint], label: String?) -> MapMark {
        guard let b = box(for: points) else { return MapMark(x: 0.5, y: 0.5, label: label) }
        let (x, y) = project(latitude, longitude, b)
        return MapMark(x: x, y: y, label: label)
    }
}
