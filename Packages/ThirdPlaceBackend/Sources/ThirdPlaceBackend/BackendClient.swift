import Foundation
import Supabase
import ThirdPlaceCore

/// Everything the app asks of the server. Location only ever leaves as blurred presence
/// (a ~150 m area and an hour), and only for places and moments the user kept.
public final class BackendClient: Sendable {
    public static let photoBucket = "profile-photos"

    public static let redirectURL = URL(string: "thirdplace://auth")!

    private let client: SupabaseClient
    public let config: BackendConfig

    public init(config: BackendConfig) {
        self.config = config
        // Fail fast instead of hanging for a minute when the server's proxy drops a connection.
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 15
        sessionConfig.waitsForConnectivity = false
        client = SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.anonKey,
            options: SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true),
                global: .init(session: URLSession(configuration: sessionConfig))
            )
        )
    }

    /// Retries reads that hit a timeout or a 5xx from the proxy in front of Supabase,
    /// which happens now and then on the free plan.
    func retrying<T>(_ attempts: Int = 3, _ operation: () async throws -> T) async throws -> T {
        var lastError: Error?
        for attempt in 0..<attempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                guard Self.isTransient(error), attempt < attempts - 1 else { throw error }
                try? await Task.sleep(for: .milliseconds(600 * (attempt + 1)))
            }
        }
        throw lastError ?? BackendError.notSignedIn
    }

    static func isTransient(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet].contains(urlError.code)
        }
        let text = String(describing: error)
        return ["Status Code: 502", "Status Code: 503", "Status Code: 504", "Status Code: 520", "Status Code: 522", "Status Code: 524"]
            .contains { text.contains($0) }
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

    /// True for accounts made with "Skip for now"; they can add an email later without losing anything.
    public var isAnonymous: Bool {
        client.auth.currentSession?.user.isAnonymous ?? false
    }

    public var email: String? {
        guard let email = client.auth.currentSession?.user.email, !email.isEmpty else { return nil }
        return email
    }

    /// Fetches the latest account state (for example after confirming an email change).
    public func refreshAccount() async {
        _ = try? await client.auth.refreshSession()
    }

    /// Emails a sign-in link (or a 6-digit code, once custom templates are on).
    /// Creates the account if this email is new.
    public func sendCode(to email: String) async throws {
        try await client.auth.signInWithOTP(email: email, redirectTo: Self.redirectURL, shouldCreateUser: true)
    }

    /// Finishes sign-in from a link in the email (thirdplace://auth?code=…).
    @discardableResult
    public func handleAuthLink(_ url: URL) async throws -> UUID {
        try await client.auth.session(from: url).user.id
    }

    @discardableResult
    public func verifyCode(_ code: String, email: String) async throws -> UUID {
        let response = try await client.auth.verifyOTP(email: email, token: code, type: .email)
        return response.user.id
    }

    /// Attaches an email to the current (anonymous) account. A 6-digit code is emailed to confirm it.
    public func addEmail(_ email: String) async throws {
        _ = try await client.auth.update(user: UserAttributes(email: email), redirectTo: Self.redirectURL)
    }

    public func confirmAddedEmail(_ code: String, email: String) async throws {
        _ = try await client.auth.verifyOTP(email: email, token: code, type: .emailChange)
    }

    /// Sign in with Apple. Pass the identity token and the raw nonce used for the request.
    @discardableResult
    public func signInWithApple(idToken: String, nonce: String) async throws -> UUID {
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
        return session.user.id
    }

    /// Whether this account already finished onboarding (has a profile row).
    public func hasProfile() async throws -> Bool {
        guard let user = currentUserID else { return false }
        struct Row: Decodable { let id: UUID }
        let rows: [Row] = try await retrying {
            try await client.from("profiles").select("id").eq("id", value: user).execute().value
        }
        return !rows.isEmpty
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
        let params = Params(candidate_places: places.map { Candidate(key: $0.key, cells: $0.cells) })
        return try await retrying {
            try await client.rpc("preview_overlaps", params: params).execute().value
        }
    }

    // MARK: Feed

    public func feed(limit: Int = 20) async throws -> [FeedRow] {
        struct Params: Encodable { let max_results: Int }
        return try await retrying {
            try await client.rpc("get_feed", params: Params(max_results: limit)).execute().value
        }
    }

    public func likesLeft() async throws -> Int {
        try await retrying { try await client.rpc("likes_left").execute().value }
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
        try await retrying { try await client.rpc("get_matches").execute().value }
    }
}

// MARK: - Chat

extension BackendClient {
    /// Conversations are keyed by the two ids in sorted order, the same way the database stores them.
    static func pair(_ x: UUID, _ y: UUID) -> (UUID, UUID) {
        x.uuidString.lowercased() < y.uuidString.lowercased() ? (x, y) : (y, x)
    }

    public func messages(with other: UUID, before: Int? = nil) async throws -> [ChatMessage] {
        struct Params: Encodable { let other: UUID; let before_id: Int?; let max_results: Int }
        let params = Params(other: other, before_id: before, max_results: 50)
        return try await retrying {
            try await client.rpc("get_messages", params: params).execute().value
        }
    }

    @discardableResult
    public func send(_ body: String, to other: UUID) async throws -> ChatMessage {
        struct Params: Encodable { let other: UUID; let body: String }
        return try await client.rpc("send_message", params: Params(other: other, body: body)).execute().value
    }

    public func markRead(from other: UUID) async throws {
        struct Params: Encodable { let other: UUID }
        try await client.rpc("mark_read", params: Params(other: other)).execute()
    }

    public func unmatch(_ other: UUID) async throws {
        struct Params: Encodable { let other: UUID }
        try await client.rpc("unmatch_person", params: Params(other: other)).execute()
    }

    public func block(_ other: UUID) async throws {
        struct Params: Encodable { let other: UUID }
        try await client.rpc("block_person", params: Params(other: other)).execute()
    }

    public func report(_ other: UUID, reason: ReportReason, details: String? = nil) async throws {
        struct Params: Encodable { let other: UUID; let reason: String; let details: String? }
        try await client.rpc("report_person", params: Params(other: other, reason: reason.rawValue, details: details)).execute()
    }

    /// New messages in one conversation as they arrive (both directions).
    public func liveMessages(with other: UUID) -> AsyncStream<ChatMessage> {
        guard let me = currentUserID else { return AsyncStream { $0.finish() } }
        let (a, b) = Self.pair(me, other)
        let client = self.client
        let channel = client.channel("chat-\(a.uuidString.lowercased())-\(b.uuidString.lowercased())")
        let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "messages",
                                             filter: .eq("user_a", value: a))
        return AsyncStream { continuation in
            let task = Task {
                try? await channel.subscribeWithError()
                for await insert in inserts {
                    if let message = try? insert.decodeRecord(as: ChatMessage.self, decoder: JSONDecoder()),
                       message.userB == b {
                        continuation.yield(message)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task { await client.removeChannel(channel) }
            }
        }
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
