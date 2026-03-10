import Foundation
import UserNotifications
import Darwin

class SystemMonitor: ObservableObject {
    @Published var usageMB: Double = 0
    @Published var totalRAM: Double = Double(ProcessInfo.processInfo.physicalMemory) / 1024 / 1024 / 1024
    @Published var processorName: String = ""
    @Published var activeCores: Int = ProcessInfo.processInfo.activeProcessorCount
    @Published var diskFreeGB: Int = 0
    @Published var diskTotalGB: Int = 0
    @Published var cpuLoad: Double = 0
    @Published var uptime: String = ""
    
    // Novedades: Historial CPU y Red
    @Published var cpuHistory: [Double] = Array(repeating: 0, count: 60)
    @Published var downloadSpeed: String = "0 KB/s"
    @Published var uploadSpeed: String = "0 KB/s"

    private var timer: Timer?
    private var prevNetworkBytes: (in: UInt64, out: UInt64)?
    private var lastNotificationTime: Date = Date.distantPast

    // FIX 1: guardamos los ticks anteriores para calcular el diferencial real
    private var prevCpuInfo: [Int32] = []

    init() {
        self.processorName = getCPUName()
        requestNotificationPermission()
        startMonitoring()
    }

    // FIX 3: invalidar el timer al destruir el objeto
    deinit {
        timer?.invalidate()
    }

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.usageMB       = self.getMemoryUsage()
            self.updateDiskSpace()
            self.uptime        = self.getUptime()
            self.updateCPULoad()
            self.updateNetworkTraffic()
            self.checkAndNotify()
        }
    }

    private func getCPUName() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        return String(cString: brand)
    }

    private func getMemoryUsage() -> Double {
        var stats = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kerr == KERN_SUCCESS ? Double(stats.resident_size) / 1024 / 1024 : 0
    }

    // FIX 2: separar los valores en Int para no hardcodear strings en español
    private func updateDiskSpace() {
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
           let freeSize  = attrs[.systemFreeSize]  as? Int64,
           let totalSize = attrs[.systemSize]       as? Int64 {
            diskFreeGB  = Int(freeSize  / 1_073_741_824)   // 1024^3
            diskTotalGB = Int(totalSize / 1_073_741_824)
        }
    }

    private func getUptime() -> String {
        let seconds = Int(ProcessInfo.processInfo.systemUptime)
        let hours   = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    // FIX 1: CPU real usando diferencial de ticks user+sys vs idle
    private func updateCPULoad() {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let info = cpuInfo else { return }

        // Leer los 4 ticks por núcleo: user, system, idle, nice
        let ticksPerCPU = 4
        let totalTicks  = Int(numCPUs) * ticksPerCPU
        var current     = [Int32](repeating: 0, count: totalTicks)
        for i in 0..<totalTicks {
            current[i] = info[i]
        }
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(cpuInfoCount))

        // Si ya tenemos una muestra anterior, calculamos el diferencial
        if prevCpuInfo.count == totalTicks {
            var totalUsed: Double = 0
            var totalAll:  Double = 0

            for core in 0..<Int(numCPUs) {
                let base = core * ticksPerCPU
                let user   = Double(current[base + Int(CPU_STATE_USER)]   - prevCpuInfo[base + Int(CPU_STATE_USER)])
                let system = Double(current[base + Int(CPU_STATE_SYSTEM)] - prevCpuInfo[base + Int(CPU_STATE_SYSTEM)])
                let idle   = Double(current[base + Int(CPU_STATE_IDLE)]   - prevCpuInfo[base + Int(CPU_STATE_IDLE)])
                let nice   = Double(current[base + Int(CPU_STATE_NICE)]   - prevCpuInfo[base + Int(CPU_STATE_NICE)])

                let used = user + system + nice
                let all  = used + idle

                totalUsed += used
                totalAll  += all
            }

            let currentLoad = totalAll > 0 ? (totalUsed / totalAll) * 100.0 : 0
            cpuLoad = currentLoad
            
            // Actualizar historial
            cpuHistory.removeFirst()
            cpuHistory.append(currentLoad)
        }

        prevCpuInfo = current
    }

    // MARK: - Red
    private func updateNetworkTraffic() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        while let p = ptr {
            let flags = Int32(p.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK

            if isUp && !isLoopback {
                if let data = p.pointee.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self)
                    totalIn += UInt64(networkData.pointee.ifi_ibytes)
                    totalOut += UInt64(networkData.pointee.ifi_obytes)
                }
            }
            ptr = p.pointee.ifa_next
        }

        if let prev = prevNetworkBytes {
            let diffIn = totalIn.subtractingReportingOverflow(prev.in).partialValue
            let diffOut = totalOut.subtractingReportingOverflow(prev.out).partialValue
            
            self.downloadSpeed = formatBytes(diffIn) + "/s"
            self.uploadSpeed = formatBytes(diffOut) + "/s"
        }

        prevNetworkBytes = (in: totalIn, out: totalOut)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    // MARK: - Notificaciones
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func checkAndNotify() {
        // Cooldown de 5 minutos entre notificaciones
        guard Date().timeIntervalSince(lastNotificationTime) > 300 else { return }

        var alertTitle, alertBody: String?

        if cpuLoad > 90.0 {
            alertTitle = "Alerta de CPU 🔴"
            alertBody = "La carga del procesador ha superado el 90%."
        } else if diskFreeGB > 0 && diskTotalGB > 0 {
            let freePercent = Double(diskFreeGB) / Double(diskTotalGB)
            if freePercent < 0.10 {
                alertTitle = "Alerta de Disco ⚠️"
                alertBody = "Queda menos del 10% de espacio disponible."
            }
        }

        if let title = alertTitle, let body = alertBody {
            sendNotification(title: title, body: body)
            lastNotificationTime = Date()
        }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
