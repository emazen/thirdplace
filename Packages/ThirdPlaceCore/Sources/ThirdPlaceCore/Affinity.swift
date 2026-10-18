import Foundation

/// How much of someone's third-place life happens at each place.
/// Weights sum to 1, so the biggest weight is their "#1 place".
public struct PlaceProfile: Sendable, Hashable {
    public let weights: [String: Double]

    public init(visitDays: [String: Int]) {
        let total = Double(visitDays.values.reduce(0, +))
        if total > 0 {
            weights = visitDays.filter { $0.value > 0 }.mapValues { Double($0) / total }
        } else {
            weights = [:]
        }
    }

    public var topPlace: String? {
        weights.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key
    }
}

/// Ranking signals for "who should I see first".
///
/// The core idea: two people who share a #1 place share a routine, not just a postcode.
/// Similarity is the cosine between place profiles, with each place weighted by how
/// specific it is, so a 20-person bookshop counts for far more than a city park.
public enum Affinity {
    /// Inverse place frequency. `visitors` is how many users have this place in their profile.
    public static func specificity(visitors: Int, totalUsers: Int) -> Double {
        guard totalUsers > 0 else { return 1 }
        return log(Double(totalUsers + 1) / Double(max(visitors, 0) + 1)) + 1
    }

    /// 0 (nothing in common) to 1 (identical place lives).
    public static func similarity(_ a: PlaceProfile, _ b: PlaceProfile, specificity: [String: Double] = [:]) -> Double {
        func weight(_ key: String) -> Double { specificity[key] ?? 1 }
        var dot = 0.0
        for (key, wa) in a.weights {
            if let wb = b.weights[key] {
                let s = weight(key)
                dot += (wa * s) * (wb * s)
            }
        }
        guard dot > 0 else { return 0 }
        let normA = sqrt(a.weights.reduce(0) { $0 + pow($1.value * weight($1.key), 2) })
        let normB = sqrt(b.weights.reduce(0) { $0 + pow($1.value * weight($1.key), 2) })
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA * normB)
    }

    /// Extra credit for having actually been there at the same time.
    /// `sharedHours` counts blurred (area, hour) slots both people have. Saturates around 10.
    public static func copresence(sharedHours: Int) -> Double {
        1 - exp(-Double(max(sharedHours, 0)) / 4)
    }

    /// The score the feed sorts by. Place overlap leads; same-time presence and a shared
    /// #1 place add to it. Reciprocity (will they like you back) is layered on server-side later.
    public static func score(_ a: PlaceProfile, _ b: PlaceProfile, specificity: [String: Double] = [:], sharedHours: Int = 0) -> Double {
        let base = similarity(a, b, specificity: specificity)
        let sameTop = (a.topPlace != nil && a.topPlace == b.topPlace) ? 0.15 : 0
        return min(1, 0.75 * base + 0.1 * copresence(sharedHours: sharedHours) + sameTop)
    }
}
