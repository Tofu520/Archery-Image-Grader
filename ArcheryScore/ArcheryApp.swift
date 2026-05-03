import SwiftUI
import SwiftData

@main
struct ArcheryApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Session.self)
    }
}
