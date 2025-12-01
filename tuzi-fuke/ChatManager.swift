//
//  ChatManager.swift
//  tuzi-fuke
//
//  通信系统 - 聊天管理器（MVP版本）
//  参考原项目 CommunicationManager.swift 和 RealtimeManager.swift
//

import Foundation
import Supabase
import Combine

// MARK: - ChatManager
@MainActor
class ChatManager: ObservableObject {

    // MARK: - 单例
    static let shared = ChatManager()

    // MARK: - Published 属性
    @Published var messages: [Message] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isConnected: Bool = false

    // MARK: - 私有属性
    private var realtimeChannel: RealtimeChannelV2?
    private var messageInsertTask: Task<Void, Never>?
    private let supabase = SupabaseManager.shared.client

    // MARK: - 初始化
    private init() {
        print("📡 [ChatManager] 初始化完成")
    }

    deinit {
        messageInsertTask?.cancel()
        messageInsertTask = nil
    }

    // MARK: - 公开方法

    /// 启动聊天系统
    func start() async {
        print("📡 [ChatManager] 启动聊天系统...")

        // 1. 加载历史消息
        await loadMessages()

        // 2. 订阅实时消息
        await subscribeToRealtime()
    }

    /// 停止聊天系统
    func stop() async {
        print("📡 [ChatManager] 停止聊天系统...")

        messageInsertTask?.cancel()
        messageInsertTask = nil

        await realtimeChannel?.unsubscribe()
        realtimeChannel = nil

        isConnected = false
        print("✅ [ChatManager] 聊天系统已停止")
    }

    /// 发送广播消息
    func sendMessage(content: String) async throws {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChatError.emptyMessage
        }

        guard let userId = await SupabaseManager.shared.getCurrentUserId() else {
            throw ChatError.notAuthenticated
        }

        print("📡 [ChatManager] 发送消息: \(content.prefix(20))...")

        // 使用 REST API 发送（避免 Swift 6 并发问题）
        try await messageUploader.upload(
            MessageUploadData(
                sender_id: userId.uuidString,
                content: content,
                message_type: MessageType.broadcast.rawValue,
                sender_name: nil
            ),
            supabaseUrl: SupabaseConfig.supabaseURL.absoluteString,
            anonKey: SupabaseConfig.supabaseAnonKey,
            accessToken: try? await supabase.auth.session.accessToken
        )

        print("✅ [ChatManager] 消息发送成功")
    }

    /// 刷新消息
    func refresh() async {
        await loadMessages()
    }

    // MARK: - 私有方法

    /// 加载历史消息
    private func loadMessages() async {
        isLoading = true
        errorMessage = nil

        do {
            // 使用 REST API 加载消息
            let loadedMessages = try await loadMessagesViaREST()
            messages = loadedMessages.reversed()  // 倒序显示
            print("✅ [ChatManager] 加载了 \(messages.count) 条历史消息")
        } catch {
            errorMessage = "加载消息失败: \(error.localizedDescription)"
            print("❌ [ChatManager] 加载消息失败: \(error)")
        }

        isLoading = false
    }

    /// 通过 REST API 加载消息
    private func loadMessagesViaREST() async throws -> [Message] {
        let url = SupabaseConfig.supabaseURL
            .appendingPathComponent("rest/v1/messages")
            .appending(queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "50")
            ])

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ChatError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            return Self.parseDate(dateString) ?? Date()
        }

        return try decoder.decode([Message].self, from: data)
    }

    /// 订阅 Realtime 消息
    private func subscribeToRealtime() async {
        print("📡 [ChatManager] 正在订阅 Realtime...")

        // 创建 channel（参考 RealtimeManager）
        realtimeChannel = await supabase.realtimeV2.channel("public:messages")

        guard let channel = realtimeChannel else {
            print("❌ [ChatManager] 无法创建 channel")
            return
        }

        // 监听 INSERT 事件
        let insertions = await channel.postgresChange(InsertAction.self, table: "messages")
        messageInsertTask = Task { @MainActor [weak self] in
            for await insertion in insertions {
                await self?.handleMessageInsert(insertion)
            }
        }

        // 订阅
        await channel.subscribe()

        isConnected = true
        print("✅ [ChatManager] Realtime 订阅成功")
    }

    /// 处理新消息插入
    private func handleMessageInsert(_ action: InsertAction) async {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)
                return Self.parseDate(dateString) ?? Date()
            }

            let message = try action.decodeRecord(decoder: decoder) as Message

            // 检查是否已存在（避免重复）
            guard !messages.contains(where: { $0.id == message.id }) else {
                return
            }

            // 添加到消息列表
            messages.append(message)
            print("📨 [ChatManager] 收到新消息: \(message.content.prefix(20))...")

        } catch {
            print("❌ [ChatManager] 解析新消息失败: \(error)")
        }
    }

    /// 解析日期字符串
    nonisolated private static func parseDate(_ dateString: String) -> Date? {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ss"
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        // ISO8601 fallback
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: dateString)
    }

    // MARK: - 调试方法

    func printStatus() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📡 ChatManager 状态")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("消息数量: \(messages.count)")
        print("Realtime 连接: \(isConnected ? "✅ 已连接" : "❌ 未连接")")
        print("加载中: \(isLoading)")
        print("错误: \(errorMessage ?? "无")")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}

// MARK: - 错误类型
enum ChatError: LocalizedError {
    case emptyMessage
    case notAuthenticated
    case invalidResponse
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            return "消息内容不能为空"
        case .notAuthenticated:
            return "请先登录"
        case .invalidResponse:
            return "服务器响应无效"
        case .serverError(let code, let message):
            return "服务器错误 (\(code)): \(message)"
        }
    }
}

// MARK: - 消息上传器（Actor，解决 Swift 6 并发问题）

/// 消息上传数据结构
struct MessageUploadData: Encodable, Sendable {
    let sender_id: String
    let content: String
    let message_type: String
    let sender_name: String?
}

/// 消息上传错误
enum MessageUploadError: Error, LocalizedError {
    case encodingFailed
    case networkError(Error)
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "数据编码失败"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "服务器错误 (\(code)): \(message)"
        }
    }
}

/// 消息上传器 - 使用原生 URLSession 直接调用 REST API
actor MessageUploader {

    func upload(_ data: MessageUploadData, supabaseUrl: String, anonKey: String, accessToken: String?) async throws {
        let urlString = "\(supabaseUrl)/rest/v1/messages"
        guard let url = URL(string: urlString) else {
            throw MessageUploadError.encodingFailed
        }

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(data)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        }

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MessageUploadError.networkError(NSError(domain: "Invalid response", code: -1))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw MessageUploadError.serverError(httpResponse.statusCode, errorMessage)
        }
    }
}

/// 全局消息上传器实例
let messageUploader = MessageUploader()
