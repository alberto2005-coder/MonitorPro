import SwiftUI

@main
struct MonitorProApp: App {
    var body: some Scene {
        // Crea el icono en la barra superior
        MenuBarExtra("Monitor", systemImage: "gauge.medium") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
