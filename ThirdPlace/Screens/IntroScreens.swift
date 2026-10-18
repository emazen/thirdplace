import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
                .padding(.top, 10)
            Spacer(minLength: 8)
            CrossingHero()
                .frame(maxWidth: .infinity)
                .frame(height: 260)
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 0) {
                Headline(text: "You’ve crossed paths before.", size: 35)
                Headline(text: "You just didn’t know it.", size: 35, color: Theme.mute)
            }
            .accessibilityElement(children: .combine)
            Subhead(text: "Meet the people who share your cafés, climbing gyms and Sunday parks, found in photos you’ve already taken.")
                .padding(.top, 16)
            VStack(spacing: 6) {
                Button("Get started") { model.go(.how) }
                    .buttonStyle(.primary)
                Button("I already have an account") { model.go(.account) }
                    .buttonStyle(.quiet)
            }
            .padding(.top, 26)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 4)
    }
}

/// Two routes over a quiet street grid, meeting at one café.
struct CrossingHero: View {
    var body: some View {
        Canvas { context, size in
            let sx = size.width / 342
            let sy = size.height / 300
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }

            var grid = Path()
            for y in [52, 128, 204, 270] as [CGFloat] { grid.move(to: p(0, y)); grid.addLine(to: p(342, y)) }
            for x in [48, 132, 222, 300] as [CGFloat] { grid.move(to: p(x, 0)); grid.addLine(to: p(x, 300)) }
            context.stroke(grid, with: .color(Theme.rule), lineWidth: 1)

            var avenue = Path()
            avenue.move(to: p(-20, 300)); avenue.addLine(to: p(360, 30))
            context.stroke(avenue, with: .color(Color(hex: 0xEAE9E4)), lineWidth: 14)

            var mine = Path()
            mine.move(to: p(-10, 262))
            mine.addCurve(to: p(186, 160), control1: p(64, 250), control2: p(112, 160))
            mine.addCurve(to: p(352, 56), control1: p(260, 160), control2: p(292, 76))
            context.stroke(mine, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            var theirs = Path()
            theirs.move(to: p(-10, 64))
            theirs.addCurve(to: p(186, 160), control1: p(70, 74), control2: p(118, 168))
            theirs.addCurve(to: p(352, 266), control1: p(254, 152), control2: p(288, 252))
            context.stroke(theirs, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.5, 7]))

            for c in [p(56, 248), p(300, 72)] {
                context.fill(Path(ellipseIn: CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)), with: .color(Theme.ink))
            }
            for c in [p(64, 73), p(292, 252)] {
                context.stroke(Path(ellipseIn: CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)), with: .color(Theme.ink), lineWidth: 1.5)
            }

            let cross = p(186, 160)
            context.stroke(Path(ellipseIn: CGRect(x: cross.x - 20, y: cross.y - 20, width: 40, height: 40)), with: .color(Theme.accent), lineWidth: 1)
            context.fill(Path(ellipseIn: CGRect(x: cross.x - 6, y: cross.y - 6, width: 12, height: 12)), with: .color(Theme.accent))

            let tag = p(4, 22)
            context.fill(Path(ellipseIn: CGRect(x: tag.x, y: tag.y - 3, width: 6, height: 6)), with: .color(Theme.accent))
            context.draw(Text("14× SAME CAFÉ").font(TPFont.mono(10)).foregroundColor(Theme.ink), at: CGPoint(x: tag.x + 14, y: tag.y), anchor: .leading)
            context.draw(Text("51.5450° N  0.0553° W").font(TPFont.mono(10)).foregroundColor(Theme.ink2), at: CGPoint(x: tag.x + 14, y: tag.y + 16), anchor: .leading)
        }
        .accessibilityLabel("Your path and someone else’s crossing at the same café")
    }
}

struct HowView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        StepScaffold {
            Headline(text: "Here’s the idea.")
            VStack(spacing: 0) {
                Hairline()
                NumberedRow(number: 1, title: "Your photos already know.",
                            detail: "Every photo carries a where and a when. That’s all we read.")
                NumberedRow(number: 2, title: "We find your third places.",
                            detail: "Not home, not work. The cafés, gyms and parks you keep going back to.")
                NumberedRow(number: 3, title: "You meet the people who share them.",
                            detail: "Your feed is everyone who crossed your path: regulars at your spots, the same crowd at a gig, someone you missed by minutes.")
            }
            .padding(.top, 28)
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    MonoLabel(text: "Example overlap")
                    Text("Both regulars at the same café since April. 14 weeks in common.")
                        .font(TPFont.display(20))
                        .tracking(-0.4)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 24)
        } footer: {
            Button("Continue") { model.go(.privacy) }
                .buttonStyle(.primary)
        }
    }
}

struct PrivacyView: View {
    @Environment(AppModel.self) private var model
    @State private var showSent = false
    @State private var asking = false

    private let rows: [(String, String)] = [
        ("Where it was taken", "~150 m area"),
        ("When it was taken", "to the hour"),
        ("The photo itself", "never opened"),
        ("Home and work", "hidden"),
        ("Your live location", "never tracked")
    ]

    var body: some View {
        StepScaffold {
            Headline(text: "Your photos never leave your phone.")
            Subhead(text: "The scan runs on your phone. From each photo we keep two things, both blurred before anything is sent.")
                .padding(.top, 12)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.0).font(TPFont.body(15)).foregroundStyle(Theme.ink)
                        Spacer(minLength: 12)
                        Text(row.1).font(TPFont.mono(12)).foregroundStyle(Theme.ink2)
                    }
                    .padding(.vertical, 16)
                    .overlay(alignment: .bottom) {
                        if index < rows.count - 1 { Hairline(color: Theme.ruleSoft) }
                    }
                }
            }
            .padding(.horizontal, 18)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.rule))
            .padding(.top, 24)

            Button {
                withAnimation(.smooth(duration: 0.25)) { showSent.toggle() }
            } label: {
                HStack {
                    Text("See exactly what gets sent")
                        .underline(color: Theme.strong)
                    Spacer()
                    Image(systemName: showSent ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                }
                .font(TPFont.body(15, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .padding(.top, 12)

            if showSent {
                VStack(alignment: .leading, spacing: 4) {
                    Group {
                        Text("area gcpvn2k · 2025-05-15 08:00")
                        Text("area gcpvn2k · 2025-05-22 08:00")
                        Text("area gcnr0bm · 2024-06-29 22:00")
                    }
                    .font(TPFont.mono(12))
                    .foregroundStyle(Theme.ink)
                    Text("One line per photo. No image, no address, no exact time.")
                        .font(TPFont.body(13))
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, 8)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.rule))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        } footer: {
            Button("Scan my photos") {
                asking = true
                Task {
                    await model.requestPhotoAccess()
                    asking = false
                }
            }
            .buttonStyle(.primary)
            .disabled(asking)
        }
    }
}
