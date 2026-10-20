import UIKit
import ThirdPlaceBackend

extension AppModel {
    /// Brings the profile on this phone in line with the server's, downloading photos if this
    /// phone doesn't have them (a new phone, or an account made before photo paths were kept).
    func refreshMyProfile() async {
        guard let backend, let row = try? await backend.myProfile() else { return }
        let photosMatch = row.photoPaths == profile.photoPaths && profilePhotos.count == row.photoPaths.count
        profile.apply(row)
        if !photosMatch {
            var images: [UIImage] = []
            for path in row.photoPaths {
                guard let data = try? await backend.downloadPhoto(path), let image = UIImage(data: data) else {
                    // A photo that won't load: keep what's on the phone rather than half a set.
                    return
                }
                images.append(image)
            }
            profilePhotos = images
        }
        persist(onboarded: true)
    }

    /// Uploads only new photos, saves the profile, then clears out photos that were removed.
    func saveProfile(_ draft: LocalProfile, photos: [EditablePhoto]) async -> Bool {
        guard let backend, let user = backend.currentUserID else {
            profile = draft
            profilePhotos = photos.map(\.image)
            persist(onboarded: true)
            return true
        }
        working = true
        defer { working = false }
        do {
            var paths: [String] = []
            for photo in photos {
                if let path = photo.path {
                    paths.append(path)
                } else {
                    paths.append(try await uploadPhoto(photo.image))
                }
            }
            try await backend.saveProfile(draft.upload(id: user, photoPaths: paths))
            let removed = profile.photoPaths.filter { !paths.contains($0) }
            var saved = draft
            saved.photoPaths = paths
            profile = saved
            profilePhotos = photos.map(\.image)
            persist(onboarded: true)
            remotePeople = nil
            await backend.removePhotos(removed)
            return true
        } catch {
            errorMessage = "Couldn’t save your profile. \(FriendlyError.message(error))"
            return false
        }
    }

    func uploadPhoto(_ image: UIImage) async throws -> String {
        guard let backend else { throw BackendError.notSignedIn }
        guard let jpeg = image.resizedForUpload().jpegData(compressionQuality: 0.82) else {
            throw BackendError.unreadablePhoto
        }
        return try await backend.uploadPhoto(jpeg)
    }
}

extension UIImage {
    /// Profile photos don't need to be bigger than 1600 px on the long side.
    func resizedForUpload(maxSide: CGFloat = 1600) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
