import Foundation

/// Geohash cells are how Third Place blurs locations: precision 7 is roughly a 150 m square,
/// which is the only location detail that ever leaves the phone.
public enum Geohash {
    private static let alphabet = Array("0123456789bcdefghjkmnpqrstuvwxyz")
    private static let lookup: [Character: Int] = {
        var map: [Character: Int] = [:]
        for (index, char) in alphabet.enumerated() { map[char] = index }
        return map
    }()

    public static func encode(latitude: Double, longitude: Double, precision: Int = 7) -> String {
        var lat = (-90.0, 90.0)
        var lon = (-180.0, 180.0)
        var hash = ""
        hash.reserveCapacity(precision)
        var bit = 0
        var value = 0
        var evenBit = true

        while hash.count < precision {
            if evenBit {
                let mid = (lon.0 + lon.1) / 2
                if longitude >= mid { value |= 1 << (4 - bit); lon.0 = mid } else { lon.1 = mid }
            } else {
                let mid = (lat.0 + lat.1) / 2
                if latitude >= mid { value |= 1 << (4 - bit); lat.0 = mid } else { lat.1 = mid }
            }
            evenBit.toggle()
            if bit < 4 {
                bit += 1
            } else {
                hash.append(alphabet[value])
                bit = 0
                value = 0
            }
        }
        return hash
    }

    /// The bounding box of a cell.
    public static func bounds(_ hash: String) -> (lat: ClosedRange<Double>, lon: ClosedRange<Double>) {
        var lat = (-90.0, 90.0)
        var lon = (-180.0, 180.0)
        var evenBit = true
        for char in hash {
            guard let value = lookup[char] else { break }
            for shift in stride(from: 4, through: 0, by: -1) {
                let isSet = (value >> shift) & 1 == 1
                if evenBit {
                    let mid = (lon.0 + lon.1) / 2
                    if isSet { lon.0 = mid } else { lon.1 = mid }
                } else {
                    let mid = (lat.0 + lat.1) / 2
                    if isSet { lat.0 = mid } else { lat.1 = mid }
                }
                evenBit.toggle()
            }
        }
        return (lat.0...lat.1, lon.0...lon.1)
    }

    public static func center(_ hash: String) -> (latitude: Double, longitude: Double) {
        let box = bounds(hash)
        return ((box.lat.lowerBound + box.lat.upperBound) / 2, (box.lon.lowerBound + box.lon.upperBound) / 2)
    }

    /// The eight cells around this one.
    public static func neighbors(_ hash: String) -> [String] {
        let box = bounds(hash)
        let dLat = box.lat.upperBound - box.lat.lowerBound
        let dLon = box.lon.upperBound - box.lon.lowerBound
        let mid = center(hash)
        var result: [String] = []
        for i in -1...1 {
            for j in -1...1 where !(i == 0 && j == 0) {
                var lat = mid.latitude + Double(i) * dLat
                var lon = mid.longitude + Double(j) * dLon
                lat = min(max(lat, -89.999999), 89.999999)
                if lon > 180 { lon -= 360 }
                if lon < -180 { lon += 360 }
                result.append(encode(latitude: lat, longitude: lon, precision: hash.count))
            }
        }
        return result
    }
}
