import SwiftUI

@main
struct SproutlyApp: App {
    @StateObject private var store = GardenStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.light)
        }
    }
}
