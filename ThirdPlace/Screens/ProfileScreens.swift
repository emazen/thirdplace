import SwiftUI
import PhotosUI

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var emailSheet = false

    var body: some View {
        let count = model.overlapCount
        StepScaffold {
            Headline(text: count > 0 ? "Save your \(count) \(count == 1 ? "overlap" : "overlaps")." : "Save your places.")
            Subhead(text: "Make an account to see who they are. It takes a minute.")
                .padding(.top, 12)
            VStack(spacing: 0) {
                Hairline()
                promise("Every profile is selfie-verified", "No bots, no fake likes, no borrowed photos.")
                promise("Places unlock on a match", "Until you both like, people see a neighbourhood, never the exact spot.")
                promise("Leave whenever you like", "Delete your account in two taps. Everything is gone the same day.")
            }
            .padding(.top, 26)
        } footer: {
            if model.backend == nil {
                Button("Continue") { model.go(.basics) }
                    .buttonStyle(.primary)
            } else {
                if model.appleSignInEnabled {
                    AppleSignInButton()
                }
                Button("Continue with email") { emailSheet = true }
                    .buttonStyle(model.appleSignInEnabled ? AnyButtonStyle(.secondary) : AnyButtonStyle(.primary))
                    .padding(.top, model.appleSignInEnabled ? 4 : 0)
                    .sheet(isPresented: $emailSheet) {
                        EmailSignInView(purpose: .signIn)
                    }
                // An anonymous account that can add an email later from the You screen.
                Button(model.working ? "Setting up…" : "Skip for now") { Task { await model.signIn() } }
                    .buttonStyle(.quiet)
                    .disabled(model.working)
            }
        }
    }

    private func promise(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(TPFont.body(16, weight: .semibold)).foregroundStyle(Theme.ink)
            Text(detail).font(TPFont.body(14)).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

struct BasicsView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var nameFocused: Bool

    var body: some View {
        @Bindable var model = model
        StepScaffold {
            Headline(text: "The basics.")
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(text: "First name")
                    TextField("Your first name", text: $model.profile.firstName)
                        .font(TPFont.body(17))
                        .textContentType(.givenName)
                        .focused($nameFocused)
                        .padding(.horizontal, 16)
                        .frame(height: 54)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(nameFocused ? Theme.ink : Theme.rule))
                }
                VStack(alignment: .leading, spacing: 8) {
                    FieldLabel(text: "Birthday")
                    DatePicker("Birthday", selection: $model.profile.birthday, in: ...adultCutoff, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .tint(Theme.ink)
                    Text("We only show your age.")
                        .font(TPFont.body(13))
                        .foregroundStyle(Theme.ink2)
                }
                ChipGroup(title: "I’m a", options: ["Woman", "Man", "Non-binary"], selection: $model.profile.gender)
                ChipGroup(title: "Show me", options: ["Women", "Men", "Everyone"], selection: $model.profile.showMe)
                ChipGroup(title: "Here for", options: ["Dating", "New friends", "Both"], selection: $model.profile.intent)
            }
            .padding(.top, 24)
        } footer: {
            Button("Continue") { model.go(.photos) }
                .buttonStyle(.primary)
                .disabled(model.profile.firstName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var adultCutoff: Date {
        Calendar.current.date(byAdding: .year, value: -18, to: .now) ?? .now
    }
}

struct FieldLabel: View {
    let text: String
    var body: some View {
        Text(text).font(TPFont.body(13, weight: .medium)).foregroundStyle(Theme.ink2)
    }
}

struct ChipGroup: View {
    let title: String
    let options: [String]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(text: title)
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let on = option == selection
                    Button {
                        selection = option
                    } label: {
                        Text(option)
                            .font(TPFont.body(15, weight: .medium))
                            .foregroundStyle(on ? Color.white : Theme.ink)
                            .padding(.horizontal, 18)
                            .frame(height: 44)
                            .background(Capsule().fill(on ? Theme.ink : Theme.surface))
                            .overlay(Capsule().strokeBorder(on ? Theme.ink : Theme.rule))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }
}

struct PhotosStepView: View {
    @Environment(AppModel.self) private var model
    @State private var photos: [EditablePhoto] = []

    var body: some View {
        StepScaffold {
            Headline(text: "Add a few photos.")
            Subhead(text: "At least two. Recent ones, where your face is clear.")
                .padding(.top, 12)
            PhotoGrid(photos: $photos)
                .padding(.top, 24)
            Text(photos.count >= 2 ? "\(photos.count) of 6 added. Hold a photo to move or remove it." : "Tap + to add \(photos.count == 1 ? "one more" : "two") to continue.")
                .font(TPFont.body(14))
                .foregroundStyle(Theme.ink2)
                .padding(.top, 14)
        } footer: {
            Button("Continue") { model.go(.prompts) }
                .buttonStyle(.primary)
                .disabled(photos.count < 2)
        }
        .onAppear { photos = model.profilePhotos.map { EditablePhoto(image: $0) } }
        .onChange(of: photos) { _, value in
            model.profilePhotos = value.map(\.image)
            // Paths from an earlier, failed sign-up no longer line up with these photos.
            model.profile.photoPaths = []
        }
    }
}

struct VerifyView: View {
    @Environment(AppModel.self) private var model
    @State private var state: Phase = .idle

    enum Phase { case idle, checking, done }

    var body: some View {
        StepScaffold {
            Headline(text: "Show you’re real.")
            Subhead(text: "Everyone here takes a quick selfie check. It’s how we keep out bots and fake profiles.")
                .padding(.top, 12)
            VStack(spacing: 0) {
                ZStack {
                    Ellipse()
                        .fill(Theme.surface)
                    Ellipse()
                        .strokeBorder(Theme.ink, style: StrokeStyle(lineWidth: 1.5, dash: state == .done ? [] : [5, 5]))
                    Image(systemName: "person")
                        .font(.system(size: 92, weight: .ultraLight))
                        .foregroundStyle(Theme.strong)
                }
                .frame(width: 216, height: 276)
                .overlay(alignment: .bottom) {
                    if state == .done {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                            Text("Verified").font(TPFont.body(14, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .frame(width: 120, height: 34)
                        .background(Capsule().fill(Theme.ink))
                        .offset(y: 17)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(status)
                    .font(TPFont.body(15))
                    .foregroundStyle(Color(hex: 0x3A3A38))
                    .frame(minHeight: 22)
                    .padding(.top, 34)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 30)
            Text("Your selfie is used only for this check, then deleted.")
                .font(TPFont.body(13))
                .foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
        } footer: {
            switch state {
            case .idle:
                // Camera capture and liveness checks come with the backend; this simulates the result.
                Button("Take a selfie") {
                    state = .checking
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        withAnimation(.spring(duration: 0.4)) { state = .done }
                        model.profile.verified = true
                    }
                }
                .buttonStyle(.primary)
            case .checking:
                Button("Checking…") {}
                    .buttonStyle(.primary)
                    .disabled(true)
            case .done:
                Button("Finish") { model.go(.done) }
                    .buttonStyle(.primary)
            }
        }
    }

    private var status: String {
        switch state {
        case .idle: return "Fit your face inside the oval."
        case .checking: return "Hold still, checking…"
        case .done: return ""
        }
    }
}

struct DoneView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let name = model.profile.firstName.trimmingCharacters(in: .whitespaces)
        let count = model.overlapCount
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            HStack(spacing: 10) {
                Circle().fill(Theme.accent).frame(width: 12, height: 12)
                MonoLabel(text: "Verified · ready", color: Theme.ink)
            }
            Headline(text: name.isEmpty ? "You’re in." : "You’re in, \(name).", size: 44)
                .padding(.top, 20)
            Subhead(text: "Your feed is ready. Like someone, and if they like you back, you’ll both see exactly where you crossed.", size: 17)
                .padding(.top, 14)
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    MonoLabel(text: "Your feed")
                    Text(count == 0 ? "Ready when people arrive" : "\(count) \(count == 1 ? "person" : "people"), waiting for you")
                        .font(TPFont.display(22))
                        .tracking(-0.5)
                        .foregroundStyle(Theme.ink)
                    Text("8 likes a day. New people appear as you add photos.")
                        .font(TPFont.body(14))
                        .foregroundStyle(Theme.ink2)
                }
            }
            .padding(.top, 30)
            Spacer()
            Button(model.working ? "Saving your places…" : "Open my feed") { Task { await model.completeSignup() } }
                .buttonStyle(.primary)
                .disabled(model.working)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, Theme.gutter)
    }
}
