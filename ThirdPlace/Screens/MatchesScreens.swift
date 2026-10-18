import SwiftUI
import ThirdPlaceBackend

/// Everyone you matched with, newest conversation first.
struct MatchesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if model.matches.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Headline(text: "No matches yet.")
                            Subhead(text: "Like someone in your feed. If they like you back, you’ll both see exactly where you crossed, and you can talk here.")
                        }
                        .padding(.top, 24)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(model.matches) { match in
                                NavigationLink(value: match) {
                                    MatchRowView(match: match)
                                }
                                .buttonStyle(.plain)
                                .overlay(alignment: .bottom) {
                                    if match.id != model.matches.last?.id { Hairline(color: Theme.ruleSoft) }
                                }
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.rule))
                        .padding(.top, 16)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 24)
            }
            .refreshable { await model.loadMatches() }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Matches")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(TPFont.body(16, weight: .medium))
                        .foregroundStyle(Theme.ink)
                }
            }
            .navigationDestination(for: MatchRow.self) { match in
                if let backend = model.backend {
                    ChatView(chat: ChatModel(match: match, backend: backend))
                }
            }
        }
        .task { await model.loadMatches() }
    }
}

private struct MatchRowView: View {
    let match: MatchRow

    var body: some View {
        HStack(spacing: 14) {
            PersonAvatar(path: match.photoPaths.first, size: 52, seed: match.personID)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(match.firstName)
                        .font(TPFont.body(16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if let when = ServerDate.parse(match.lastMessageAt ?? match.matchedAt) {
                        Text(when, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                            .font(TPFont.mono(10.5))
                            .foregroundStyle(Theme.ink3)
                    }
                }
                if let place = match.sharedPlaces.first {
                    MonoLabel(text: place.myVenue ?? "\(place.category) · \(place.neighbourhood)", size: 10)
                        .lineLimit(1)
                }
                HStack {
                    Text(preview)
                        .font(TPFont.body(14, weight: match.unread > 0 ? .medium : .regular))
                        .foregroundStyle(match.unread > 0 ? Theme.ink : Theme.ink2)
                        .lineLimit(1)
                    Spacer()
                    if match.unread > 0 {
                        Text("\(match.unread)")
                            .font(TPFont.mono(11, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Capsule().fill(Theme.accent))
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private var preview: String {
        guard let text = match.lastMessage else { return "New match. Say hello." }
        return (match.lastMessageMine == true ? "You: " : "") + text
    }
}

/// A profile photo from storage, or a soft placeholder until one loads.
struct PersonAvatar: View {
    @Environment(AppModel.self) private var model
    let path: String?
    var size: CGFloat = 40
    var seed: UUID
    @State private var url: URL?

    var body: some View {
        ZStack {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { placeholder }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: path) {
            guard let path else { return }
            url = await model.photoURL(path)
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        let tones: [UInt32] = [0xDDD6CC, 0xCDD4D8, 0xD3DACF, 0xDCD1CC, 0xD7CFDA]
        return Circle()
            .fill(Color(hex: tones[abs(seed.hashValue) % tones.count]))
            .overlay(Image(systemName: "person").font(.system(size: size * 0.42, weight: .light)).foregroundStyle(Theme.ink.opacity(0.25)))
    }
}

// MARK: - Chat

struct ChatView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var chat: ChatModel
    @State private var confirm: Confirm?
    @State private var reporting = false
    @FocusState private var typing: Bool

    enum Confirm: Identifiable {
        case unmatch, block
        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        header
                        if chat.loading {
                            ProgressView().padding(.top, 40)
                        } else if chat.messages.isEmpty {
                            openers
                        }
                        LazyVStack(spacing: 6) {
                            ForEach(chat.messages) { message in
                                Bubble(message: message, mine: message.sender == chat.me)
                                    .id(message.id)
                            }
                        }
                        .padding(.top, 12)
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: chat.messages.count) { _, _ in
                    if let last = chat.messages.last {
                        withAnimation(.smooth(duration: 0.25)) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            composer
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle(chat.match.firstName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Unmatch") { confirm = .unmatch }
                    Button("Block", role: .destructive) { confirm = .block }
                    Button("Report", role: .destructive) { reporting = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Options")
            }
        }
        .confirmationDialog(confirm == .block ? "Block \(chat.match.firstName)?" : "Unmatch \(chat.match.firstName)?",
                            isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible) {
            Button(confirm == .block ? "Block" : "Unmatch", role: .destructive) {
                let action = confirm
                Task {
                    if action == .block { await model.block(chat.match) } else { await model.unmatch(chat.match) }
                    dismiss()
                }
            }
        } message: {
            Text(confirm == .block
                 ? "You won’t see each other again, anywhere in Third Place. They aren’t told."
                 : "Your conversation is deleted for both of you.")
        }
        .confirmationDialog("What’s wrong?", isPresented: $reporting, titleVisibility: .visible) {
            ForEach(ReportReason.allCases, id: \.self) { reason in
                Button(reason.label, role: .destructive) {
                    Task {
                        await model.report(chat.match, reason: reason)
                        dismiss()
                    }
                }
            }
        } message: {
            Text("Reports are private. We’ll also block them for you.")
        }
        .task { await chat.start() }
        .onDisappear {
            chat.stop()
            Task { await model.loadMatches() }
        }
        .alert("Something went wrong", isPresented: Binding(get: { chat.error != nil }, set: { if !$0 { chat.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(chat.error ?? "")
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            PersonAvatar(path: chat.match.photoPaths.first, size: 72, seed: chat.match.personID)
            if let venue = chat.sharedVenue {
                HStack(spacing: 8) {
                    Circle().fill(Theme.accent).frame(width: 7, height: 7)
                    MonoLabel(text: "You both go to \(venue)", color: Theme.ink, size: 10.5)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .overlay(Capsule().strokeBorder(Theme.rule))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private var openers: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(text: "Start with the place you share")
            ForEach(chat.openers, id: \.self) { line in
                Button {
                    Task { await chat.send(line) }
                } label: {
                    Text(line)
                        .font(TPFont.body(15))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.rule))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 28)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message", text: $chat.draft, axis: .vertical)
                .font(TPFont.body(16))
                .lineLimit(1...5)
                .focused($typing)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 22).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(typing ? Theme.ink : Theme.rule))
            Button {
                Task { await chat.send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(canSend ? Theme.ink : Theme.strong))
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, Theme.gutter - 8)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Theme.paper)
        .overlay(alignment: .top) { Hairline() }
    }

    private var canSend: Bool {
        !chat.sending && !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct Bubble: View {
    let message: ChatMessage
    let mine: Bool

    var body: some View {
        HStack {
            if mine { Spacer(minLength: 56) }
            Text(message.body)
                .font(TPFont.body(16))
                .foregroundStyle(mine ? Color.white : Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(mine ? Theme.ink : Theme.surface)
                )
                .overlay {
                    if !mine { RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.rule) }
                }
                .textSelection(.enabled)
            if !mine { Spacer(minLength: 56) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(mine ? "You: \(message.body)" : message.body)
    }
}
