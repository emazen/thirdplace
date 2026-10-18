import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ZStack {
            Theme.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                if let progress = model.step.progress {
                    TopBar(step: progress, total: Step.progressTotal, onBack: model.back)
                        .transition(.opacity)
                }
                screen
                    .id(model.step)
                    .transition(.asymmetric(
                        insertion: .move(edge: model.direction).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder private var screen: some View {
        switch model.step {
        case .welcome: WelcomeView()
        case .how: HowView()
        case .privacy: PrivacyView()
        case .scan: ScanView()
        case .places: PlacesView()
        case .moments: MomentsView()
        case .reveal: RevealView()
        case .account: AccountView()
        case .basics: BasicsView()
        case .photos: PhotosStepView()
        case .verify: VerifyView()
        case .done: DoneView()
        case .feed: FeedView()
        }
    }
}

struct TopBar: View {
    let step: Int
    let total: Int
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back")
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.rule)
                    Rectangle().fill(Theme.ink)
                        .frame(width: geo.size.width * CGFloat(step) / CGFloat(total))
                }
            }
            .frame(height: 2)
            .animation(.smooth(duration: 0.4), value: step)
            Text(String(format: "%02d / %02d", step, total))
                .font(TPFont.mono(11))
                .foregroundStyle(Theme.ink3)
                .monospacedDigit()
        }
        .padding(.leading, 8)
        .padding(.trailing, Theme.gutter)
        .frame(height: 52)
        .accessibilityElement(children: .contain)
    }
}
