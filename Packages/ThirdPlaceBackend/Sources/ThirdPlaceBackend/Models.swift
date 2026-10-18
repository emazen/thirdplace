import Foundation

/// Where the app finds its Supabase project. Loaded from Supabase.json in the app bundle.
public struct BackendConfig: Decodable, Sendable {
    public let url: URL
    public let anonKey: String

    public init(url: URL, anonKey: String) {
        self.url = url
        self.anonKey = anonKey
    }
}

// MARK: - Uploads

public struct ProfileUpload: Encodable, Sendable {
    public var id: UUID
    public var firstName: String
    /// yyyy-MM-dd
    public var birthday: String
    /// woman | man | nonbinary
    public var gender: String
    /// women | men | everyone
    public var showMe: String
    /// dating | friends | both
    public var intent: String
    public var promptQuestion: String?
    public var promptAnswer: String?
    public var photoPaths: [String]

    public init(id: UUID, firstName: String, birthday: String, gender: String, showMe: String, intent: String,
                promptQuestion: String? = nil, promptAnswer: String? = nil, photoPaths: [String] = []) {
        self.id = id
        self.firstName = firstName
        self.birthday = birthday
        self.gender = gender
        self.showMe = showMe
        self.intent = intent
        self.promptQuestion = promptQuestion
        self.promptAnswer = promptAnswer
        self.photoPaths = photoPaths
    }

    enum CodingKeys: String, CodingKey {
        case id, birthday, gender, intent
        case firstName = "first_name"
        case showMe = "show_me"
        case promptQuestion = "prompt_question"
        case promptAnswer = "prompt_answer"
        case photoPaths = "photo_paths"
    }
}

public struct PlaceUpload: Encodable, Sendable {
    public var placeKey: String
    public var cells: [String]
    public var category: String
    public var neighbourhood: String
    public var venueName: String?
    public var rhythm: String?
    public var visitDays: Int

    public init(placeKey: String, cells: [String], category: String, neighbourhood: String,
                venueName: String?, rhythm: String?, visitDays: Int) {
        self.placeKey = placeKey
        self.cells = cells
        self.category = category
        self.neighbourhood = neighbourhood
        self.venueName = venueName
        self.rhythm = rhythm
        self.visitDays = visitDays
    }

    enum CodingKeys: String, CodingKey {
        case cells, category, neighbourhood, rhythm
        case placeKey = "place_key"
        case venueName = "venue_name"
        case visitDays = "visit_days"
    }
}

public struct MomentUpload: Encodable, Sendable {
    public var momentKey: String
    public var area5: String
    public var title: String
    /// yyyy-MM-dd
    public var startsOn: String
    public var endsOn: String

    public init(momentKey: String, area5: String, title: String, startsOn: String, endsOn: String) {
        self.momentKey = momentKey
        self.area5 = area5
        self.title = title
        self.startsOn = startsOn
        self.endsOn = endsOn
    }

    enum CodingKeys: String, CodingKey {
        case area5, title
        case momentKey = "moment_key"
        case startsOn = "starts_on"
        case endsOn = "ends_on"
    }
}

public struct PresenceUpload: Encodable, Sendable, Hashable {
    public var area: String
    /// ISO 8601, already rounded to the hour.
    public var hour: String

    public init(area: String, hour: String) {
        self.area = area
        self.hour = hour
    }
}

public struct SyncResult: Decodable, Sendable {
    public let places: Int
    public let moments: Int
    public let presence: Int
}

// MARK: - Feed

public struct FeedRow: Decodable, Sendable, Identifiable, Hashable {
    public let personID: UUID
    public let firstName: String
    public let age: Int
    public let verified: Bool
    public let photoPaths: [String]
    public let promptQuestion: String?
    public let promptAnswer: String?
    public let neighbourhood: String?
    public let score: Double
    public let crossings: [Crossing]

    public var id: UUID { personID }

    enum CodingKeys: String, CodingKey {
        case age, verified, neighbourhood, score, crossings
        case personID = "person_id"
        case firstName = "first_name"
        case photoPaths = "photo_paths"
        case promptQuestion = "prompt_question"
        case promptAnswer = "prompt_answer"
    }

    public struct Crossing: Decodable, Sendable, Hashable {
        /// place | moment
        public let kind: String
        /// regulars | near_miss | same_moment | same_day | same_place
        public let tier: String
        public let category: String?
        public let neighbourhood: String?
        public let rhythm: String?
        public let myWeeks: [Int]?
        public let theirWeeks: [Int]?
        public let weeksInCommon: Int?
        public let title: String?
        /// yyyy-MM-dd
        public let date: String?

        enum CodingKeys: String, CodingKey {
            case kind, tier, category, neighbourhood, rhythm, title, date
            case myWeeks = "my_weeks"
            case theirWeeks = "their_weeks"
            case weeksInCommon = "weeks_in_common"
        }
    }
}

public struct LikeResult: Decodable, Sendable {
    public let ok: Bool
    public let matched: Bool
    public let likesLeft: Int
    public let reason: String?

    enum CodingKeys: String, CodingKey {
        case ok, matched, reason
        case likesLeft = "likes_left"
    }
}

public struct MatchRow: Decodable, Sendable, Identifiable, Hashable {
    public let personID: UUID
    public let firstName: String
    public let age: Int
    public let photoPaths: [String]
    public let matchedAt: String
    public let sharedPlaces: [SharedPlace]

    public var id: UUID { personID }

    enum CodingKeys: String, CodingKey {
        case age
        case personID = "person_id"
        case firstName = "first_name"
        case photoPaths = "photo_paths"
        case matchedAt = "matched_at"
        case sharedPlaces = "shared_places"
    }

    public struct SharedPlace: Decodable, Sendable, Hashable {
        public let category: String
        public let neighbourhood: String
        public let myVenue: String?
        public let theirVenue: String?

        enum CodingKeys: String, CodingKey {
            case category, neighbourhood
            case myVenue = "my_venue"
            case theirVenue = "their_venue"
        }
    }
}

public struct OverlapPreview: Decodable, Sendable {
    /// People per place key. Places shared with fewer than 2 people report 0.
    public let places: [String: Int]
    /// Distinct people across all the places.
    public let total: Int

    public init(places: [String: Int], total: Int) {
        self.places = places
        self.total = total
    }
}
