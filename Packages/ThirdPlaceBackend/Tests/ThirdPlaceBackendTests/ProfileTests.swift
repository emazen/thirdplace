import XCTest
@testable import ThirdPlaceBackend

final class ProfileTests: XCTestCase {
    func testPromptsUploadAsTheShapeTheDatabaseChecks() throws {
        let upload = ProfileUpload(
            id: UUID(), firstName: "Ada", birthday: "1995-02-01", gender: "woman", showMe: "everyone", intent: "dating",
            prompts: [ProfilePrompt(question: "Green flag", answer: "Kind to waiters.")], photoPaths: []
        )
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(upload)) as! [String: Any]
        let prompts = json["prompts"] as! [[String: String]]
        XCTAssertEqual(prompts, [["q": "Green flag", "a": "Kind to waiters."]])
    }

    func testFeedRowsReadEveryPrompt() throws {
        let json = """
        {"person_id": "00000000-0000-0000-0000-000000000201", "first_name": "Ada", "age": 30, "verified": true,
         "photo_paths": ["a/1.jpg"], "neighbourhood": "Hackney", "score": 0.5, "crossings": [],
         "prompts": [{"q": "One", "a": "1"}, {"q": "Two", "a": "2"}]}
        """
        let row = try JSONDecoder().decode(FeedRow.self, from: Data(json.utf8))
        XCTAssertEqual(row.prompts.map(\.question), ["One", "Two"])
    }
}
