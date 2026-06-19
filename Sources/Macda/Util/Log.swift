import Foundation

/// Simple persistent logger. Writes to a rotating file under the data folder so
/// crashes and errors can be studied after the fact. Tail it with:
///   tail -f ~/Library/Application\ Support/Macda/logs/macda.log
enum Log {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Macda/logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()
    static let fileURL = directory.appendingPathComponent("macda.log")

    private static let queue = DispatchQueue(label: "macda.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func info(_ message: String) { write("INFO", message) }
    static func error(_ message: String) { write("ERROR", message) }

    static func write(_ level: String, _ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(level): \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
        queue.async {
            rotateIfNeeded()
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? line.data(using: .utf8)?.write(to: fileURL)
            }
        }
    }

    private static func rotateIfNeeded() {
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        if (size ?? 0) > 2_000_000 {   // keep the last ~2MB
            let old = directory.appendingPathComponent("macda.log.1")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: fileURL, to: old)
        }
    }

    /// Capture uncaught exceptions and fatal signals into the log.
    static func installCrashHandlers() {
        info("Macda starting — log at \(fileURL.path)")
        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.joined(separator: "\n  ")
            Log.write("CRASH", "Uncaught \(exception.name.rawValue): \(exception.reason ?? "")\n  \(stack)")
        }
        for sig in [SIGABRT, SIGSEGV, SIGILL, SIGTRAP, SIGBUS, SIGFPE] {
            signal(sig) { received in
                // Minimal async-signal-safe note; details come from the macOS .ips report.
                let msg = "[signal] fatal signal \(received) received\n"
                if let data = msg.data(using: .utf8) {
                    let fd = open(Log.fileURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
                    if fd >= 0 { data.withUnsafeBytes { _ = Foundation.write(fd, $0.baseAddress, data.count) }; close(fd) }
                }
                signal(received, SIG_DFL)
                raise(received)
            }
        }
    }
}
