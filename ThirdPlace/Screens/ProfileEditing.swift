import SwiftUI
import PhotosUI
import ThirdPlaceBackend

// MARK: - Photos

/// Six photo slots. Hold a photo to move it, make it the main one or remove it.
struct PhotoGrid: View {
    @Binding var photos: [EditablePhoto]
    @State private var picked: [PhotosPickerItem] = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                if index < photos.count {
                    tile(photos[index], index: index)
                } else {
                    addTile(isNext: index == photos.count)
                }
            }
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data), photos.count < 6 {
                        photos.append(EditablePhoto(image: image))
                    }
                }
                picked = []
            }
        }
    }

    private func tile(_ photo: EditablePhoto, index: Int) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 144)
            .overlay {
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .bottomLeading) {
                MonoLabel(text: index == 0 ? "Main" : "Photo \(index + 1)", color: Theme.ink, size: 10)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surface))
                    .padding(8)
            }
            .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 14))
            .draggable(photo.id.uuidString) {
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .dropDestination(for: String.self) { items, _ in
                guard let id = items.first.flatMap(UUID.init(uuidString:)),
                      let from = photos.firstIndex(where: { $0.id == id }), from != index else { return false }
                withAnimation(.smooth(duration: 0.25)) {
                    let moved = photos.remove(at: from)
                    photos.insert(moved, at: index)
                }
                return true
            }
            .contextMenu {
                if index > 0 {
                    Button("Make main photo", systemImage: "star") {
                        withAnimation(.smooth(duration: 0.25)) {
                            let moved = photos.remove(at: index)
                            photos.insert(moved, at: 0)
                        }
                    }
                }
                Button("Remove", systemImage: "trash", role: .destructive) {
                    withAnimation(.smooth(duration: 0.25)) { _ = photos.remove(at: index) }
                }
            }
            .accessibilityLabel(index == 0 ? "Main photo" : "Photo \(index + 1)")
    }

    private func addTile(isNext: Bool) -> some View {
        PhotosPicker(selection: $picked, maxSelectionCount: 6 - photos.count, matching: .images) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(isNext ? Theme.ink : Theme.strong, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                )
                .overlay(Image(systemName: "plus").font(.system(size: 20, weight: .light)).foregroundStyle(isNext ? Theme.ink : Theme.mute))
                .frame(height: 144)
        }
        .accessibilityLabel("Add photo")
    }
}

// MARK: - Prompts

/// Up to three prompt cards: answered ones open the editor, the next empty one adds a prompt.
struct PromptList: View {
    @Binding var prompts: [ProfilePrompt]
    @State private var editing: Target?

    private struct Target: Identifiable {
        let id = UUID()
        /// nil adds a new prompt.
        let index: Int?
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<LocalProfile.maxPrompts, id: \.self) { index in
                if index < prompts.count {
                    answered(prompts[index], index: index)
                } else if index == prompts.count {
                    add
                } else {
                    placeholder(index)
                }
            }
        }
        .sheet(item: $editing) { target in
            let existing = target.index.map { prompts[$0] }
            PromptEditor(existing: existing, taken: Set(prompts.map(\.question)).subtracting([existing?.question].compactMap { $0 })) { result in
                switch result {
                case .save(let prompt):
                    if let index = target.index { prompts[index] = prompt } else { prompts.append(prompt) }
                case .remove:
                    if let index = target.index { prompts.remove(at: index) }
                }
            }
        }
    }

    private func answered(_ prompt: ProfilePrompt, index: Int) -> some View {
        Button { editing = Target(index: index) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(prompt.question)
                        .font(TPFont.body(14, weight: .medium))
                        .foregroundStyle(Theme.ink2)
                    Spacer(minLength: 12)
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.ink2)
                }
                Text(prompt.answer)
                    .font(TPFont.display(20, weight: .medium))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.rule))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit this prompt")
    }

    private var add: some View {
        Button { editing = Target(index: nil) } label: {
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.paper))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a prompt").font(TPFont.body(16, weight: .medium)).foregroundStyle(Theme.ink)
                    Text("Pick a question, answer it in your own words.").font(TPFont.body(13)).foregroundStyle(Theme.ink2)
                }
                Spacer()
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.ink, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func placeholder(_ index: Int) -> some View {
        HStack {
            MonoLabel(text: "Prompt \(index + 1)", color: Theme.mute, size: 10.5)
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.strong, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        .accessibilityHidden(true)
    }
}

/// Pick a question, then write the answer.
struct PromptEditor: View {
    enum Result { case save(ProfilePrompt), remove }

    @Environment(\.dismiss) private var dismiss
    let existing: ProfilePrompt?
    let taken: Set<String>
    let onDone: (Result) -> Void

    @State private var question: String?
    @State private var answer: String
    @FocusState private var focused: Bool

    init(existing: ProfilePrompt?, taken: Set<String>, onDone: @escaping (Result) -> Void) {
        self.existing = existing
        self.taken = taken
        self.onDone = onDone
        _question = State(initialValue: existing?.question)
        _answer = State(initialValue: existing?.answer ?? "")
    }

    private var trimmed: String { answer.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Group {
                if let question {
                    answerView(question)
                } else {
                    questionList
                }
            }
            .background(Theme.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(TPFont.body(16))
                        .foregroundStyle(Theme.ink)
                }
                if let question {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            onDone(.save(ProfilePrompt(question: question, answer: trimmed)))
                            dismiss()
                        }
                        .font(TPFont.body(16, weight: .medium))
                        .foregroundStyle(trimmed.isEmpty ? Theme.mute : Theme.ink)
                        .disabled(trimmed.isEmpty)
                    }
                }
            }
        }
    }

    private var questionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Headline(text: "Pick a prompt.", size: 28)
                Subhead(text: "Answer it the way you’d say it out loud.", size: 15)
                    .padding(.top, 10)
                VStack(spacing: 0) {
                    let options = PromptCatalog.questions.filter { !taken.contains($0) }
                    ForEach(options, id: \.self) { option in
                        Button {
                            withAnimation(.smooth(duration: 0.25)) { question = option }
                        } label: {
                            HStack {
                                Text(option)
                                    .font(TPFont.body(16))
                                    .foregroundStyle(Theme.ink)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.mute)
                            }
                            .padding(.horizontal, 18)
                            .frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) {
                            if option != options.last { Hairline(color: Theme.ruleSoft) }
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.rule))
                .padding(.top, 20)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
    }

    private func answerView(_ question: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    MonoLabel(text: "Your prompt")
                    Spacer()
                    Button("Change") {
                        withAnimation(.smooth(duration: 0.25)) { self.question = nil }
                    }
                    .font(TPFont.body(14, weight: .medium))
                    .foregroundStyle(Theme.ink)
                }
                Text(question)
                    .font(TPFont.display(26))
                    .tracking(-0.7)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                TextField("Your answer", text: $answer, axis: .vertical)
                    .font(TPFont.body(18))
                    .lineLimit(4...8)
                    .focused($focused)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(focused ? Theme.ink : Theme.rule))
                    .padding(.top, 20)
                    .onChange(of: answer) { _, value in
                        if value.count > LocalProfile.maxAnswer { answer = String(value.prefix(LocalProfile.maxAnswer)) }
                    }
                HStack {
                    Text("Specific beats clever. Name the place, the dish, the time of day.")
                        .font(TPFont.body(13))
                        .foregroundStyle(Theme.ink2)
                    Spacer(minLength: 12)
                    MonoLabel(text: "\(LocalProfile.maxAnswer - answer.count)", color: answer.count > LocalProfile.maxAnswer - 20 ? Theme.accent : Theme.mute, size: 11)
                }
                .padding(.top, 10)

                if existing != nil {
                    Button("Remove this prompt", role: .destructive) {
                        onDone(.remove)
                        dismiss()
                    }
                    .font(TPFont.body(15))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 28)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { focused = true }
    }
}

// MARK: - Onboarding step

struct PromptsStepView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        StepScaffold {
            Headline(text: "Give them something to talk about.")
            Subhead(text: "Answer at least one prompt. People can like an answer, and it gives them an easy first message.")
                .padding(.top, 12)
            PromptList(prompts: $model.profile.prompts)
                .padding(.top, 24)
        } footer: {
            Button("Continue") { model.go(.verify) }
                .buttonStyle(.primary)
                .disabled(model.profile.prompts.isEmpty)
        }
    }
}

// MARK: - Edit profile

struct EditProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft = LocalProfile()
    @State private var photos: [EditablePhoto] = []
    @State private var originalPhotoIDs: [UUID] = []
    @State private var tab: Tab = .edit
    @State private var confirmDiscard = false
    @FocusState private var nameFocused: Bool

    enum Tab { case edit, preview }

    private var changed: Bool { draft != model.profile || photos.map(\.id) != originalPhotoIDs }
    private var valid: Bool { !draft.firstName.trimmingCharacters(in: .whitespaces).isEmpty && photos.count >= 2 }

    var body: some View {
        VStack(spacing: 0) {
            tabs
            if tab == .edit { form } else { preview }
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { if changed { confirmDiscard = true } else { dismiss() } }
                    .font(TPFont.body(16))
                    .foregroundStyle(Theme.ink)
            }
            ToolbarItem(placement: .principal) {
                Text("Your profile").font(TPFont.body(16, weight: .semibold)).foregroundStyle(Theme.ink)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(model.working ? "Saving…" : "Save") { save() }
                    .font(TPFont.body(16, weight: .medium))
                    .foregroundStyle(changed && valid ? Theme.ink : Theme.mute)
                    .disabled(!changed || !valid || model.working)
            }
        }
        .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .task {
            load()
            // On a new phone the server has the photos and prompts; pick them up if nothing was touched yet.
            let untouched = draft
            let untouchedPhotos = photos.map(\.id)
            await model.refreshMyProfile()
            if draft == untouched && photos.map(\.id) == untouchedPhotos { load() }
        }
    }

    private func load() {
        draft = model.profile
        let paths = model.profile.photoPaths
        photos = model.profilePhotos.enumerated().map { index, image in
            EditablePhoto(image: image, path: paths.count == model.profilePhotos.count ? paths[index] : nil)
        }
        originalPhotoIDs = photos.map(\.id)
    }

    private func save() {
        Task {
            if await model.saveProfile(draft, photos: photos) { dismiss() }
        }
    }

    private var tabs: some View {
        HStack(spacing: 24) {
            ForEach([(Tab.edit, "Edit"), (Tab.preview, "Preview")], id: \.1) { value, title in
                Button {
                    nameFocused = false
                    withAnimation(.smooth(duration: 0.2)) { tab = value }
                } label: {
                    VStack(spacing: 8) {
                        Text(title)
                            .font(TPFont.body(15, weight: .medium))
                            .foregroundStyle(tab == value ? Theme.ink : Theme.mute)
                        Rectangle()
                            .fill(tab == value ? Theme.ink : Color.clear)
                            .frame(height: 2)
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == value ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 6)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MonoLabel(text: "Photos")
                PhotoGrid(photos: $photos)
                    .padding(.top, 10)
                Text(photos.count < 2 ? "Add at least two photos." : "Hold a photo to move it, make it your main one or remove it.")
                    .font(TPFont.body(13))
                    .foregroundStyle(photos.count < 2 ? Theme.accent : Theme.ink2)
                    .padding(.top, 10)

                MonoLabel(text: "Prompts").padding(.top, 30)
                PromptList(prompts: $draft.prompts)
                    .padding(.top, 10)

                MonoLabel(text: "About you").padding(.top, 30)
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        FieldLabel(text: "First name")
                        TextField("Your first name", text: $draft.firstName)
                            .font(TPFont.body(17))
                            .textContentType(.givenName)
                            .focused($nameFocused)
                            .padding(.horizontal, 16)
                            .frame(height: 54)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(nameFocused ? Theme.ink : Theme.rule))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        FieldLabel(text: "Age")
                        Text("\(draft.age)")
                            .font(TPFont.body(17))
                            .foregroundStyle(Theme.ink)
                        Text("From your birthday, which can’t be changed after sign-up.")
                            .font(TPFont.body(13))
                            .foregroundStyle(Theme.ink2)
                    }
                    ChipGroup(title: "I’m a", options: ["Woman", "Man", "Non-binary"], selection: $draft.gender)
                    ChipGroup(title: "Show me", options: ["Women", "Men", "Everyone"], selection: $draft.showMe)
                    ChipGroup(title: "Here for", options: ["Dating", "New friends", "Both"], selection: $draft.intent)
                }
                .padding(.top, 14)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var preview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("This is how you show up for someone who goes where you go.")
                    .font(TPFont.body(14))
                    .foregroundStyle(Theme.ink2)
                    .padding(.bottom, 16)
                ProfileCard(person: previewPerson, liked: nil, preview: true) { _ in }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }

    private var previewPerson: FeedPerson {
        let top = model.places.filter(\.selected).max { $0.visitDays < $1.visitDays }
        let crossing: FeedPerson.Crossing
        if let top {
            let weeks = Set(top.visitWeeks)
            crossing = CrossingText.place(tier: .regulars, noun: CrossingText.noun(for: top.category), rhythm: top.rhythm,
                                          area: top.area, myWeeks: weeks, theirWeeks: weeks)
        } else {
            crossing = .init(tier: .samePlace, title: "Where you crossed goes here.",
                             detail: "Their places and yours, kept vague until you match.", myWeeks: [], theirWeeks: [], stamp: "Your places")
        }
        return FeedPerson(
            id: -1,
            name: draft.firstName.trimmingCharacters(in: .whitespaces).isEmpty ? "You" : draft.firstName,
            age: draft.age,
            line: top?.area ?? "Nearby",
            tones: (0xDDD6CC, 0xCDD4D8),
            first: crossing,
            second: nil,
            prompts: draft.prompts,
            localPhotos: photos.map(\.image)
        )
    }
}
