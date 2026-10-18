import Foundation
import ThirdPlaceBackend

/// Reads Supabase.json (project URL + anon key) from the app bundle.
/// The file is gitignored; copy supabase/Supabase.example.json to ThirdPlace/Supabase.json.
enum BackendLoader {
    static func load() -> BackendClient? {
        guard let url = Bundle.main.url(forResource: "Supabase", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(BackendConfig.self, from: data),
              !config.anonKey.isEmpty, !config.anonKey.hasPrefix("YOUR_")
        else { return nil }
        return BackendClient(config: config)
    }
}
