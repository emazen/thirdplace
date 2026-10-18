import Foundation
import CryptoKit
import ThirdPlaceBackend

extension AppModel {
    enum EmailPurpose {
        /// Sign in or create an account with this email.
        case signIn
        /// Add an email to the current "Skip for now" account.
        case link
    }

    var isAnonymousAccount: Bool { backend?.isAnonymous ?? false }
    var accountEmail: String? { backend?.email }
    var emailCodesEnabled: Bool { backend?.config.emailCodes ?? false }
    var appleSignInEnabled: Bool { backend?.config.appleSignIn ?? false }

    func sendEmail(_ email: String, purpose: EmailPurpose) async -> Bool {
        guard let backend else { return false }
        do {
            switch purpose {
            case .signIn: try await backend.sendCode(to: email)
            case .link: try await backend.addEmail(email)
            }
            return true
        } catch {
            errorMessage = emailError(error)
            return false
        }
    }

    /// Supabase's built-in email has a low hourly limit and only delivers to the project's team.
    private func emailError(_ error: Error) -> String {
        let text = String(describing: error).lowercased()
        if text.contains("rate limit") || text.contains("over_email_send_rate_limit") || text.contains("security purposes") {
            return "Too many emails just now. Wait a minute and try again."
        }
        if text.contains("not authorized") || text.contains("email_address_not_authorized") {
            return "That email can’t receive messages yet. While Third Place is in testing, only team email addresses work."
        }
        if text.contains("invalid") && text.contains("email") {
            return "That email address doesn’t look right."
        }
        return "Couldn’t send the email. \(FriendlyError.message(error))"
    }

    func verifyEmail(code: String, email: String, purpose: EmailPurpose) async -> Bool {
        guard let backend else { return false }
        do {
            switch purpose {
            case .signIn:
                try await backend.verifyCode(code, email: email)
                await afterSignIn()
            case .link:
                try await backend.confirmAddedEmail(code, email: email)
            }
            return true
        } catch {
            errorMessage = "That code didn’t work. Check it and try again."
            return false
        }
    }

    /// thirdplace://auth links from sign-in emails.
    func handleOpenURL(_ url: URL) async {
        guard let backend, url.scheme == "thirdplace" else { return }
        do {
            try await backend.handleAuthLink(url)
            authLinkCompleted = true
            await afterSignIn()
        } catch {
            // Email-change confirmations land here without a sign-in code; the change still applied.
            let hadSession = backend.currentUserID != nil
            await backend.refreshAccount()
            if hadSession, backend.email != nil, !url.absoluteString.contains("error") {
                authLinkCompleted = true
            } else {
                errorMessage = "That sign-in link has expired. Ask for a new one."
            }
        }
    }

    // MARK: Sign in with Apple

    /// A random nonce; its SHA-256 goes to Apple and the raw value to Supabase.
    func makeAppleNonce() -> (raw: String, hashed: String) {
        let raw = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        let hashed = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        return (raw, hashed)
    }

    func signInWithApple(idToken: String, nonce: String) async {
        guard let backend else { return }
        do {
            try await backend.signInWithApple(idToken: idToken, nonce: nonce)
            await afterSignIn()
        } catch {
            errorMessage = "Sign in with Apple didn’t work. \(FriendlyError.message(error))"
        }
    }

    // MARK: After any sign-in

    /// Returning people go straight to their feed; new people carry on with onboarding.
    func afterSignIn() async {
        guard let backend else { return }
        let existing = (try? await backend.hasProfile()) ?? false
        if existing {
            finishOnboarding()
        } else if step == .account {
            go(.basics)
        } else if step == .welcome {
            go(.how)
        }
    }

    func signOut() async {
        try? await backend?.signOut()
        reset()
    }
}
