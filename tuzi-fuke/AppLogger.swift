//
//  AppLogger.swift
//  tuzi-fuke
//
//  App内日志管理器 - 支持断开Xcode后查看日志
//

import Foundation
import SwiftUI
import Combine

// MARK: - 日志级别

enum LogLevel: String {
    case debug = "🔍"
    case info = "📍"
    case success = "✅"
    case warning = "⚠️"
    case error = "❌"

    var color: Color {
        switch self {
        case .debug: return .gray
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

// MARK: - 日志条目

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let category: String
    let message: String

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }

    var fullText: String {
        "\(formattedTime) \(level.rawValue) [\(category)] \(message)"
    }
}

// MARK: - AppLogger 单例

@MainActor
class AppLogger: ObservableObject {
    static let shared = AppLogger()

    @Published private(set) var logs: [LogEntry] = []

    // 最大保留日志数量
    private let maxLogs = 500

    private init() {
        log(.info, category: "AppLogger", message: "日志系统初始化")
    }

    // MARK: - 日志方法

    func log(_ level: LogLevel, category: String, message: String) {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message
        )

        // 添加到内存
        logs.append(entry)

        // 限制数量
        if logs.count > maxLogs {
            logs.removeFirst(logs.count - maxLogs)
        }

        // 同时输出到控制台（Xcode调试用）
        print(entry.fullText)
    }

    // MARK: - 便捷方法

    func debug(_ category: String, _ message: String) {
        log(.debug, category: category, message: message)
    }

    func info(_ category: String, _ message: String) {
        log(.info, category: category, message: message)
    }

    func success(_ category: String, _ message: String) {
        log(.success, category: category, message: message)
    }

    func warning(_ category: String, _ message: String) {
        log(.warning, category: category, message: message)
    }

    func error(_ category: String, _ message: String) {
        log(.error, category: category, message: message)
    }

    // MARK: - 清除日志

    func clear() {
        logs.removeAll()
        log(.info, category: "AppLogger", message: "日志已清除")
    }

    // MARK: - 导出日志

    func exportLogs() -> String {
        logs.map { $0.fullText }.joined(separator: "\n")
    }
}

// MARK: - 全局便捷函数

func appLog(_ level: LogLevel, category: String, message: String) {
    Task { @MainActor in
        AppLogger.shared.log(level, category: category, message: message)
    }
}
