import Photos
import ThirdPlaceCore

/// Reads only where and when each photo was taken. The image data is never loaded.
enum PhotoLibraryReader {
    struct Result: Sendable {
        let photosRead: Int
        let points: [PhotoPoint]
    }

    static func requestAccess() async -> PhotoAccess {
        switch await PHPhotoLibrary.requestAuthorization(for: .readWrite) {
        case .authorized: return .full
        case .limited: return .limited
        default: return .denied
        }
    }

    static func read() async -> Result {
        await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.includeAssetSourceTypes = [.typeUserLibrary]
            let assets = PHAsset.fetchAssets(with: .image, options: options)
            var points: [PhotoPoint] = []
            points.reserveCapacity(assets.count)
            assets.enumerateObjects { asset, _, _ in
                guard let location = asset.location, let date = asset.creationDate else { return }
                let c = location.coordinate
                guard CLLocationCoordinate2DIsValid(c), !(c.latitude == 0 && c.longitude == 0) else { return }
                points.append(PhotoPoint(latitude: c.latitude, longitude: c.longitude, date: date))
            }
            return Result(photosRead: assets.count, points: points)
        }.value
    }
}
