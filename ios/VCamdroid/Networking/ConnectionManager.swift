import Foundation
import Network

class ConnectionManager: ObservableObject {
    private let monitor = NWPathMonitor()
    @Published var localIPAddress: String? = nil
    @Published var allIPs: [String] = []

    private let queue = DispatchQueue(label: "connection.manager")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.updateLocalIPs()
        }
        monitor.start(queue: queue)
        updateLocalIPs()
    }

    private func updateLocalIPs() {
        var ips: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return }

        var ptr = firstAddr
        while true {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee
            if addr.sa_family == UInt8(AF_INET) {
                let up = (flags & IFF_UP) != 0
                let loopback = (flags & IFF_LOOPBACK) != 0
                if up && !loopback {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(ptr.pointee.ifa_addr,
                                socklen_t(addr.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, 0, NI_NUMERICHOST)
                    ips.append(String(cString: hostname))
                }
            }
            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }
        freeifaddrs(ifaddr)

        DispatchQueue.main.async {
            self.allIPs = ips
            self.localIPAddress = ips.first ?? "127.0.0.1"
        }
    }

    deinit {
        monitor.cancel()
    }
}
