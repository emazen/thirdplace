import SwiftUI

@main
struct ThirdPlaceApp: App {
    @State private var model: AppModel

    init() {
        FontRegistry.registerAll()
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.ink)
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    Task { await model.handleOpenURL(url) }
                }
        }
    }
}
