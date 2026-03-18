import SwiftUI

@main
struct BokeFocusApp: App {
    @State private var languageManager = LanguageManager.shared

    init() {
        AdManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(languageManager)
        }
    }
}
