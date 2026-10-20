import UIKit
import ThirdPlaceBackend

struct LocalProfile: Codable, Hashable {
    var firstName = ""
    var birthday = Calendar.current.date(byAdding: .year, value: -28, to: .now) ?? .now
    var gender = "Woman"
    var showMe = "Everyone"
    var intent = "Dating"
    var verified = false
    var prompts: [ProfilePrompt] = []
    /// Storage paths of the uploaded photos, in the same order as the photos saved on the phone.
    var photoPaths: [String] = []

    static let maxPrompts = 3
    static let maxAnswer = 200

    var age: Int { Calendar.current.dateComponents([.year], from: birthday, to: .now).year ?? 0 }
}

extension LocalProfile {
    // Saves from before prompts and photo paths existed decode with them empty.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        firstName = try c.decode(String.self, forKey: .firstName)
        birthday = try c.decode(Date.self, forKey: .birthday)
        gender = try c.decode(String.self, forKey: .gender)
        showMe = try c.decode(String.self, forKey: .showMe)
        intent = try c.decode(String.self, forKey: .intent)
        verified = try c.decode(Bool.self, forKey: .verified)
        prompts = try c.decodeIfPresent([ProfilePrompt].self, forKey: .prompts) ?? []
        photoPaths = try c.decodeIfPresent([String].self, forKey: .photoPaths) ?? []
    }

    private static let genders = ["Woman": "woman", "Man": "man", "Non-binary": "nonbinary"]
    private static let showMes = ["Women": "women", "Men": "men", "Everyone": "everyone"]
    private static let intents = ["Dating": "dating", "New friends": "friends", "Both": "both"]

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func upload(id: UUID, photoPaths: [String]) -> ProfileUpload {
        ProfileUpload(
            id: id,
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            birthday: Uploads.day(birthday),
            gender: Self.genders[gender] ?? "nonbinary",
            showMe: Self.showMes[showMe] ?? "everyone",
            intent: Self.intents[intent] ?? "both",
            prompts: prompts.map { ProfilePrompt(question: $0.question, answer: $0.answer.trimmingCharacters(in: .whitespacesAndNewlines)) },
            photoPaths: photoPaths
        )
    }

    /// Takes the server's copy, e.g. after signing in on a new phone.
    mutating func apply(_ row: MyProfileRow) {
        firstName = row.firstName
        if let day = Self.dayFormatter.date(from: row.birthday) {
            birthday = day.addingTimeInterval(12 * 3600)
        }
        gender = Self.genders.first { $0.value == row.gender }?.key ?? gender
        showMe = Self.showMes.first { $0.value == row.showMe }?.key ?? showMe
        intent = Self.intents.first { $0.value == row.intent }?.key ?? intent
        verified = row.verified
        prompts = row.prompts
        photoPaths = row.photoPaths
    }
}

/// The questions people can answer. Most lean on places, since that's what everyone here shares.
enum PromptCatalog {
    static let questions = [
        "My third place is…",
        "I’m a regular at…",
        "You’ll find me on a Sunday…",
        "The best spot in my neighbourhood…",
        "If you see me there, say…",
        "A perfect first date…",
        "We’ll get along if…",
        "I’ll know it’s going well if…",
        "Green flags I look for…",
        "My most controversial opinion…",
        "I’m weirdly good at…",
        "The last great thing I ate…",
        "Teach me something about…",
        "My ideal Sunday…"
    ]
}

/// A profile photo while editing: the picture, and where it already lives on the server if it does.
struct EditablePhoto: Identifiable, Equatable {
    let id = UUID()
    var image: UIImage
    var path: String?
}
