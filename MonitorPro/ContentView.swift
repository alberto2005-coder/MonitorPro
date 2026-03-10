import SwiftUI

struct ContentView: View {
    @StateObject var monitor = SystemMonitor()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bolt.fill").foregroundColor(.yellow)
                Text("Monitor de Sistema Pro").font(.headline)
            }.frame(maxWidth: .infinity, alignment: .center)
            
            Divider()

            VStack(spacing: 8) {
                InfoRow(label: "Procesador:", value: monitor.processorName, icon: "cpu", color: .orange)
                InfoRow(label: "Núcleos:", value: "\(monitor.activeCores) Cores", icon: "number", color: .blue)
                InfoRow(label: "Tiempo Activo:", value: monitor.uptime, icon: "clock", color: .green)
                InfoRow(label: "Disco:", value: "\(monitor.diskFreeGB)GB libres de \(monitor.diskTotalGB)GB", icon: "internaldrive", color: .gray)
            }

            Divider()

            // Sección de Carga Dinámica
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Label("Carga CPU", systemImage: "waveform.path.ecg").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(monitor.cpuLoad))%").font(.caption).bold()
                }
                ProgressView(value: monitor.cpuLoad, total: 100)
                    .tint(.orange)
                
                HStack {
                    Label("RAM App", systemImage: "memorychip").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(monitor.usageMB)) MB").font(.caption).bold()
                }
                ProgressView(value: min(monitor.usageMB, 500), total: 500)
                    .tint(.blue)
            }

            Divider()

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Text("Cerrar Dashboard").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding()
        .frame(width: 320)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon).foregroundColor(color).frame(width: 20)
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.medium).lineLimit(1)
        }
        .font(.system(size: 11))
    }
}
