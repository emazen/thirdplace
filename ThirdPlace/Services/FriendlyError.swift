import Foundation

/// Turns transport and server errors into one calm sentence. Raw details go to the console only.
enum FriendlyError {
    static func message(_ error: Error) -> String {
        print("Third Place error:", error)
        let text = String(describing: error)
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "You seem to be offline. Check your connection and try again."
            case .timedOut, .cannotConnectToHost, .cannotFindHost:
                return "Third Place is taking too long to answer. Try again in a minute."
            default:
                break
            }
        }
        if text.contains("Status Code: 5") || text.contains("cloudflare") || text.contains("522") || text.contains("503") {
            return "Third Place is having trouble right now. Try again in a minute."
        }
        if text.contains("JWT") || text.contains("not signed in") {
            return "Your session expired. Close and reopen the app."
        }
        return "Something didn’t work. Try again in a moment."
    }
}
