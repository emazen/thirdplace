import Foundation

/// Turns raw photo points into places. Runs entirely on the phone.
///
/// 1. Bucket photos into ~150 m cells (geohash 7).
/// 2. Grow clusters by hill-climbing: each cell joins its busiest neighbour, so dense
///    neighbourhoods split into separate peaks instead of chaining into one blob.
/// 3. Name the roles: anywhere you sleep is a home and anywhere you spend weekday working
///    hours is a workplace. People move and change jobs, so there can be several of each.
///    All of them are hidden.
/// 4. Everything else visited on enough separate days is a third place.
/// 5. Leftover bursts of photos far from the usual places become moments.
public struct PlaceAnalyzer {
    public var calendar: Calendar
    public var minVisitDays = 3
    public var minSpanDays = 14
    public var minMomentPhotos = 8
    public var maxPlaces = 12
    public var maxMoments = 6
    public var maxHomes = 3
    public var maxWorkplaces = 3

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func analyze(_ points: [PhotoPoint]) -> PlaceAnalysis {
        guard !points.isEmpty else {
            return PlaceAnalysis(photosWithLocation: 0, places: [], hidden: [], moments: [], areaCount: 0)
        }
        let reference = points.map(\.date).max() ?? Date()

        // 1. Cells.
        var cellPoints: [String: [PhotoPoint]] = [:]
        for point in points {
            let cell = Geohash.encode(latitude: point.latitude, longitude: point.longitude, precision: 7)
            cellPoints[cell, default: []].append(point)
        }
        let cellDays = cellPoints.mapValues { Set($0.map { calendar.startOfDay(for: $0.date) }).count }

        // 2. Hill-climb each cell to its local peak.
        func strength(_ cell: String) -> (Int, Int, String) {
            (cellDays[cell] ?? 0, cellPoints[cell]?.count ?? 0, cell)
        }
        var uphill: [String: String] = [:]
        for cell in cellPoints.keys {
            var best = cell
            for neighbor in Geohash.neighbors(cell) where cellPoints[neighbor] != nil {
                if strength(neighbor) > strength(best) { best = neighbor }
            }
            uphill[cell] = best
        }
        func peak(of cell: String) -> String {
            var current = cell
            var steps = 0
            while let next = uphill[current], next != current, steps < 64 {
                current = next
                steps += 1
            }
            return current
        }
        var clusters: [String: [String]] = [:]
        for cell in cellPoints.keys {
            clusters[peak(of: cell), default: []].append(cell)
        }

        // 3. Describe each cluster.
        struct Candidate {
            let peak: String
            let cells: [String]
            let points: [PhotoPoint]
            let days: Set<Date>
            let nights: Int
            let workDays: Int
            /// Nights followed by a morning photo in the same place: the clearest sign of sleeping there.
            let overnights: Int
            /// Distinct weekdays with night photos. Homes see every day of the week; bars see Fri and Sat.
            let nightWeekdays: Int
        }
        var candidates: [Candidate] = []
        for (peakCell, cells) in clusters {
            let pts = cells.flatMap { cellPoints[$0] ?? [] }
            let days = Set(pts.map { calendar.startOfDay(for: $0.date) })
            var nights = Set<Date>()
            var mornings = Set<Date>()
            var work = Set<Date>()
            for p in pts {
                let hour = calendar.component(.hour, from: p.date)
                let weekday = calendar.component(.weekday, from: p.date)
                if hour >= 21 || hour < 6 {
                    let night = hour < 6 ? calendar.date(byAdding: .day, value: -1, to: p.date) ?? p.date : p.date
                    nights.insert(calendar.startOfDay(for: night))
                }
                if (5..<11).contains(hour) {
                    mornings.insert(calendar.startOfDay(for: p.date))
                }
                if (2...6).contains(weekday) && (9..<18).contains(hour) {
                    work.insert(calendar.startOfDay(for: p.date))
                }
            }
            let overnights = nights.filter { night in
                calendar.date(byAdding: .day, value: 1, to: night).map { mornings.contains($0) } ?? false
            }.count
            let nightWeekdays = Set(nights.map { calendar.component(.weekday, from: $0) }).count
            candidates.append(Candidate(peak: peakCell, cells: cells, points: pts, days: days, nights: nights.count,
                                        workDays: work.count, overnights: overnights, nightWeekdays: nightWeekdays))
        }

        // Homes: places you sleep. A bar you're at every Friday night isn't one, because it has no
        // mornings after and only sees a couple of weekdays.
        let maxNights = candidates.map(\.nights).max() ?? 0
        let homes = candidates
            .filter { c in
                let sleepsHere = c.overnights >= 3 || (c.nights >= 8 && c.nightWeekdays >= 4)
                let topAndPlausible = c.nights == maxNights && c.nights >= 5 && (c.nightWeekdays >= 3 || c.overnights >= 1)
                return (sleepsHere && Double(c.nights) >= max(5, Double(maxNights) * 0.15)) || topAndPlausible
            }
            .sorted { ($0.nights, $0.points.count) > ($1.nights, $1.points.count) }
            .prefix(maxHomes)
        let homePeaks = Set(homes.map(\.peak))

        // Workplaces: weekday working hours make up most of your time there. Old jobs count too.
        let workLike = candidates.filter { c in
            !homePeaks.contains(c.peak) && c.workDays >= 5 && Double(c.workDays) / Double(max(c.days.count, 1)) >= 0.6
        }
        let maxWork = workLike.map(\.workDays).max() ?? 0
        let works = workLike
            .filter { Double($0.workDays) >= max(5, Double(maxWork) * 0.2) }
            .sorted { ($0.workDays, $0.points.count) > ($1.workDays, $1.points.count) }
            .prefix(maxWorkplaces)

        func makeCluster(_ c: Candidate, role: PlaceRole) -> PlaceCluster {
            let lat = c.points.map(\.latitude).reduce(0, +) / Double(c.points.count)
            let lon = c.points.map(\.longitude).reduce(0, +) / Double(c.points.count)
            let dates = c.points.map(\.date)
            return PlaceCluster(
                id: c.peak,
                center: Coordinate(latitude: lat, longitude: lon),
                cells: c.cells.sorted(),
                photoCount: c.points.count,
                visitDays: c.days.count,
                firstVisit: dates.min() ?? reference,
                lastVisit: dates.max() ?? reference,
                rhythm: rhythm(for: c.points),
                monthlyVisits: monthly(days: c.days, reference: reference),
                visitWeeks: weeks(days: c.days, reference: reference),
                role: role,
                spots: sample(c.points)
            )
        }

        let hidden = homes.map { makeCluster($0, role: .home) } + works.map { makeCluster($0, role: .work) }
        let hiddenPeaks = Set(hidden.map(\.id))

        // 4. Third places: returned to on several days, over more than a single trip.
        let third = candidates
            .filter { c in
                guard !hiddenPeaks.contains(c.peak), c.days.count >= minVisitDays,
                      let first = c.days.min(), let last = c.days.max() else { return false }
                let span = calendar.dateComponents([.day], from: first, to: last).day ?? 0
                return span >= minSpanDays
            }
            .sorted { ($0.days.count, $0.points.count, $0.peak) > ($1.days.count, $1.points.count, $1.peak) }
            .prefix(maxPlaces)
            .map { makeCluster($0, role: .third) }

        // 5. Moments from everything that is not a known place.
        let usedCells = Set((hidden + third).flatMap(\.cells))
        let leftovers = cellPoints.filter { !usedCells.contains($0.key) }.flatMap(\.value)
        let moments = findMoments(in: leftovers)

        let areas = Set(points.map { Geohash.encode(latitude: $0.latitude, longitude: $0.longitude, precision: 4) })

        return PlaceAnalysis(
            photosWithLocation: points.count,
            places: Array(third),
            hidden: hidden,
            moments: moments,
            areaCount: areas.count
        )
    }

    /// An even sample of photo positions, for naming and the map. Stays on the phone.
    private func sample(_ points: [PhotoPoint], limit: Int = 80) -> [Spot] {
        let sorted = points.sorted { $0.date < $1.date }
        let step = max(1, sorted.count / limit)
        return stride(from: 0, to: sorted.count, by: step).prefix(limit).map { i in
            let p = sorted[i]
            return Spot(latitude: p.latitude, longitude: p.longitude, hour: calendar.component(.hour, from: p.date))
        }
    }

    // MARK: - Moments

    private func findMoments(in points: [PhotoPoint]) -> [Moment] {
        struct Key: Hashable { let cell: String; let day: Date }
        var groups: [Key: [PhotoPoint]] = [:]
        for p in points {
            let cell = Geohash.encode(latitude: p.latitude, longitude: p.longitude, precision: 5)
            groups[Key(cell: cell, day: calendar.startOfDay(for: p.date)), default: []].append(p)
        }
        // Merge consecutive days in the same ~5 km cell into one moment (festivals, trips).
        var byCell: [String: [(Date, [PhotoPoint])]] = [:]
        for (key, pts) in groups { byCell[key.cell, default: []].append((key.day, pts)) }

        var moments: [Moment] = []
        for (cell, days) in byCell {
            let sorted = days.sorted { $0.0 < $1.0 }
            var run: [(Date, [PhotoPoint])] = []
            func flush() {
                let pts = run.flatMap(\.1)
                if pts.count >= minMomentPhotos, let start = run.first?.0, let end = run.last?.0 {
                    let lat = pts.map(\.latitude).reduce(0, +) / Double(pts.count)
                    let lon = pts.map(\.longitude).reduce(0, +) / Double(pts.count)
                    let stamp = Int(start.timeIntervalSince1970)
                    moments.append(Moment(id: "\(cell)-\(stamp)", center: Coordinate(latitude: lat, longitude: lon), start: start, end: end, photoCount: pts.count))
                }
                run = []
            }
            for day in sorted {
                if let last = run.last?.0, (calendar.dateComponents([.day], from: last, to: day.0).day ?? 99) > 1 { flush() }
                run.append(day)
            }
            flush()
        }
        return Array(moments.sorted { ($0.photoCount, $0.id) > ($1.photoCount, $1.id) }.prefix(maxMoments))
    }

    // MARK: - Descriptions

    private enum Bucket: Int, CaseIterable {
        case morning, afternoon, evening, night
        var plural: String { ["mornings", "afternoons", "evenings", "nights"][rawValue] }
        static func of(hour: Int) -> Bucket {
            switch hour {
            case 5..<12: return .morning
            case 12..<17: return .afternoon
            case 17..<22: return .evening
            default: return .night
            }
        }
    }

    func rhythm(for points: [PhotoPoint]) -> String {
        // Count each (day, bucket) once so a burst of photos doesn't dominate.
        struct Visit: Hashable { let day: Date; let bucket: Bucket; let weekday: Int; let month: Int }
        let visits = Set(points.map { p -> Visit in
            Visit(day: calendar.startOfDay(for: p.date),
                  bucket: .of(hour: calendar.component(.hour, from: p.date)),
                  weekday: calendar.component(.weekday, from: p.date),
                  month: calendar.component(.month, from: p.date))
        })
        guard !visits.isEmpty else { return "Now and then" }
        let total = Double(visits.count)

        var bucketCounts: [Bucket: Int] = [:]
        var weekdayCounts: [Int: Int] = [:]
        var summer = 0
        for v in visits {
            bucketCounts[v.bucket, default: 0] += 1
            weekdayCounts[v.weekday, default: 0] += 1
            if (6...8).contains(v.month) { summer += 1 }
        }
        let bucket = bucketCounts.max { ($0.value, -$0.key.rawValue) < ($1.value, -$1.key.rawValue) }!.key
        let weekdayShare = Double((2...6).reduce(0) { $0 + (weekdayCounts[$1] ?? 0) }) / total
        let isSummer = Double(summer) / total >= 0.7

        let rankedDays = weekdayCounts.sorted { ($0.value, -$0.key) > ($1.value, -$1.key) }
        let full = calendar.weekdaySymbols
        let short = calendar.shortWeekdaySymbols

        if isSummer {
            if weekdayShare <= 0.3 { return "Summer weekends" }
            return "Summer \(bucket.plural)"
        }
        if let top = rankedDays.first, Double(top.value) / total > 0.55 {
            return "\(full[top.key - 1]) \(bucket.plural)"
        }
        if rankedDays.count >= 2 {
            let pair = rankedDays.prefix(2)
            if Double(pair.reduce(0) { $0 + $1.value }) / total >= 0.7 {
                let names = pair.map(\.key).sorted().map { short[$0 - 1] }
                return "\(names[0]) and \(names[1]) \(bucket.plural)"
            }
        }
        if weekdayShare >= 0.75 { return "Weekday \(bucket.plural)" }
        if weekdayShare <= 0.25 { return "Weekend \(bucket.plural)" }
        return "\(bucket.plural.prefix(1).uppercased())\(bucket.plural.dropFirst()), all week"
    }

    private func monthly(days: Set<Date>, reference: Date) -> [Int] {
        let refMonth = calendar.dateInterval(of: .month, for: reference)?.start ?? reference
        var counts = Array(repeating: 0, count: 8)
        for day in days {
            let month = calendar.dateInterval(of: .month, for: day)?.start ?? day
            let back = calendar.dateComponents([.month], from: month, to: refMonth).month ?? 99
            if (0..<8).contains(back) { counts[7 - back] += 1 }
        }
        return counts
    }

    private func weeks(days: Set<Date>, reference: Date) -> Set<Int> {
        var result = Set<Int>()
        for day in days {
            let back = calendar.dateComponents([.weekOfYear], from: day, to: reference).weekOfYear ?? 99
            if (0..<52).contains(back) { result.insert(51 - back) }
        }
        return result
    }
}
