import SwiftUI
import ThirdPlaceBackend

/// Everyone you crossed paths with, one profile at a time. Like a specific part of a profile,
/// Hinge-style; places stay vague until you both like each other.
struct FeedView: View {
    @Environment(AppModel.self) private var model
    @State private var index = 0
    @State private var liked: String?
    @State private var toast: String?
    @State private var confirmReset = false
    @State private var advanceTask: Task<Void, Never>?
    @State private var loading = false
    @State private var showMatches = false
    @State private var showYou = false

    var body: some View {
        let people = model.people
        VStack(spacing: 0) {
            header(count: people.count)
            if people.isEmpty {
                if loading || (model.backend != nil && model.remotePeople == nil) {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyState
                }
            } else {
                let person = people[index % people.count]
                ZStack(alignment: .bottomLeading) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            ProfileCard(person: person, liked: liked) { part in like(part, person: person) }
                                .id(person.id)
                                .padding(.horizontal, Theme.gutter)
                                .padding(.top, 14)
                                .padding(.bottom, 120)
                        }
                        .scrollIndicators(.hidden)
                        .refreshable { await model.loadFeed() }
                        .onChange(of: person) { _, newPerson in
                            proxy.scrollTo(newPerson.id, anchor: .top)
                        }
                    }
                    controls(for: person)
                }
                .transition(.opacity)
            }
        }
        .task {
            guard model.backend != nil else { return }
            loading = true
            await model.loadFeed()
            loading = false
            await model.loadMatches()
        }
        .fullScreenCover(isPresented: $showMatches) {
            MatchesView()
        }
        .sheet(isPresented: $showYou) {
            YouView()
        }
        .confirmationDialog("Start over?", isPresented: $confirmReset, titleVisibility: .visible) {
            if model.backend != nil {
                Button("Delete my account and start over", role: .destructive) {
                    Task { await model.deleteAccount() }
                }
            } else {
                Button("Restart onboarding", role: .destructive) { model.reset() }
            }
        } message: {
            Text(model.backend != nil
                 ? "This deletes your account, places and photos from Third Place."
                 : "This clears your places and profile on this phone.")
        }
    }

    private func header(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 4) {
                Text("Crossed paths")
                    .font(TPFont.display(24))
                    .tracking(-0.8)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .onLongPressGesture { confirmReset = true }
                Spacer(minLength: 8)
                if model.backend != nil {
                    headerButton(icon: "bubble.left", label: model.unreadTotal > 0 ? "Matches, \(model.unreadTotal) unread" : "Matches",
                                 dot: model.unreadTotal > 0 ? Theme.accent : (model.matches.isEmpty ? nil : Theme.ink)) {
                        showMatches = true
                    }
                    headerButton(icon: "person", label: "You", dot: model.isAnonymousAccount ? Theme.accent : nil) {
                        showYou = true
                    }
                }
            }
            HStack(spacing: 6) {
                if count > 0 {
                    MonoLabel(text: model.backend == nil ? "\(index % count + 1) of \(count)" : "\(count) waiting")
                    MonoLabel(text: "·")
                }
                Image(systemName: "heart.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.accent)
                MonoLabel(text: model.likesLeft == 1 ? "1 like left today" : "\(model.likesLeft) likes left today", color: Theme.ink)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private func headerButton(icon: String, label: String, dot: Color?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.surface))
                .overlay(Circle().strokeBorder(Theme.rule))
                .overlay(alignment: .topTrailing) {
                    if let dot {
                        Circle()
                            .fill(dot)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(Theme.paper, lineWidth: 1.5))
                            .offset(x: 1, y: -1)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    private func controls(for person: FeedPerson) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            Button { skip(person) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(Theme.surface))
                    .overlay(Circle().strokeBorder(Theme.rule))
                    .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
            }
            .accessibilityLabel("Skip")
            if let toast {
                Text(toast)
                    .font(TPFont.body(13.5))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.ink))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Headline(text: "No one yet.")
                Subhead(text: model.backend == nil
                        ? "New people appear as you add photos at your places. Check back after your next coffee."
                        : "You’re early here. New people show up as they join around your places. Pull to refresh.")
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable { await model.loadFeed() }
    }

    private func like(_ part: String, person: FeedPerson) {
        guard liked == nil else { return }
        withAnimation(.spring(duration: 0.3)) { liked = part }
        Task {
            let outcome = await model.like(person, item: part)
            var pause = 1.9
            withAnimation(.smooth) {
                switch outcome {
                case .sent:
                    toast = "Like sent. If \(person.name) likes you back, you’ll both see where you crossed."
                case .matched(let venue):
                    pause = 3.2
                    toast = venue.map { "It’s a match. You both go to \($0). Say hi in Matches." } ?? "It’s a match with \(person.name)."
                    Task { await model.loadMatches() }
                case .outOfLikes:
                    liked = nil
                    toast = "Out of likes until tomorrow. Third Place+ gives you unlimited likes."
                case .failed(let message):
                    liked = nil
                    toast = "Couldn’t send that like. \(message)"
                }
            }
            guard liked != nil else { return }
            advanceTask?.cancel()
            advanceTask = Task {
                try? await Task.sleep(for: .seconds(pause))
                guard !Task.isCancelled else { return }
                next(after: person)
            }
        }
    }

    private func skip(_ person: FeedPerson) {
        advanceTask?.cancel()
        Task { await model.pass(person) }
        next(after: person)
    }

    private func next(after person: FeedPerson) {
        withAnimation(.smooth(duration: 0.3)) {
            if model.backend != nil {
                model.removeFromFeed(person)
                index = 0
            } else {
                index += 1
            }
            liked = nil
            toast = nil
        }
    }
}

/// One profile, Hinge-style: photos, prompts and where you crossed, each of which can be liked.
struct ProfileCard: View {
    let person: FeedPerson
    let liked: String?
    /// Your own profile as others see it: nothing to like.
    var preview = false
    let onLike: (String) -> Void

    private enum Section: Hashable {
        case photo(Int), prompt(Int), first, second
    }

    /// Main photo and the best crossing first, then prompts and photos taking turns.
    private var sections: [Section] {
        var result: [Section] = [.photo(0), .first]
        var photo = 1
        var prompt = 0
        var placedSecond = person.second == nil
        while photo < person.photoCount || prompt < person.prompts.count {
            if prompt < person.prompts.count {
                result.append(.prompt(prompt))
                prompt += 1
            }
            if photo < person.photoCount {
                result.append(.photo(photo))
                photo += 1
            }
            if !placedSecond {
                result.append(.second)
                placedSecond = true
            }
        }
        if !placedSecond { result.append(.second) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(person.name)
                        .font(TPFont.display(36))
                        .tracking(-1.4)
                        .foregroundStyle(Theme.ink)
                    Text("\(person.age)")
                        .font(TPFont.display(24, weight: .regular))
                        .foregroundStyle(Theme.ink2)
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.ink)
                        .accessibilityLabel("Verified")
                }
                Text(person.line)
                    .font(TPFont.body(15))
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.bottom, 6)

            ForEach(sections, id: \.self) { section in
                switch section {
                case .photo(let index):
                    photo(index)
                case .prompt(let index):
                    prompt(person.prompts[index], index: index)
                case .first:
                    CrossingCard(crossing: person.first, theirName: person.name) {
                        like("first", label: "Like where you crossed")
                    }
                case .second:
                    if let second = person.second {
                        CrossingCard(crossing: second, theirName: person.name) {
                            like("second", label: "Like this overlap")
                        }
                    }
                }
            }
        }
    }

    private func photo(_ index: Int) -> some View {
        let tones = [person.tones.0, person.tones.1]
        return PhotoBlock(
            tone: tones[index % 2],
            label: "Photo \(index + 1)",
            path: index < person.photoPaths.count ? person.photoPaths[index] : nil,
            image: index < person.localPhotos.count ? person.localPhotos[index] : nil
        ) {
            like("photo\(index + 1)", large: true, label: index == 0 ? "Like \(person.name)’s main photo" : "Like \(person.name)’s photo \(index + 1)")
        }
    }

    private func prompt(_ prompt: ProfilePrompt, index: Int) -> some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(prompt.question)
                    .font(TPFont.body(14, weight: .medium))
                    .foregroundStyle(Theme.ink2)
                Text(prompt.answer)
                    .font(TPFont.display(24, weight: .medium))
                    .tracking(-0.6)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, preview ? 0 : 56)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            like("prompt\(index + 1)", label: "Like \(person.name)’s answer").padding(14)
        }
    }

    @ViewBuilder
    private func like(_ part: String, large: Bool = false, label: String) -> some View {
        if !preview {
            LikeButton(isLiked: liked == part, large: large, label: label) { onLike(part) }
        }
    }
}

private struct PhotoBlock<Accessory: View>: View {
    @Environment(AppModel.self) private var model
    let tone: UInt32
    let label: String
    var path: String? = nil
    var image: UIImage? = nil
    @ViewBuilder var accessory: Accessory
    @State private var url: URL?

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.radius)
            .fill(Color(hex: tone))
            .frame(height: 420)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            ProgressView()
                        }
                    }
                } else {
                    Image(systemName: "person")
                        .font(.system(size: 110, weight: .ultraLight))
                        .foregroundStyle(Theme.ink.opacity(0.16))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(alignment: .topLeading) {
                if url == nil && image == nil {
                    MonoLabel(text: label, color: Color(hex: 0x3A3A38), size: 10)
                        .padding(14)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                accessory.padding(14)
            }
            .task(id: path) {
                guard let path else { url = nil; return }
                url = await model.photoURL(path)
            }
    }
}

private struct CrossingCard<Accessory: View>: View {
    let crossing: FeedPerson.Crossing
    let theirName: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 0) {
                MonoLabel(text: "Where you’ve crossed · \(crossing.tier.rawValue)", size: 10.5)
                    .padding(.trailing, 56)
                Text(crossing.title)
                    .font(TPFont.display(24))
                    .tracking(-0.7)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .padding(.trailing, 48)
                Text(crossing.detail)
                    .font(TPFont.body(14))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                if let stamp = crossing.stamp {
                    HStack(spacing: 8) {
                        Circle().fill(Theme.accent).frame(width: 7, height: 7)
                        MonoLabel(text: stamp, color: Theme.ink, size: 10.5)
                    }
                    .padding(.top, 14)
                } else {
                    VStack(spacing: 6) {
                        WeekStrip(label: "You", weeks: crossing.myWeeks, color: Theme.ink)
                        WeekStrip(label: theirName, weeks: crossing.theirWeeks, color: Theme.accent)
                    }
                    .padding(.top, 18)
                    HStack {
                        MonoLabel(text: "Last 12 months", size: 10)
                        Spacer()
                        MonoLabel(text: "\(crossing.weeksInCommon) weeks in common", color: Theme.ink, size: 10)
                    }
                    .padding(.top, 12)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            accessory.padding(14)
        }
    }
}

/// 52 thin bars, one per week; tall where this person was there.
private struct WeekStrip: View {
    let label: String
    let weeks: Set<Int>
    let color: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            MonoLabel(text: label, size: 10)
                .lineLimit(1)
                .frame(width: 48, alignment: .leading)
            GeometryReader { geo in
                let step = geo.size.width / 52
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<52, id: \.self) { week in
                        let on = weeks.contains(week)
                        Rectangle()
                            .fill(on ? color : Theme.rule)
                            .frame(width: 2, height: on ? 14 : 3)
                            .frame(width: step, alignment: .leading)
                    }
                }
                .frame(height: 14, alignment: .bottom)
            }
            .frame(height: 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): there \(weeks.count) of the last 52 weeks")
    }
}

private struct LikeButton: View {
    let isLiked: Bool
    var large = false
    let label: String
    let action: () -> Void

    var body: some View {
        let size: CGFloat = large ? 52 : 48
        Button(action: action) {
            Image(systemName: isLiked ? "heart.fill" : "heart")
                .font(.system(size: large ? 21 : 19, weight: .regular))
                .foregroundStyle(isLiked ? Color.white : Theme.ink)
                .frame(width: size, height: size)
                .background(Circle().fill(isLiked ? Theme.accent : Theme.surface))
                .overlay(Circle().strokeBorder(large ? Color.clear : Theme.rule))
                .shadow(color: .black.opacity(large ? 0.12 : 0), radius: 9, y: 6)
                .scaleEffect(isLiked ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .sensoryFeedback(.impact(weight: .light), trigger: isLiked)
    }
}
