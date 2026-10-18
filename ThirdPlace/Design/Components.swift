import SwiftUI

// MARK: - Type

struct Headline: View {
    let text: String
    var size: CGFloat = 32
    var color: Color = Theme.ink

    var body: some View {
        Text(text)
            .font(TPFont.display(size))
            .tracking(-size * 0.03)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct Subhead: View {
    let text: String
    var size: CGFloat = 16

    var body: some View {
        Text(text)
            .font(TPFont.body(size))
            .foregroundStyle(Theme.ink2)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct MonoLabel: View {
    let text: String
    var color: Color = Theme.ink3
    var size: CGFloat = 11

    var body: some View {
        Text(text.uppercased())
            .font(TPFont.mono(size))
            .tracking(size * 0.06)
            .foregroundStyle(color)
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TPFont.body(17, weight: .medium))
            .foregroundStyle(isEnabled ? Color.white : Theme.ink3)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Capsule().fill(isEnabled ? Theme.ink : Theme.rule))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TPFont.body(17, weight: .medium))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().strokeBorder(Theme.strong, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TPFont.body(15, weight: .medium))
            .foregroundStyle(Theme.ink2)
            .frame(minHeight: 44)
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
}

// MARK: - Surfaces

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.rule, lineWidth: 1))
    }
}

struct Hairline: View {
    var color: Color = Theme.rule
    var body: some View {
        Rectangle().fill(color).frame(height: 1)
    }
}

/// A numbered row with hairlines, used for explanations instead of icon tiles.
struct NumberedRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(String(format: "%02d", number))
                .font(TPFont.mono(12))
                .foregroundStyle(Theme.ink3)
                .frame(width: 22, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(TPFont.body(17, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(TPFont.body(15))
                    .foregroundStyle(Theme.ink2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

struct CheckCircle: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            if isOn {
                Circle().fill(Theme.ink)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle().strokeBorder(Theme.strong, lineWidth: 1.5)
            }
        }
        .frame(width: 24, height: 24)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

/// Eight thin bars: visit days per month, oldest first.
struct VisitBars: View {
    let values: [Int]
    let isOn: Bool

    var body: some View {
        let top = max(values.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Rectangle()
                    .fill(isOn ? Theme.ink : Color(hex: 0xD6D5CF))
                    .frame(width: 2, height: 2 + 20 * CGFloat(value) / CGFloat(top))
            }
        }
        .frame(height: 22, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

// MARK: - Brand

/// Two paths and the point where they cross.
struct CrossingMark: View {
    var size: CGFloat = 22
    var lineColor: Color = Theme.ink

    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width / 24
            var mine = Path()
            mine.move(to: CGPoint(x: 3 * s, y: 18 * s))
            mine.addCurve(to: CGPoint(x: 21 * s, y: 5 * s), control1: CGPoint(x: 8 * s, y: 16 * s), control2: CGPoint(x: 11 * s, y: 8 * s))
            context.stroke(mine, with: .color(lineColor), style: StrokeStyle(lineWidth: 2 * s, lineCap: .round))
            var theirs = Path()
            theirs.move(to: CGPoint(x: 3 * s, y: 6 * s))
            theirs.addCurve(to: CGPoint(x: 21 * s, y: 19 * s), control1: CGPoint(x: 10 * s, y: 7 * s), control2: CGPoint(x: 13 * s, y: 16 * s))
            context.stroke(theirs, with: .color(lineColor), style: StrokeStyle(lineWidth: 2 * s, lineCap: .round, dash: [0.5 * s, 4 * s]))
            let dot = CGRect(x: 11.6 * s - 2.6 * s, y: 11.4 * s - 2.6 * s, width: 5.2 * s, height: 5.2 * s)
            context.fill(Path(ellipseIn: dot), with: .color(Theme.accent))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct Wordmark: View {
    var body: some View {
        HStack(spacing: 9) {
            CrossingMark()
            Text("third place")
                .font(TPFont.display(19))
                .tracking(-0.6)
                .foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Third Place")
    }
}

// MARK: - Layout

/// Shared frame for onboarding steps: scrolling content plus a pinned footer.
struct StepScaffold<Content: View, Footer: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 20)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            VStack(spacing: 6) {
                footer
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }
}
