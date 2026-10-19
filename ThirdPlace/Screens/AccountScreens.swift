import SwiftUI
import AuthenticationServices

/// Email sign-in: a link by default, a 6-digit code once custom email templates are on.
struct EmailSignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let purpose: AppModel.EmailPurpose

    @State private var email = ""
    @State private var code = ""
    @State private var sentTo: String?
    @State private var working = false
    @State private var resendAt = Date.distantPast
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                if let sentTo {
                    sent(to: sentTo)
                } else {
                    enterEmail
                }
                Spacer()
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .background(Theme.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(TPFont.body(16))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .onChange(of: model.authLinkCompleted) { _, done in
            if done {
                model.authLinkCompleted = false
                dismiss()
            }
        }
    }

    private var enterEmail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Headline(text: purpose == .link ? "Save your account." : "What’s your email?")
            Subhead(text: purpose == .link
                    ? "Add your email so you can sign back in on a new phone. Your matches and places stay as they are."
                    : (model.emailCodesEnabled
                       ? "We’ll send you a 6-digit code. No password to remember."
                       : "We’ll send you a link to sign in. No password to remember."))
                .padding(.top, 12)
            TextField("Email address", text: $email)
                .font(TPFont.body(17))
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .onSubmit(send)
                .focused($focused)
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(focused ? Theme.ink : Theme.rule))
                .padding(.top, 24)
            Button(working ? "Sending…" : "Send") { send() }
                .buttonStyle(.primary)
                .disabled(!isValid || working)
                .padding(.top, 16)
        }
        .onAppear { focused = true }
    }

    private func sent(to address: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Headline(text: "Check your email.")
            Subhead(text: model.emailCodesEnabled
                    ? "We sent a 6-digit code to \(address)."
                    : "We sent a link to \(address). Open it on this phone and you’re in.")
                .padding(.top, 12)

            if model.emailCodesEnabled {
                TextField("000000", text: $code)
                    .font(TPFont.mono(28, weight: .medium))
                    .tracking(8)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focused)
                    .padding(.horizontal, 16)
                    .frame(height: 64)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(focused ? Theme.ink : Theme.rule))
                    .padding(.top, 24)
                    .onChange(of: code) { _, value in
                        code = String(value.filter(\.isNumber).prefix(6))
                        if code.count == 6 { verify(address) }
                    }
                    .onAppear { focused = true }
                Button(working ? "Checking…" : "Continue") { verify(address) }
                    .buttonStyle(.primary)
                    .disabled(code.count != 6 || working)
                    .padding(.top, 16)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Waiting for you to tap the link…")
                        .font(TPFont.body(15))
                        .foregroundStyle(Theme.ink2)
                }
                .padding(.top, 24)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let wait = Int(resendAt.timeIntervalSince(context.date).rounded(.up))
                HStack(spacing: 16) {
                    Button(wait > 0 ? "Resend in \(wait)s" : "Send again") { send() }
                        .disabled(wait > 0 || working)
                    Button("Use a different email") {
                        sentTo = nil
                        code = ""
                    }
                }
                .buttonStyle(.quiet)
                .padding(.top, 12)
            }

            if purpose == .link && !model.emailCodesEnabled {
                Text("Once you tap the link, your email is saved to this account.")
                    .font(TPFont.body(13))
                    .foregroundStyle(Theme.ink3)
                    .padding(.top, 8)
            }
        }
    }

    private var isValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.contains(".") && trimmed.count >= 6
    }

    private func send() {
        let address = (sentTo ?? email).trimmingCharacters(in: .whitespaces).lowercased()
        guard address.contains("@"), !working else { return }
        working = true
        Task {
            if await model.sendEmail(address, purpose: purpose) {
                sentTo = address
                resendAt = .now.addingTimeInterval(60)
            }
            working = false
        }
    }

    private func verify(_ address: String) {
        guard !working else { return }
        working = true
        Task {
            if await model.verifyEmail(code: code, email: address, purpose: purpose) {
                dismiss()
            } else {
                code = ""
            }
            working = false
        }
    }
}

/// Sign in with Apple, shown only when it's configured (needs an Apple Developer account).
struct AppleSignInButton: View {
    @Environment(AppModel.self) private var model
    @State private var nonce = ""

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            let pair = model.makeAppleNonce()
            nonce = pair.raw
            request.requestedScopes = [.email]
            request.nonce = pair.hashed
        } onCompletion: { result in
            guard case .success(let auth) = result,
                  let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else { return }
            let raw = nonce
            Task { await model.signInWithApple(idToken: token, nonce: raw) }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 56)
        .clipShape(Capsule())
    }
}

/// Your account: email, sign out, delete.
struct YouView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var addingEmail = false
    @State private var confirmDelete = false
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 14) {
                        if let first = model.profilePhotos.first {
                            Image(uiImage: first).resizable().scaledToFill()
                                .frame(width: 64, height: 64).clipShape(Circle())
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Headline(text: model.profile.firstName.isEmpty ? "You" : model.profile.firstName, size: 28)
                            MonoLabel(text: "\(model.selectedPlaceCount) \(model.selectedPlaceCount == 1 ? "place" : "places") · \(model.matches.count) \(model.matches.count == 1 ? "match" : "matches")")
                        }
                    }
                    .padding(.top, 8)

                    MonoLabel(text: "Account").padding(.top, 32)
                    VStack(spacing: 0) {
                        row {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Email").font(TPFont.body(15)).foregroundStyle(Theme.ink)
                                Text(model.accountEmail ?? "Not added yet")
                                    .font(TPFont.body(14))
                                    .foregroundStyle(model.accountEmail == nil ? Theme.accent : Theme.ink2)
                            }
                            Spacer()
                            if model.isAnonymousAccount {
                                Button("Add") { addingEmail = true }
                                    .font(TPFont.body(15, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                        if model.isAnonymousAccount {
                            Text("Without an email, this account only lives on this phone. Add one so you can sign back in.")
                                .font(TPFont.body(13))
                                .foregroundStyle(Theme.ink2)
                                .padding(.horizontal, 18)
                                .padding(.bottom, 14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.rule))
                    .padding(.top, 10)

                    MonoLabel(text: "Your places").padding(.top, 24)
                    Button {
                        dismiss()
                        model.startRescan()
                    } label: {
                        row {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Rescan my photos").font(TPFont.body(15)).foregroundStyle(Theme.ink)
                                Text("Pick up new photos and fix place names. Your matches stay.")
                                    .font(TPFont.body(13))
                                    .foregroundStyle(Theme.ink2)
                            }
                            Spacer()
                            Image(systemName: "arrow.clockwise").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink2)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.rule))
                    .padding(.top, 10)

                    VStack(spacing: 0) {
                        Button {
                            if model.isAnonymousAccount { confirmSignOut = true } else { Task { await model.signOut() } }
                        } label: {
                            row { Text("Sign out").font(TPFont.body(15)).foregroundStyle(Theme.ink); Spacer() }
                        }
                        .buttonStyle(.plain)
                        Hairline(color: Theme.ruleSoft)
                        Button { confirmDelete = true } label: {
                            row { Text("Delete my account").font(TPFont.body(15)).foregroundStyle(Theme.accent); Spacer() }
                        }
                        .buttonStyle(.plain)
                    }
                    .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.rule))
                    .padding(.top, 16)

                    Text("Deleting removes your profile, photos, places, likes, matches and messages from Third Place the same day.")
                        .font(TPFont.body(13))
                        .foregroundStyle(Theme.ink3)
                        .padding(.top, 10)
                        .padding(.horizontal, 2)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .background(Theme.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(TPFont.body(16, weight: .medium))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .sheet(isPresented: $addingEmail) {
            EmailSignInView(purpose: .link)
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                Task { await model.deleteAccount() }
            }
        } message: {
            Text("This can’t be undone.")
        }
        .confirmationDialog("Sign out without an email?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Add an email first") { addingEmail = true }
            Button("Sign out and lose this account", role: .destructive) {
                Task { await model.signOut() }
            }
        } message: {
            Text("This account has no email, so you won’t be able to sign back in.")
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12, content: content)
            .padding(.horizontal, 18)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
    }
}
