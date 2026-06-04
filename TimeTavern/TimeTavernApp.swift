import SwiftData
import SwiftUI

@main
struct TimeTavernApp: App {
    @StateObject private var store = TimeTavernStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
        .modelContainer(for: [AppSnapshot.self])
    }
}
