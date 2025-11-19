import Foundation
import OSLog

/// Category-based logging system with filtering and channels
@MainActor
class ChannelLogger: ObservableObject {

    // MARK: - Log Channels

    enum Channel: String, CaseIterable {
        case ar = "AR"
        case rendering = "Rendering"
        case physics = "Physics"
        case networking = "Networking"
        case audio = "Audio"
        case input = "Input"
        case gameplay = "Gameplay"
        case performance = "Performance"
        case system = "System"
        case debug = "Debug"

        var emoji: String {
            switch self {
            case .ar: return "🎯"
            case .rendering: return "🎨"
            case .physics: return "⚛️"
            case .networking: return "📡"
            case .audio: return "🔊"
            case .input: return "🎮"
            case .gameplay: return "🎲"
            case .performance: return "⚡"
            case .system: return "⚙️"
            case .debug: return "🐛"
            }
        }
    }

    enum LogLevel: Int, Comparable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3

        static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }

        var emoji: String {
            switch self {
            case .debug: return "💬"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            }
        }
    }

    // MARK: - Log Entry

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let channel: Channel
        let level: LogLevel
        let message: String
        let file: String
        let function: String
        let line: Int
    }

    // MARK: - Configuration

    var minimumLevel: LogLevel = .info
    var enabledChannels: Set<Channel> = Set(Channel.allCases)

    @Published var logEntries: [LogEntry] = []
    private let maxLogEntries = 1000

    // MARK: - OSLog Integration

    private var osLoggers: [Channel: Logger] = [:]

    // MARK: - Statistics

    private(set) var totalLogs: Int = 0
    private var logCounts: [Channel: Int] = [:]
    private var levelCounts: [LogLevel: Int] = [:]

    // MARK: - Initialization

    init() {
        // Create OSLog loggers for each channel
        for channel in Channel.allCases {
            osLoggers[channel] = Logger(subsystem: "com.game.engine", category: channel.rawValue)
        }

        print("✅ Channel Logger initialized")
    }

    // MARK: - Logging

    /// Log message to channel
    func log(
        _ message: String,
        channel: Channel = .system,
        level: LogLevel = .info,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        // Filter by level
        guard level >= minimumLevel else { return }

        // Filter by channel
        guard enabledChannels.contains(channel) else { return }

        let entry = LogEntry(
            timestamp: Date(),
            channel: channel,
            level: level,
            message: message,
            file: (file as NSString).lastPathComponent,
            function: function,
            line: line
        )

        logEntries.append(entry)
        totalLogs += 1

        logCounts[channel, default: 0] += 1
        levelCounts[level, default: 0] += 1

        // Trim old entries
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst()
        }

        // Print to console
        let prefix = "\(channel.emoji) [\(channel.rawValue)] \(level.emoji)"
        let location = "\(entry.file):\(entry.line)"
        print("\(prefix) \(message) (\(location))")

        // Log to OSLog
        if let logger = osLoggers[channel] {
            switch level {
            case .debug:
                logger.debug("\(message)")
            case .info:
                logger.info("\(message)")
            case .warning:
                logger.warning("\(message)")
            case .error:
                logger.error("\(message)")
            }
        }

        // Post notification
        NotificationCenter.default.post(
            name: .logEntryAdded,
            object: entry
        )
    }

    // MARK: - Convenience Methods

    func debug(_ message: String, channel: Channel = .debug, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, channel: channel, level: .debug, file: file, function: function, line: line)
    }

    func info(_ message: String, channel: Channel = .system, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, channel: channel, level: .info, file: file, function: function, line: line)
    }

    func warning(_ message: String, channel: Channel = .system, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, channel: channel, level: .warning, file: file, function: function, line: line)
    }

    func error(_ message: String, channel: Channel = .system, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, channel: channel, level: .error, file: file, function: function, line: line)
    }

    // MARK: - Channel-Specific Logging

    func logAR(_ message: String, level: LogLevel = .info) {
        log(message, channel: .ar, level: level)
    }

    func logRendering(_ message: String, level: LogLevel = .info) {
        log(message, channel: .rendering, level: level)
    }

    func logPhysics(_ message: String, level: LogLevel = .info) {
        log(message, channel: .physics, level: level)
    }

    func logNetworking(_ message: String, level: LogLevel = .info) {
        log(message, channel: .networking, level: level)
    }

    func logPerformance(_ message: String, level: LogLevel = .info) {
        log(message, channel: .performance, level: level)
    }

    // MARK: - Filtering

    /// Enable specific channel
    func enableChannel(_ channel: Channel) {
        enabledChannels.insert(channel)
        print("Enabled channel: \(channel.rawValue)")
    }

    /// Disable specific channel
    func disableChannel(_ channel: Channel) {
        enabledChannels.remove(channel)
        print("Disabled channel: \(channel.rawValue)")
    }

    /// Set minimum log level
    func setMinimumLevel(_ level: LogLevel) {
        minimumLevel = level
        print("Minimum log level: \(level)")
    }

    /// Get logs for channel
    func getLogs(for channel: Channel) -> [LogEntry] {
        return logEntries.filter { $0.channel == channel }
    }

    /// Get logs with level
    func getLogs(withLevel level: LogLevel) -> [LogEntry] {
        return logEntries.filter { $0.level == level }
    }

    // MARK: - Export

    /// Export logs to string
    func exportLogs() -> String {
        var output = "=== Log Export ===\n"
        output += "Total Entries: \(logEntries.count)\n"
        output += "Timestamp: \(Date())\n\n"

        for entry in logEntries {
            let timestamp = ISO8601DateFormatter().string(from: entry.timestamp)
            output += "[\(timestamp)] \(entry.channel.emoji) [\(entry.channel.rawValue)] \(entry.level.emoji) \(entry.message)\n"
            output += "  Location: \(entry.file):\(entry.line) in \(entry.function)\n\n"
        }

        return output
    }

    /// Clear all logs
    func clearLogs() {
        logEntries.removeAll()
        totalLogs = 0
        logCounts.removeAll()
        levelCounts.removeAll()
        print("Logs cleared")
    }

    // MARK: - Statistics

    func getLoggerStats() -> LoggerStats {
        return LoggerStats(
            totalLogs: totalLogs,
            storedLogs: logEntries.count,
            logsByChannel: logCounts,
            logsByLevel: levelCounts,
            minimumLevel: minimumLevel,
            enabledChannels: enabledChannels.count
        )
    }

    func getDebugInfo() -> String {
        let stats = getLoggerStats()

        var info = "=== Channel Logger ===\n"
        info += "Total Logs: \(stats.totalLogs)\n"
        info += "Stored: \(stats.storedLogs)/\(maxLogEntries)\n"
        info += "Min Level: \(stats.minimumLevel)\n"
        info += "Enabled Channels: \(stats.enabledChannels)/\(Channel.allCases.count)\n"

        info += "\nLogs by Channel:\n"
        for channel in Channel.allCases {
            let count = stats.logsByChannel[channel] ?? 0
            if count > 0 {
                info += "  \(channel.emoji) \(channel.rawValue): \(count)\n"
            }
        }

        info += "\nLogs by Level:\n"
        for level in [LogLevel.debug, .info, .warning, .error] {
            let count = stats.logsByLevel[level] ?? 0
            if count > 0 {
                info += "  \(level.emoji) \(level): \(count)\n"
            }
        }

        info += "===================="

        return info
    }
}

struct LoggerStats {
    let totalLogs: Int
    let storedLogs: Int
    let logsByChannel: [ChannelLogger.Channel: Int]
    let logsByLevel: [ChannelLogger.LogLevel: Int]
    let minimumLevel: ChannelLogger.LogLevel
    let enabledChannels: Int
}

extension Notification.Name {
    static let logEntryAdded = Notification.Name("logEntryAdded")
}
