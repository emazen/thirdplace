import SwiftUI
import MapKit

struct ScanView: View {
    @Environment(AppModel.self) private var model
    private let minimumDuration: Double = 3.2

    var body: some View {
        TimelineView(.animation(paused: model.scan.finished && elapsed >= minimumDuration)) { _ in
            let p = progress
            let late = max(0, (p - 0.35) / 0.65)
            let done = model.scan.finished && p >= 1

            StepScaffold {
                Headline(text: done ? "Found your places." : "Reading your photos…")
                Subhead(text: done
                        ? "\(model.scan.placeCount) places you keep coming back to, and moments from \(model.scan.areaCount) \(model.scan.areaCount == 1 ? "city" : "cities")."
                        : "Only where and when. Nothing else leaves the photo.")
                    .frame(minHeight: 48, alignment: .top)
                    .padding(.top, 12)

                ScanMap(dots: model.scan.dots, rings: model.scan.rings, progress: p, showRings: done)
                    .frame(height: 250)
                    .padding(.top, 16)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Theme.rule)
                        Rectangle().fill(Theme.ink).frame(width: geo.size.width * p)
                    }
                }
                .frame(height: 2)
                .padding(.top, 14)

                ScanCounters(
                    photos: Int(Double(model.scan.photosRead) * p),
                    located: Int(Double(model.scan.withLocation) * p),
                    places: Int(Double(model.scan.placeCount) * late),
                    cities: Int(Double(model.scan.areaCount) * late)
                )
                .padding(.top, 14)
            } footer: {
                if done {
                    Button(model.scan.placeCount == 0 ? "Add places by hand" : "See my places") { model.go(.places) }
                        .buttonStyle(.primary)
                } else {
                    Text("This only takes a few seconds.")
                        .font(TPFont.body(15))
                        .foregroundStyle(Theme.ink2)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
            }
        }
        .task { await model.runScan() }
    }

    private var elapsed: Double {
        model.scan.startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
    }

    /// Time-driven so the scan always reads as a scan, held at 90% until the work is done.
    private var progress: Double {
        let t = min(1, elapsed / minimumDuration)
        return model.scan.finished ? t : min(t, 0.9)
    }
}

private struct ScanMap: View {
    let dots: [MapMark]
    let rings: [MapMark]
    let progress: Double
    let showRings: Bool

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 28
            let w = size.width - inset * 2
            let h = size.height - inset * 2
            func point(_ m: MapMark) -> CGPoint {
                CGPoint(x: inset + w * m.x, y: inset + h * m.y)
            }

            var grid = Path()
            for y in stride(from: 0.2, to: 1, by: 0.24) { grid.move(to: CGPoint(x: 0, y: size.height * y)); grid.addLine(to: CGPoint(x: size.width, y: size.height * y)) }
            for x in stride(from: 0.18, to: 1, by: 0.24) { grid.move(to: CGPoint(x: size.width * x, y: 0)); grid.addLine(to: CGPoint(x: size.width * x, y: size.height)) }
            context.stroke(grid, with: .color(Theme.ruleSoft), lineWidth: 1)

            let visible = Int(Double(dots.count) * progress)
            for mark in dots.prefix(visible) {
                let c = point(mark)
                context.fill(Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)), with: .color(Theme.ink.opacity(0.85)))
            }

            if showRings {
                for mark in rings {
                    let c = point(mark)
                    context.stroke(Path(ellipseIn: CGRect(x: c.x - 16, y: c.y - 16, width: 32, height: 32)), with: .color(Theme.accent), lineWidth: 1)
                    if let label = mark.label {
                        let text = Text(String(label.uppercased().prefix(24))).font(TPFont.mono(10)).foregroundColor(Theme.ink)
                        let flip = c.x > size.width * 0.55
                        context.draw(text, at: CGPoint(x: flip ? c.x - 22 : c.x + 22, y: c.y), anchor: flip ? .trailing : .leading)
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.rule))
        .overlay(alignment: .bottomLeading) {
            MonoLabel(text: "On your phone · nothing uploaded", color: Theme.ink, size: 10)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.surface))
                .overlay(Capsule().strokeBorder(Theme.rule))
                .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .accessibilityLabel("Map of where your photos were taken")
    }
}

private struct ScanCounters: View {
    let photos: Int
    let located: Int
    let places: Int
    let cities: Int

    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                cell(photos, "photos read")
                Rectangle().fill(Theme.ruleSoft).frame(width: 1)
                cell(located, "with a location")
            }
            GridRow {
                Hairline(color: Theme.ruleSoft).gridCellColumns(3)
            }
            GridRow {
                cell(places, "places you return to")
                Rectangle().fill(Theme.ruleSoft).frame(width: 1)
                cell(cities, "cities")
            }
        }
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.rule))
    }

    private func cell(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.formatted())
                .font(TPFont.display(26))
                .tracking(-0.8)
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            Text(label)
                .font(TPFont.body(13))
                .foregroundStyle(Theme.ink2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Places

struct PlacesView: View {
    @Environment(AppModel.self) private var model
    @State private var fixing: MyPlace?

    var body: some View {
        let manual = model.access == .denied || (model.scan.finished && model.places.isEmpty && model.access != .unknown)
        StepScaffold {
            Headline(text: manual ? "Add your places." : "These look like your places.")
            Subhead(text: manual
                    ? "Pick the spots you keep going back to. You can change them any time."
                    : "Keep the ones where you’d like to meet people. Untick anything you’d rather keep to yourself.")
                .padding(.top, 12)

            if model.access == .limited {
                Text("You shared some of your photos, so we found fewer places. Share more any time in Settings › Photos.")
                    .font(TPFont.body(14))
                    .foregroundStyle(Color(hex: 0x3A3A38))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.wash))
                    .padding(.top, 16)
            }

            if manual {
                PlaceSearch()
                    .padding(.top, 20)
            }

            if !model.places.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(model.places.enumerated()), id: \.element.id) { index, place in
                        PlaceRow(place: place, isLast: index == model.places.count - 1, toggle: {
                            withAnimation(.easeOut(duration: 0.15)) { model.togglePlace(place.id) }
                        }, fix: {
                            fixing = place
                        })
                    }
                }
                .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.rule))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                .padding(.top, 18)
            }

            if !model.hidden.isEmpty {
                MonoLabel(text: "Kept private, never used")
                    .padding(.top, 26)
                VStack(spacing: 0) {
                    Hairline()
                    ForEach(model.hidden) { place in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.title).font(TPFont.body(15, weight: .medium)).foregroundStyle(Theme.ink)
                                Text(place.detail).font(TPFont.body(14)).foregroundStyle(Theme.ink2)
                            }
                            Spacer()
                            Image(systemName: "lock")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.ink2)
                                .accessibilityLabel("Hidden")
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 2)
                        .overlay(alignment: .bottom) { Hairline() }
                    }
                }
                .padding(.top, 10)
            }
        } footer: {
            let count = model.selectedPlaceCount
            Button(count == 0 ? "Skip for now" : "Keep \(count) \(count == 1 ? "place" : "places")") {
                let hasMoments = !model.moments.isEmpty && model.access != .denied
                model.go(hasMoments ? .moments : .reveal)
            }
            .buttonStyle(.primary)
            .sheet(item: $fixing) { place in
                PlaceFixSheet(place: place)
                    .presentationDetents([.large])
            }
        }
    }
}

private struct PlaceRow: View {
    let place: MyPlace
    let isLast: Bool
    let toggle: () -> Void
    let fix: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggle) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(place.name)
                            .font(TPFont.body(16, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(place.selected ? Theme.ink : Theme.ink2)
                            .lineLimit(2)
                        Text(place.meta)
                            .font(TPFont.body(14))
                            .foregroundStyle(Theme.ink2)
                        MonoLabel(text: place.detail, size: 10.5)
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !place.monthly.isEmpty {
                        VisitBars(values: place.monthly, isOn: place.selected)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(place.selected ? .isSelected : [])

            Button(action: fix) {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ink2)
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fix the name of \(place.name)")

            Button(action: toggle) {
                CheckCircle(isOn: place.selected)
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(place.selected ? "Keep \(place.name)" : "Don’t keep \(place.name)")
        }
        .padding(.vertical, 11)
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .overlay(alignment: .bottom) {
            if !isLast { Hairline(color: Theme.ruleSoft) }
        }
    }
}

/// "That's not where I go": pick the right venue nearby, call it just the area, or name it.
private struct PlaceFixSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let place: MyPlace
    @State private var venues: [MKMapItem] = []
    @State private var loading = true
    @State private var custom = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Headline(text: "What’s this place?", size: 28)
                    Subhead(text: "Pick where you actually go. Until you match with someone, they only see “\(place.category == "Area" ? "an area" : place.category.lowercased()) in \(place.area)”.", size: 15)
                        .padding(.top, 10)

                    MonoLabel(text: "Where you go").padding(.top, 24)
                    VStack(spacing: 0) {
                        choice(title: "Just the area",
                               detail: "Around \(place.street ?? place.area) · not one venue",
                               current: place.category == "Area", last: venues.isEmpty && !loading) {
                            model.renamePlace(place.id, name: "Around \(place.street ?? place.area)", category: "Area")
                            dismiss()
                        }
                        if loading {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                        }
                        ForEach(venues, id: \.self) { item in
                            choice(title: item.name ?? "Place",
                                   detail: "\(PlaceNamer.category(for: item.pointOfInterestCategory)) · \(PlaceNamer.distanceLabel(item, from: place.coordinate))",
                                   current: item.name == place.name, last: item == venues.last) {
                                model.renamePlace(place.id, name: item.name ?? "Place",
                                                  category: PlaceNamer.category(for: item.pointOfInterestCategory))
                                dismiss()
                            }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.rule))
                    .padding(.top, 10)

                    MonoLabel(text: "Or name it yourself").padding(.top, 24)
                    HStack(spacing: 10) {
                        TextField("My running route, Grandma’s, …", text: $custom)
                            .font(TPFont.body(16))
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.rule))
                        Button("Save") {
                            model.renamePlace(place.id, name: custom.trimmingCharacters(in: .whitespaces), category: "Place")
                            dismiss()
                        }
                        .font(TPFont.body(16, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .background(Theme.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(TPFont.body(16))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .task {
            venues = await PlaceNamer.nearbyVenues(place.coordinate)
            loading = false
        }
    }

    private func choice(title: String, detail: String, current: Bool, last: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(TPFont.body(15, weight: .medium)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(detail).font(TPFont.body(13)).foregroundStyle(Theme.ink2).lineLimit(1)
                }
                Spacer()
                if current {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !last { Hairline(color: Theme.ruleSoft) }
        }
    }
}

private struct PlaceSearch: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.ink2)
                TextField("Search cafés, gyms, parks…", text: $query)
                    .font(TPFont.body(16))
                    .submitLabel(.search)
                    .onSubmit(runSearch)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.rule))

            if searching {
                ProgressView().padding(.top, 16).frame(maxWidth: .infinity)
            }

            ForEach(results, id: \.self) { item in
                Button {
                    model.addManualPlace(item)
                    results.removeAll { $0 == item }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "Place").font(TPFont.body(15, weight: .medium)).foregroundStyle(Theme.ink)
                            Text(item.placemark.title ?? "").font(TPFont.body(13)).foregroundStyle(Theme.ink2).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "plus").foregroundStyle(Theme.ink)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) { Hairline() }
            }
        }
    }

    private func runSearch() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        searching = true
        Task {
            results = Array(await PlaceNamer.search(text).prefix(6))
            searching = false
        }
    }
}

// MARK: - Moments

struct MomentsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        StepScaffold {
            Headline(text: "And a few big moments.")
            Subhead(text: "Gigs, festivals, trips. Days you shared with a crowd, and maybe with someone worth meeting.")
                .padding(.top, 12)
            VStack(spacing: 0) {
                ForEach($model.moments) { $moment in
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(moment.monthLabel)
                            Text(moment.yearLabel)
                        }
                        .font(TPFont.mono(11))
                        .foregroundStyle(Theme.ink3)
                        .frame(width: 40, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(moment.title)
                                .font(TPFont.body(16, weight: .semibold))
                                .tracking(-0.2)
                                .foregroundStyle(moment.selected ? Theme.ink : Theme.ink2)
                            Text(moment.meta)
                                .font(TPFont.body(14))
                                .foregroundStyle(Theme.ink2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Toggle(moment.title, isOn: $moment.selected)
                            .labelsHidden()
                            .tint(Theme.ink)
                    }
                    .padding(.vertical, 16)
                    .padding(.leading, 18)
                    .padding(.trailing, 16)
                    .overlay(alignment: .bottom) {
                        if moment.id != model.moments.last?.id { Hairline(color: Theme.ruleSoft) }
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.rule))
            .padding(.top, 22)
            Text("For moments, a match only sees the day, never your exact time.")
                .font(TPFont.body(14))
                .foregroundStyle(Theme.ink2)
                .padding(.top, 16)
                .padding(.horizontal, 2)
        } footer: {
            Button("Continue") { model.go(.reveal) }
                .buttonStyle(.primary)
        }
    }
}

// MARK: - Reveal

struct RevealView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.backend != nil {
            LiveRevealView()
        } else {
            DemoRevealView()
        }
    }
}

/// Real counts from the server: how many people share each kept place. Nothing is uploaded yet.
private struct LiveRevealView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let total = model.preview?.total ?? 0
        let rows = model.places.filter(\.selected).compactMap { place -> (MyPlace, Int)? in
            guard let n = model.preview?.places[place.id], n > 0 else { return nil }
            return (place, n)
        }
        StepScaffold {
            if model.preview == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else if total == 0 {
                Headline(text: "You’re early here.")
                    .padding(.top, 12)
                Subhead(text: "No one else has these places yet. Join now and you’ll see people as they arrive around your spots.")
                    .padding(.top, 12)
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(total)")
                        .font(TPFont.display(112))
                        .tracking(-6)
                        .foregroundStyle(Theme.ink)
                    Circle().fill(Theme.accent).frame(width: 14, height: 14)
                        .padding(.bottom, 14)
                }
                Headline(text: total == 1 ? "person already shares your places." : "people already share your places.", size: 28)
                    .padding(.top, 4)
                Subhead(text: "Make an account to see who they are and where you crossed.")
                    .padding(.top, 10)
                VStack(spacing: 0) {
                    ForEach(rows, id: \.0.id) { place, count in
                        HStack(spacing: 14) {
                            HStack(spacing: -14) {
                                ForEach(0..<min(count, 3), id: \.self) { i in
                                    BlurredAvatar(tones: [(0xDDD6CC, 0xCDD4D8), (0xD3DACF, 0xDCD1CC), (0xD7CFDA, 0xD8D4C6)][i])
                                        .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2))
                                }
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(place.name)
                                    .font(TPFont.body(16, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Text("\(count) \(count == 1 ? "person goes" : "people go") here too")
                                    .font(TPFont.body(14))
                                    .foregroundStyle(Theme.ink2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .overlay(alignment: .bottom) {
                            if place.id != rows.last?.0.id { Hairline(color: Theme.ruleSoft) }
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.rule))
                .padding(.top, 22)
            }
        } footer: {
            Button(total == 0 ? "Save my places" : "See who they are") { model.go(.account) }
                .buttonStyle(.primary)
                .disabled(model.preview == nil)
            Text("Exact places unlock only when you both like each other.")
                .font(TPFont.body(13))
                .foregroundStyle(Theme.ink2)
                .padding(.top, 4)
        }
        .task {
            if model.preview == nil { await model.loadPreview() }
        }
    }
}

private struct DemoRevealView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let people = model.people
        StepScaffold {
            if people.isEmpty {
                Headline(text: "No overlaps yet. That’s normal.")
                    .padding(.top, 12)
                Subhead(text: "As you take photos at your places, people who share them will show up in your feed.")
                    .padding(.top, 12)
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(people.count)")
                        .font(TPFont.display(112))
                        .tracking(-6)
                        .foregroundStyle(Theme.ink)
                    Circle().fill(Theme.accent).frame(width: 14, height: 14)
                        .padding(.bottom, 14)
                }
                Headline(text: people.count == 1 ? "person has already been in your places." : "people have already been in your places.", size: 28)
                    .padding(.top, 4)
                Subhead(text: "Some were there at the very same time. Others missed you by minutes.")
                    .padding(.top, 10)
                VStack(spacing: 10) {
                    ForEach(people.prefix(4)) { person in
                        OverlapRow(person: person)
                    }
                    if people.count > 4 {
                        Text("+ \(people.count - 4) more in your feed")
                            .font(TPFont.body(15, weight: .medium))
                            .foregroundStyle(Color(hex: 0x3A3A38))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.strong, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                    }
                }
                .padding(.top, 22)
                MonoLabel(text: "Demo people · add Supabase.json to go live", size: 10)
                    .padding(.top, 14)
            }
        } footer: {
            Button(people.isEmpty ? "Save my places" : "See who they are") { model.go(.account) }
                .buttonStyle(.primary)
            Text("Exact places unlock only when you both like each other.")
                .font(TPFont.body(13))
                .foregroundStyle(Theme.ink2)
                .padding(.top, 4)
        }
    }
}

private struct OverlapRow: View {
    let person: FeedPerson

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BlurredAvatar(tones: person.tones)
            VStack(alignment: .leading, spacing: 0) {
                TierChip(tier: person.first.tier)
                Text(person.first.title)
                    .font(TPFont.body(16, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 10)
                Text(person.first.detail)
                    .font(TPFont.body(14))
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 3)
                Text("Someone, \(person.age) · profile hidden for now")
                    .font(TPFont.body(13))
                    .foregroundStyle(Theme.ink3)
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.rule))
    }
}

struct BlurredAvatar: View {
    let tones: (UInt32, UInt32)

    var body: some View {
        ZStack {
            Circle().fill(Color(hex: tones.0))
            Circle().fill(Color(hex: tones.1).opacity(0.9)).frame(width: 22, height: 22).offset(y: -6)
            Ellipse().fill(Color(hex: tones.1).opacity(0.9)).frame(width: 40, height: 28).offset(y: 22)
        }
        .frame(width: 48, height: 48)
        .blur(radius: 4)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

struct TierChip: View {
    let tier: FeedPerson.Tier

    var body: some View {
        HStack(spacing: 6) {
            dot
            Text(tier.rawValue.uppercased())
                .font(TPFont.mono(10.5))
                .tracking(0.6)
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .overlay(Capsule().strokeBorder(Theme.rule))
    }

    @ViewBuilder private var dot: some View {
        switch tier {
        case .regulars: Circle().fill(Theme.accent).frame(width: 7, height: 7)
        case .sameMoment: Circle().fill(Theme.ink).frame(width: 7, height: 7)
        case .sameDay: Circle().strokeBorder(Theme.ink, lineWidth: 1.25).frame(width: 7, height: 7)
        case .nearMiss: Circle().strokeBorder(Theme.ink, style: StrokeStyle(lineWidth: 1.25, dash: [1.5, 1.5])).frame(width: 7, height: 7)
        case .samePlace: Circle().strokeBorder(Theme.mute, lineWidth: 1.25).frame(width: 7, height: 7)
        }
    }
}
