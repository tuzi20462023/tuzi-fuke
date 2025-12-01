//
//  ChatManager.swift
//  tuzi-fuke
//
//  通信系统 - 聊天管理器（MVP版本）
//  负责消息收发、Realtime 订阅
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
    private var subscriptionTask: Task<Void, Never>?
    private let supabase = SupabaseManager.shared.client

    // MARK: - 初始化
    private init() {
        AppLogger.shared.info("[ChatManager] 初始化完成", category: "Chat")
    }

    deinit {
        subscriptionTask?.cancel()
    }

    // MARK: - 公开方法

    /// 启动聊天系统
    func start() async {
        AppLogger.shared.info("[ChatManager] 启动聊天系统...", category: "Chat")

        // 1. 加载历史消息
        await loadMessages()

        // 2. 订阅实时消息
        await subscribeToRealtime()
    }

    /// 停止聊天系统
    func stop() async {
        AppLogger.shared.info("[ChatManager] 停止聊天系统...", category: "Chat")

        subscriptionTask?.cancel()
        subscriptionTask = nil

        if let channel = realtimeChannel {
            await channel.unsubscribe()
            realtimeChannel = nil
        }

        isConnected = false
    }

    /// 发送广播消息
    func sendMessage(content: String) async throws {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChatError.emptyMessage
        }

        guard let userId = await SupabaseManager.shared.getCurrentUserId() else {
            throw ChatError.notAuthenticated
        }

        AppLogger.shared.info("[ChatManager] 发送消息: \(content.prefix(20))...", category: "Chat")

        // 使用 REST API 发送（避免 Swift 6 并发问题）
        try await sendMessageViaREST(
            senderId: userId,
            content: content,
            messageType: .broadcast,
            senderName: nil  // TODO: 从用户资料获取
        )

        AppLogger.shared.success("[ChatManager] 消息发送成功", category: "Chat")
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
            let response: [Message] = try await supabase
                .from("messages")
                .select()
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value

            // 倒序显示（最新消息在底部）
            messages = response.reversed()

            AppLogger.shared.success("[ChatManager] 加载了 \(messages.count) 条历史消息", category: "Chat")

        } catch {
            errorMessage = "加载消息失败: \(error.localizedDescription)"
            AppLogger.shared.error("[ChatManager] 加载消息失败: \(error)", category: "Chat")
        }

        isLoading = false
    }

    /// 订阅 Realtime 消息
    private func subscribeToRealtime() async {
        AppLogger.shared.info("[ChatManager] 正在订阅 Realtime...", category: "Chat")

        // 创建 channel
        let channel = supabase.realtimeV2.channel("messages-channel")
        realtimeChannel = channel

        // 监听 INSERT 事件
        let insertions = await channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "messages"
        )

        // 启动监听任务
        subscriptionTask = Task { [weak self] in
            for await insertion in insertions {
                await self?.handleNewMessage(insertion)
            }
        }

        // 订阅
        await channel.subscribe()

        isConnected = true
        AppLogger.shared.success("[ChatManager] Realtime 订阅成功", category: "Chat")
    }

    /// 处理新消息
    private func handleNewMessage(_ action: InsertAction) async {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)

                // 尝试多种日期格式
                let formatters: [DateFormatter] = {
                    let formats = [
                        "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ",
                        "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
                        "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
                        "yyyy-MM-dd'T'HH:mm:ss"
                    ]
                    return formats.map { format in
                        let formatter = DateFormatter()
                        formatter.dateFormat = format
                        formatter.locale = Locale(identifier: "en_US_POSIX")
                        return formatter
                    }
                }()

                for formatter in formatters {
                    if let date = formatter.date(from: dateString) {
                        return date
                    }
                }

                // ISO8601 fallback
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = iso.date(from: dateString) {
                    return date
                }

                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "无法解析日期: \(dateString)"
                )
            }

            let message = try action.decodeRecord(decoder: decoder) as Message

            // 检查是否已存在（避免重复）
            guard !messages.contains(where: { $0.id == message.id }) else {
                return
            }

            // 添加到消息列表
            messages.append(message)

            AppLogger.shared.info("[ChatManager] 收到新消息: \(message.content.prefix(20))...", category: "Chat")

            // TODO: 播放提示音和震动

        } catch {
            AppLogger.shared.error("[ChatManager] 解析新消息失败: \(error)", category: "Chat")
        }
    }

    /// 通过 REST API 发送消息（避免 Swift 6 并发问题）
    private func sendMessageViaREST(
        senderId: UUID,
        content: String,
        messageType: MessageType,
        senderName: String?
    ) async throws {

        // 构建请求
        let url = SupabaseConfig.supabaseURL
            .appendingPathComponent("rest/v1/messages")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")

        // 添加认证 token
        if let session = try? await supabase.auth.session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }

        // 构建请求体
        let uploadData = MessageUploadData(
            sender_id: senderId.uuidString,
            content: content,
            message_type: messageType.rawValue,
            sender_name: senderName
        )

        request.httpBody = try JSONEncoder().encode(uploadData)

        // 发送请求
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            AppLogger.shared.error("[ChatManager] REST API 错误: \(httpResponse.statusCode) - \(errorBody)", category: "Chat")
            throw ChatError.serverError(httpResponse.statusCode, errorBody)
        }
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
