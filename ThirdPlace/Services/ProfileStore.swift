import UIKit

/// Local persistence until the backend exists: one JSON file plus profile photos.
struct ProfileStore {
    private var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ThirdPlace", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var stateURL: URL { folder.appendingPathComponent("state.json") }

    func load() -> SavedState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(SavedState.self, from: data)
    }

    func save(_ state: SavedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    func loadPhotos() -> [UIImage] {
        (0..<6).compactMap { UIImage(contentsOfFile: folder.appendingPathComponent("photo-\($0).jpg").path) }
    }

    func savePhotos(_ images: [UIImage]) {
        for index in 0..<6 {
            let url = folder.appendingPathComponent("photo-\(index).jpg")
            if index < images.count, let data = images[index].jpegData(compressionQuality: 0.85) {
                try? data.write(to: url, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    func reset() {
        try? FileManager.default.removeItem(at: folder)
    }
}
