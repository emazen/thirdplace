import UIKit
import ThirdPlaceBackend

/// One profile in the feed: a real person from the server, or a demo stand-in when no backend
/// is configured.
struct FeedPerson: Identifiable, Hashable {
    enum Tier: String {
        case regulars = "Regulars"
        case nearMiss = "Near miss"
        case sameDay = "Same day"
        case sameMoment = "Same moment"
        case samePlace = "Same place"
    }

    struct Crossing: Hashable {
        var tier: Tier
        var title: String
        var detail: String
        /// Week strip (last 52 weeks) for place overlaps.
        var myWeeks: Set<Int>
        var theirWeeks: Set<Int>
        /// A date stamp for moment overlaps.
        var stamp: String?

        var weeksInCommon: Int { myWeeks.intersection(theirWeeks).count }
    }

    let id: Int
    let name: String
    let age: Int
    let line: String
    let tones: (UInt32, UInt32)
    let first: Crossing
    let second: Crossing?
    let prompts: [ProfilePrompt]
    var remoteID: UUID? = nil
    var photoPaths: [String] = []
    /// Your own photos, for previewing your profile.
    var localPhotos: [UIImage] = []

    /// Everyone has at least two photos; demo people show two placeholders.
    var photoCount: Int { max(2, photoPaths.count, localPhotos.count) }

    static func == (lhs: FeedPerson, rhs: FeedPerson) -> Bool { lhs.id == rhs.id && lhs.remoteID == rhs.remoteID }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(remoteID)
    }
}

/// The sentences shown for each kind of crossing. Shared by demo and real people.
enum CrossingText {
    static func place(tier: FeedPerson.Tier, noun: String, rhythm: String?, area: String,
                      myWeeks: Set<Int>, theirWeeks: Set<Int>) -> FeedPerson.Crossing {
        let rhythm = sentenceCase(rhythm ?? "now and then")
        let (title, detail): (String, String)
        switch tier {
        case .regulars:
            (title, detail) = ("Same \(noun), \(rhythm).", "In \(area). The exact place unlocks when you match.")
        case .nearMiss:
            (title, detail) = ("Missed each other by an hour.", "A \(noun) in \(area). They arrived just after you left.")
        case .sameDay:
            (title, detail) = ("Same \(noun), same day.", "In \(area), a few hours apart.")
        case .sameMoment:
            (title, detail) = ("Same \(noun), same hour.", "In \(area). You were there at the same time.")
        case .samePlace:
            (title, detail) = ("Same \(noun), different times.", "In \(area). The exact place unlocks when you match.")
        }
        return .init(tier: tier, title: title, detail: detail, myWeeks: myWeeks, theirWeeks: theirWeeks, stamp: nil)
    }

    static func moment(title: String, stamp: String?) -> FeedPerson.Crossing {
        .init(tier: .sameMoment, title: "Same crowd in \(title).",
              detail: "Within about a kilometre of each other, the same hour.",
              myWeeks: [], theirWeeks: [], stamp: stamp)
    }

    static func noun(for category: String?) -> String {
        guard let category, category != "Place" else { return "spot" }
        return category.lowercased()
    }

    /// "Weekday mornings" → "weekday mornings", but "Tue and Thu evenings" keeps its day names.
    static func sentenceCase(_ text: String) -> String {
        let days = Calendar.current.weekdaySymbols + Calendar.current.shortWeekdaySymbols
        if let first = text.split(separator: " ").first, days.contains(String(first)) { return text }
        return text.prefix(1).lowercased() + text.dropFirst()
    }
}

// MARK: - Real people from the server

extension FeedPerson {
    private static let palette: [(UInt32, UInt32)] = [
        (0xDDD6CC, 0xCDD4D8), (0xD3DACF, 0xDCD1CC), (0xD7CFDA, 0xD8D4C6), (0xCFD8CC, 0xDAD0C8),
        (0xDDD2C6, 0xC9D8D8), (0xDACBD5, 0xD2D6CC), (0xCDD6DD, 0xDDD5CB)
    ]

    init?(row: FeedRow, index: Int) {
        let crossings = row.crossings.compactMap(Self.crossing(from:))
        guard let first = crossings.first else { return nil }
        let tone = Self.palette[abs(row.personID.hashValue) % Self.palette.count]
        self.init(
            id: index,
            name: row.firstName,
            age: row.age,
            line: row.neighbourhood ?? "Nearby",
            tones: tone,
            first: first,
            second: crossings.dropFirst().first,
            prompts: row.prompts,
            remoteID: row.personID,
            photoPaths: row.photoPaths
        )
    }

    private static func crossing(from c: FeedRow.Crossing) -> Crossing? {
        if c.kind == "moment" {
            return CrossingText.moment(title: c.title ?? "a big night out", stamp: stamp(c.date))
        }
        let tier: Tier
        switch c.tier {
        case "regulars": tier = .regulars
        case "near_miss": tier = .nearMiss
        case "same_day": tier = .sameDay
        case "same_moment": tier = .sameMoment
        default: tier = .samePlace
        }
        return CrossingText.place(
            tier: tier,
            noun: CrossingText.noun(for: c.category),
            rhythm: c.rhythm,
            area: c.neighbourhood ?? "your area",
            myWeeks: Set(c.myWeeks ?? []),
            theirWeeks: Set(c.theirWeeks ?? [])
        )
    }

    private static func stamp(_ day: String?) -> String? {
        guard let day else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: day) else { return day }
        return date.formatted(.dateTime.day().month(.abbreviated).year()).uppercased()
    }
}

// MARK: - Demo people

/// Stand-in people built from the user's own places, used when no backend is configured.
/// Every overlap points at one of the user's real places, so the feed feels like theirs.
enum DemoPeople {
    private static let roster: [(String, Int, String)] = [
        ("Maya", 29, "Product designer"), ("Jonah", 31, "Architect"), ("Leila", 27, "Junior doctor"),
        ("Sam", 30, "Chef"), ("Ana", 28, "Photographer"), ("Theo", 32, "Teacher"), ("Noor", 26, "Engineer")
    ]

    private static let tones: [(UInt32, UInt32)] = [
        (0xDDD6CC, 0xCDD4D8), (0xD3DACF, 0xDCD1CC), (0xD7CFDA, 0xD8D4C6), (0xCFD8CC, 0xDAD0C8),
        (0xDDD2C6, 0xC9D8D8), (0xDACBD5, 0xD2D6CC), (0xCDD6DD, 0xDDD5CB)
    ]

    private static let prompts: [ProfilePrompt] = [
        .init(question: "My third place is…", answer: "The lido at 8 am, before anyone else is up."),
        .init(question: "I’m a regular at…", answer: "A tiny bookshop that still writes receipts by hand."),
        .init(question: "My ideal Sunday…", answer: "Long run, longer breakfast, a film I’ve already seen."),
        .init(question: "I’ll know it’s going well if…", answer: "We find a café neither of us has been to yet."),
        .init(question: "My most controversial opinion…", answer: "Bad weather is the best weather for a walk."),
        .init(question: "You’ll find me on a Sunday…", answer: "Front left at every gig, whether I like the band or not."),
        .init(question: "Green flags I look for…", answer: "You know the barista’s name.")
    ]

    static func make(places: [MyPlace], moments: [MyMoment]) -> [FeedPerson] {
        let places = places.filter(\.selected).sorted { $0.visitDays > $1.visitDays }
        let moments = moments.filter(\.selected)
        let count = min(7, places.count + moments.count)
        guard count > 0 else { return [] }

        var people: [FeedPerson] = []
        for i in 0..<count {
            let (name, age, job) = roster[i % roster.count]
            var crossings: [(FeedPerson.Crossing, String)] = []
            if !places.isEmpty {
                let place = places[i % places.count]
                crossings.append((placeCrossing(place, index: i), place.area))
            }
            if !moments.isEmpty {
                let moment = moments[i % moments.count]
                crossings.append((CrossingText.moment(title: moment.title, stamp: moment.stamp), moment.place))
            }
            if crossings.count == 1, places.count > 1 {
                let place = places[(i + 1) % places.count]
                crossings.append((placeCrossing(place, index: i + 1), place.area))
            }
            // Alternate which kind of crossing leads so the feed doesn't feel repetitive.
            if i % 3 == 2, crossings.count == 2 { crossings.swapAt(0, 1) }

            people.append(FeedPerson(
                id: i,
                name: name,
                age: age,
                line: "\(crossings[0].1) · \(job)",
                tones: tones[i % tones.count],
                first: crossings[0].0,
                second: crossings.count > 1 ? crossings[1].0 : nil,
                prompts: [prompts[i % prompts.count], prompts[(i + 3) % prompts.count]]
            ))
        }
        return people
    }

    private static func placeCrossing(_ place: MyPlace, index: Int) -> FeedPerson.Crossing {
        let mine = Set(place.visitWeeks)
        var theirs = Set<Int>()
        var seed = place.id.unicodeScalars.reduce(UInt64(5381)) { ($0 &<< 5) &+ $0 &+ UInt64($1.value) } &+ UInt64(index) &* 7919
        func next() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int(truncatingIfNeeded: seed >> 33)
        }
        for week in 0..<52 {
            let roll = abs(next()) % 100
            if mine.contains(week) ? roll < 55 : roll < 18 { theirs.insert(week) }
        }
        let tiers: [FeedPerson.Tier] = [.regulars, .nearMiss, .sameDay]
        return CrossingText.place(tier: tiers[index % 3], noun: place.noun, rhythm: place.rhythm, area: place.area,
                                  myWeeks: mine, theirWeeks: theirs)
    }
}
