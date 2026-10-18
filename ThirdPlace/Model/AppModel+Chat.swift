import Foundation
import ThirdPlaceBackend

extension AppModel {
    var unreadTotal: Int { matches.reduce(0) { $0 + $1.unread } }

    func loadMatches() async {
        guard let backend else { return }
        do {
            matches = try await backend.matches()
        } catch {
            errorMessage = "Couldn’t load your matches. \(FriendlyError.message(error))"
        }
    }

    func unmatch(_ match: MatchRow) async {
        guard let backend else { return }
        do {
            try await backend.unmatch(match.personID)
            matches.removeAll { $0.personID == match.personID }
        } catch {
            errorMessage = "Couldn’t unmatch. \(FriendlyError.message(error))"
        }
    }

    func block(_ match: MatchRow) async {
        guard let backend else { return }
        do {
            try await backend.block(match.personID)
            matches.removeAll { $0.personID == match.personID }
        } catch {
            errorMessage = "Couldn’t block. \(FriendlyError.message(error))"
        }
    }

    func report(_ match: MatchRow, reason: ReportReason) async {
        guard let backend else { return }
        do {
            try await backend.report(match.personID, reason: reason)
            matches.removeAll { $0.personID == match.personID }
        } catch {
            errorMessage = "Couldn’t send the report. \(FriendlyError.message(error))"
        }
    }
}

/// One open conversation: history, live updates and sending.
@MainActor
@Observable
final class ChatModel {
    let match: MatchRow
    private let backend: BackendClient
    private(set) var messages: [ChatMessage] = []
    private(set) var loading = true
    var draft = ""
    var sending = false
    var error: String?
    private var liveTask: Task<Void, Never>?

    init(match: MatchRow, backend: BackendClient) {
        self.match = match
        self.backend = backend
    }

    var me: UUID? { backend.currentUserID }

    /// The venue you share, revealed now that you've matched.
    var sharedVenue: String? {
        match.sharedPlaces.first.map { $0.myVenue ?? "\($0.category) in \($0.neighbourhood)" }
    }

    /// Conversation starters that fit the kind of place you share.
    var openers: [String] {
        guard let place = match.sharedPlaces.first else {
            return ["Where else do you end up on a Sunday?", "What’s your favourite spot nearby?"]
        }
        let venue = place.myVenue ?? "the \(place.category.lowercased())"
        let middle: String
        switch place.category {
        case "Café", "Bakery", "Restaurant", "Bar", "Brewery", "Wine bar":
            middle = "What’s your usual order at \(venue)?"
        case "Cinema", "Theatre", "Music venue", "Venue", "Stadium":
            middle = "Seen anything good at \(venue) lately?"
        case "Gym", "Climbing gym", "Pool", "Tennis club", "Pitch", "Court", "Rink", "Skate park":
            middle = "Mornings or evenings at \(venue)?"
        case "Park", "Beach", "Trail", "Marina":
            middle = "What do you usually do at \(venue)?"
        case "Bookshop", "Library", "Museum", "Shop":
            middle = "What did you last find at \(venue)?"
        default:
            middle = "What keeps you going back to \(venue)?"
        }
        return [
            "How long have you been going to \(venue)?",
            middle,
            "Same time at \(venue) next week?"
        ]
    }

    func start() async {
        do {
            messages = try await backend.messages(with: match.personID)
            try? await backend.markRead(from: match.personID)
        } catch {
            self.error = FriendlyError.message(error)
        }
        loading = false
        liveTask?.cancel()
        let stream = backend.liveMessages(with: match.personID)
        liveTask = Task { [weak self] in
            for await message in stream {
                guard let self else { return }
                self.insert(message)
                if message.sender == self.match.personID {
                    try? await self.backend.markRead(from: self.match.personID)
                }
            }
        }
    }

    func stop() {
        liveTask?.cancel()
        liveTask = nil
    }

    func send(_ text: String? = nil) async {
        let body = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !sending else { return }
        sending = true
        defer { sending = false }
        if text == nil { draft = "" }
        do {
            let sent = try await backend.send(body, to: match.personID)
            insert(sent)
            // Replies that land before the live channel is ready still show up.
            if let fresh = try? await backend.messages(with: match.personID) {
                fresh.forEach(insert)
            }
        } catch {
            if text == nil { draft = body }
            self.error = "Couldn’t send. \(FriendlyError.message(error))"
        }
    }

    private func insert(_ message: ChatMessage) {
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        messages.append(message)
        messages.sort { $0.id < $1.id }
    }
}
