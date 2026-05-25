import Foundation
import OSLog

struct Logger {
    private static let log = OSLog(subsystem: "com.darusc.vcamdroid", category: "VCamdroid")

    static func log(_ message: String, tag: String = "VCAMDROID") {
        os_log("[%@] %@", log: log, type: .info, tag, message)
        #if DEBUG
        print("[\(tag)] \(message)")
        #endif
    }
}
