import SwiftUI
import ServiceManagement

@main
struct MonitorProApp: App {
    @StateObject private var monitor = SystemMonitor()
    
    var body: some Scene {
        // Crea el icono dinámico en la barra superior
        MenuBarExtra("\(Int(monitor.cpuLoad))% CPU", systemImage: "gauge.medium") {
            ContentView(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}
