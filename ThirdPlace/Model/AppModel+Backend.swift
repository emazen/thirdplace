import UIKit
import SwiftUI
import ThirdPlaceBackend

extension AppModel {
    enum LikeOutcome {
        case sent
        case matched(venue: String?)
        case outOfLikes
        case failed(String)
    }

    // MARK: Before sign-up

    /// Real counts of people who share the kept places. Nothing about the user is stored.
    func loadPreview() async {
        guard let backend else { return }
        let input = places.filter(\.selected).map { (key: $0.id, cells: $0.allCells) }
        guard !input.isEmpty else {
            preview = OverlapPreview(places: [:], total: 0)
            return
        }
        previewFailed = false
        do {
            preview = try await backend.preview(input)
        } catch {
            previewFailed = true
        }
    }

    // MARK: Account

    /// Until Apple, Google and phone sign-in are configured, every option creates an anonymous
    /// account that can be linked to one of them later.
    func signIn() async {
        guard let backend else {
            go(.basics)
            return
        }
        working = true
        defer { working = false }
        do {
            try await backend.signIn()
            go(.basics)
        } catch {
            errorMessage = "Couldn’t sign in. \(FriendlyError.message(error))"
        }
    }

    /// Saves the profile, photos and kept places, then opens the feed.
    func completeSignup() async {
        guard let backend else {
            finishOnboarding()
            return
        }
        working = true
        defer { working = false }
        do {
            let user = try await backend.signIn()
            // A retry after a failed save reuses photos that already went up.
            var paths = Array(profile.photoPaths.prefix(profilePhotos.count))
            for image in profilePhotos.dropFirst(paths.count) {
                paths.append(try await uploadPhoto(image))
                profile.photoPaths = paths
            }
            try await backend.saveProfile(profile.upload(id: user, photoPaths: paths))
            try await syncPlaces()
            finishOnboarding()
        } catch {
            errorMessage = "Couldn’t save your profile. \(FriendlyError.message(error))"
        }
    }

    /// Uploads kept places and moments, plus blurred presence inside them only.
    func syncPlaces() async throws {
        guard let backend else { return }
        let kept = places.filter(\.selected)
        let keptMoments = moments.filter(\.selected)
        let placeUploads = kept.map {
            PlaceUpload(placeKey: $0.id, cells: Array($0.allCells.prefix(64)), category: String($0.category.prefix(40)),
                        neighbourhood: String($0.area.prefix(80)), venueName: String($0.name.prefix(120)),
                        rhythm: $0.rhythm.map { String($0.prefix(60)) }, visitDays: $0.visitDays)
        }
        let momentUploads = keptMoments.map {
            MomentUpload(momentKey: String($0.id.prefix(40)), area5: $0.area5, title: String($0.title.prefix(80)),
                         startsOn: Uploads.day($0.start), endsOn: Uploads.day($0.end))
        }
        let presence = Uploads.presence(
            from: scanPoints,
            placeCells: Set(kept.flatMap(\.allCells)),
            moments: keptMoments.map { (area5: $0.area5, start: $0.start, end: $0.end) }
        )
        _ = try await backend.sync(places: placeUploads, moments: momentUploads, presence: presence)
    }

    // MARK: Rescan

    /// Scan the photo library again (new photos, better naming) without touching the account.
    func startRescan() {
        rescanning = true
        scan = ScanState()
        preview = nil
        restartFlow(at: .scan)
    }

    /// After reviewing places and moments: replace what's shared, then back to the feed.
    func finishRescan() async {
        working = true
        defer { working = false }
        do {
            try await syncPlaces()
            rescanning = false
            remotePeople = nil
            finishOnboarding()
        } catch {
            errorMessage = "Couldn’t update your places. \(FriendlyError.message(error))"
        }
    }

    func deleteAccount() async {
        try? await backend?.deleteAccount()
        reset()
    }

    // MARK: Feed

    func loadFeed() async {
        guard let backend else { return }
        do {
            let rows = try await backend.feed(limit: 30)
            remotePeople = rows.enumerated().compactMap { FeedPerson(row: $1, index: $0) }
            likesLeft = try await backend.likesLeft()
        } catch {
            if remotePeople == nil { remotePeople = [] }
            errorMessage = "Couldn’t load your feed. \(FriendlyError.message(error))"
        }
    }

    func like(_ person: FeedPerson, item: String) async -> LikeOutcome {
        guard let backend, let id = person.remoteID else {
            guard likesLeft > 0 else { return .outOfLikes }
            likesLeft -= 1
            return .sent
        }
        do {
            let result = try await backend.like(id, item: item)
            likesLeft = result.likesLeft
            guard result.ok else { return .outOfLikes }
            if result.matched {
                let match = try? await backend.matches().first { $0.personID == id }
                return .matched(venue: match?.sharedPlaces.first?.myVenue)
            }
            return .sent
        } catch {
            return .failed(FriendlyError.message(error))
        }
    }

    func pass(_ person: FeedPerson) async {
        guard let backend, let id = person.remoteID else { return }
        try? await backend.pass(id)
    }

    /// Takes a real person out of the feed after a like or pass. Demo people just cycle.
    func removeFromFeed(_ person: FeedPerson) {
        remotePeople?.removeAll { $0.remoteID == person.remoteID }
    }

    func photoURL(_ path: String) async -> URL? {
        try? await backend?.photoURL(path)
    }
}
