import Foundation
import os.log

class Logger {
    static let shared = Logger()
    private let osLog = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "VoiceControl")
    
    private init() {}
    
    func log(_ message: String, type: OSLogType = .default) {
        os_log("%{public}@", log: osLog, type: type, message)
        
        #if DEBUG
        print("VoiceControl: \(message)")
        #endif
    }
    
    func debug(_ message: String) {
        log(message, type: .debug)
    }
    
    func info(_ message: String) {
        log(message, type: .info)
    }
    
    func error(_ message: String) {
        log(message, type: .error)
    }
}