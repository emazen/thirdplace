import Foundation
import Supabase
import ThirdPlaceCore

/// Everything the app asks of the server. Location only ever leaves as blurred presence
/// (a ~150 m area and an hour), and only for places and moments the user kept.
public final class BackendClient: Sendable {
    public static let photoBucket = "profile-photos"

    private let client: SupabaseClient

    public init(config: BackendConfig) {
        client = SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.anonKey,
            options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
        )
    }

    // MARK: Account

    public var currentUserID: UUID? {
        client.auth.currentSession?.user.id
    }

    /// Signs in without an identity provider. The account can be linked to Apple, Google or a
    /// phone number later without losing data.
    @discardableResult
    public func signIn() async throws -> UUID {
        if let session = try? await client.auth.session { return session.user.id }
        return try await client.auth.signInAnonymously().user.id
    }

    public func signOut() async throws {
        try await client.auth.signOut()
    }

    public func deleteAccount(photoPaths: [String]) async throws {
        if !photoPaths.isEmpty {
            _ = try? await client.storage.from(Self.photoBucket).remove(paths: photoPaths)
        }
        try await client.rpc("delete_my_account").execute()
        try? await client.auth.signOut()
    }

    // MARK: Profile

    public func saveProfile(_ profile: ProfileUpload) async throws {
        try await client.from("profiles").upsert(profile).execute()
    }

    /// Uploads one profile photo to <user>/<index>.jpg and returns its storage path.
    public func uploadPhoto(_ jpeg: Data, index: Int) async throws -> String {
        guard let user = currentUserID else { throw BackendError.notSignedIn }
        let path = "\(user.uuidString.lowercased())/\(index).jpg"
        try await client.storage.from(Self.photoBucket)
            .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: true))
        return path
    }

    public func photoURL(_ path: String) async throws -> URL {
        try await client.storage.from(Self.photoBucket).createSignedURL(path: path, expiresIn: 3600)
    }

    // MARK: Places

    public func sync(places: [PlaceUpload], moments: [MomentUpload], presence: [PresenceUpload]) async throws -> SyncResult {
        struct Params: Encodable {
            let kept_places: [PlaceUpload]
            let kept_moments: [MomentUpload]
            let blurred_presence: [PresenceUpload]
        }
        return try await client
            .rpc("sync_my_places", params: Params(kept_places: places, kept_moments: moments, blurred_presence: presence))
            .execute()
            .value
    }

    /// Before sign-up: how many people share these places. Counts only.
    public func preview(_ places: [(key: String, cells: [String])]) async throws -> OverlapPreview {
        struct Candidate: Encodable { let key: String; let cells: [String] }
        struct Params: Encodable { let candidate_places: [Candidate] }
        return try await client
            .rpc("preview_overlaps", params: Params(candidate_places: places.map { Candidate(key: $0.key, cells: $0.cells) }))
            .execute()
            .value
    }

    // MARK: Feed

    public func feed(limit: Int = 20) async throws -> [FeedRow] {
        struct Params: Encodable { let max_results: Int }
        return try await client.rpc("get_feed", params: Params(max_results: limit)).execute().value
    }

    public func likesLeft() async throws -> Int {
        try await client.rpc("likes_left").execute().value
    }

    public func like(_ person: UUID, item: String, comment: String? = nil) async throws -> LikeResult {
        struct Params: Encodable { let target: UUID; let item: String; let comment: String? }
        return try await client
            .rpc("like_person", params: Params(target: person, item: item, comment: comment))
            .execute()
            .value
    }

    public func pass(_ person: UUID) async throws {
        struct Params: Encodable { let target: UUID }
        try await client.rpc("pass_person", params: Params(target: person)).execute()
    }

    public func matches() async throws -> [MatchRow] {
        try await client.rpc("get_matches").execute().value
    }
}

public enum BackendError: LocalizedError {
    case notSignedIn

    public var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You’re not signed in."
        }
    }
}

// MARK: - Turning scan results into uploads

public enum Uploads {
    private static let hourFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public static func day(_ date: Date) -> String { dayFormatter.string(from: date) }

    /// Blurs photo points and keeps only those inside kept places or kept moments, so home,
    /// work and anything the user unticked never leave the phone.
    public static func presence(
        from points: [PhotoPoint],
        placeCells: Set<String>,
        moments: [(area5: String, start: Date, end: Date)]
    ) -> [PresenceUpload] {
        let utc = TimeZone(identifier: "UTC")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        var seen = Set<PresenceUpload>()
        var result: [PresenceUpload] = []
        for point in points {
            let blurred = Blur.blur(point, calendar: calendar)
            let inPlace = placeCells.contains(blurred.area)
            let inMoment = !inPlace && moments.contains { m in
                blurred.area.hasPrefix(m.area5)
                    && point.date >= m.start.addingTimeInterval(-86_400)
                    && point.date <= m.end.addingTimeInterval(2 * 86_400)
            }
            guard inPlace || inMoment else { continue }
            let row = PresenceUpload(area: blurred.area, hour: hourFormatter.string(from: blurred.hour))
            if seen.insert(row).inserted { result.append(row) }
        }
        return result
    }
}
