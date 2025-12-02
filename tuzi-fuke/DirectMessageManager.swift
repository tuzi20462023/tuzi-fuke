//
//  DirectMessageManager.swift
//  tuzi-fuke
//
//  私聊消息管理器 - L5 私聊功能核心
//

import Foundation
import Supabase
import CoreLocation

// MARK: - DirectMessageManager

@MainActor
class DirectMessageManager: ObservableObject {

    // MARK: - 单例
    static let shared = DirectMessageManager()

    // MARK: - Published 属性
    @Published var conversations: [ConversationUser] = []       // 对话列表
    @Published var currentMessages: [DirectMessage] = []        // 当前对话消息
    @Published var nearbyPlayers: [NearbyPlayer] = []           // 附近玩家
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - 私有属性
    private let supabase = SupabaseManager.shared.client
    private var realtimeChannel: RealtimeChannelV2?
    private var messageTask: Task<Void, Never>?
    private var currentConversationUserId: UUID?

    // MARK: - 初始化
    private init() {
        print("💬 [DirectMessageManager] 初始化完成")
    }

    // MARK: - 公开方法

    /// 加载对话列表
    func loadConversations() async {
        guard let userId = await SupabaseManager.shared.getCurrentUserId() else {
            print("❌ [DirectMessageManager] 未登录")
            return
        }

        isLoading = true

        do {
            let conversations = try await fetchConversationsViaREST(userId: userId)
            self.conversations = conversations
            print("✅ [DirectMessageManager] 加载了 \(conversations.count) 个对话")
        } catch {
            errorMessage = "加载对话失败: \(error.localizedDescription)"
            print("❌ [DirectMessageManager] 加载对话失败: \(error)")
        }

        isLoading = false
    }

    /// 加载与某用户的私聊消息
    func loadMessages(with userId: UUID) async {
        guard let currentUserId = await SupabaseManager.shared.getCurrentUserId() else {
            print("❌ [DirectMessageManager] 未登录")
            return
        }

        currentConversationUserId = userId
        isLoading = true

        do {
            let messages = try await fetchMessagesViaREST(currentUserId: currentUserId, otherUserId: userId)
            currentMessages = messages
            print("✅ [DirectMessageManager] 加载了 \(messages.count) 条私聊消息")

            // 标记消息为已读
            await markMessagesAsRead(from: userId)

            // 订阅实时消息
            await subscribeToDirectMessages(currentUserId: currentUserId, otherUserId: userId)
        } catch {
            errorMessage = "加载消息失败: \(error.localizedDescription)"
            print("❌ [DirectMessageManager] 加载消息失败: \(error)")
        }

        isLoading = false
    }

    /// 发送私聊消息
    func sendMessage(to recipientId: UUID, content: String) async throws {
        guard let senderId = await SupabaseManager.shared.getCurrentUserId() else {
            throw DirectMessageError.notAuthenticated
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DirectMessageError.emptyMessage
        }

        // 检查设备是否可以发送
        let deviceManager = DeviceManager.shared
        guard deviceManager.canSendMessage else {
            throw DirectMessageError.deviceCannotSend(deviceManager.cannotSendReason ?? "设备无法发送")
        }

        // 获取当前位置
        let location = LocationManager.shared.location
        let lat = location?.coordinate.latitude
        let lon = location?.coordinate.longitude

        // 获取设备类型
        let deviceType = deviceManager.activeDevice?.deviceType.rawValue ?? "radio"

        print("💬 [DirectMessageManager] 发送私聊消息到 \(recipientId)")

        // 乐观更新
        let tempId = UUID()
        let optimisticMessage = DirectMessage(
            id: tempId,
            senderId: senderId,
            recipientId: recipientId,
            content: content,
            deviceType: deviceType,
            senderLat: lat,
            senderLon: lon,
            distanceKm: nil,
            isRead: false,
            createdAt: Date()
        )
        currentMessages.append(optimisticMessage)

        do {
            try await sendMessageViaREST(
                senderId: senderId,
                recipientId: recipientId,
                content: content,
                deviceType: deviceType,
                lat: lat,
                lon: lon
            )
            print("✅ [DirectMessageManager] 私聊消息发送成功")
        } catch {
            // 移除乐观更新
            currentMessages.removeAll { $0.id == tempId }
            throw error
        }
    }

    /// 加载附近玩家（用于选择私聊对象）
    func loadNearbyPlayers(rangeKm: Double = 100) async {
        guard let userId = await SupabaseManager.shared.getCurrentUserId() else {
            print("❌ [DirectMessageManager] 未登录")
            return
        }

        guard let location = LocationManager.shared.location else {
            print("❌ [DirectMessageManager] 位置未知")
            return
        }

        do {
            let players = try await fetchNearbyPlayersViaREST(
                userId: userId,
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                rangeKm: rangeKm
            )
            nearbyPlayers = players
            print("✅ [DirectMessageManager] 找到 \(players.count) 个附近玩家")
        } catch {
            print("❌ [DirectMessageManager] 加载附近玩家失败: \(error)")
        }
    }

    /// 检查是否可以与目标用户通讯（L4 距离检测）
    func canCommunicateWith(userId: UUID) -> (canSend: Bool, reason: String?) {
        let deviceManager = DeviceManager.shared

        // 检查设备
        guard let device = deviceManager.activeDevice else {
            return (false, "没有通讯设备")
        }

        guard device.canSend else {
            return (false, "当前设备只能接收，无法发送")
        }

        // 找到目标玩家
        if let player = nearbyPlayers.first(where: { $0.id == userId }) {
            let deviceRange = device.effectiveRangeKm

            if player.distanceKm > deviceRange {
                return (false, "目标超出通讯范围（\(String(format: "%.1f", player.distanceKm))km > \(String(format: "%.0f", deviceRange))km）")
            }
        }

        return (true, nil)
    }

    /// 停止实时订阅
    func stopSubscription() async {
        messageTask?.cancel()
        messageTask = nil

        if let channel = realtimeChannel {
            await channel.unsubscribe()
            realtimeChannel = nil
        }

        currentConversationUserId = nil
        print("💬 [DirectMessageManager] 已停止订阅")
    }

    // MARK: - 私有方法

    /// 获取对话列表
    private func fetchConversationsViaREST(userId: UUID) async throws -> [ConversationUser] {
        // 获取所有私聊消息中涉及的用户
        let url = SupabaseConfig.supabaseURL
            .appendingPathComponent("rest/v1/direct_messages")
            .appending(queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "or", value: "(sender_id.eq.\(userId.uuidString),recipient_id.eq.\(userId.uuidString))"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ])

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")

        if let accessToken = try? await supabase.auth.session.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw DirectMessageError.fetchFailed
        }

        let messages = try Self.jsonDecoder.decode([DirectMessage].self, from: data)

        // 按对话用户分组
        var userMessages: [UUID: [DirectMessage]] = [:]
        for message in messages {
            let otherUserId = message.senderId == userId ? message.recipientId : message.senderId
            if userMessages[otherUserId] == nil {
                userMessages[otherUserId] = []
            }
            userMessages[otherUserId]?.append(message)
        }

        // 构建对话列表
        var conversations: [ConversationUser] = []
        for (otherUserId, msgs) in userMessages {
            let lastMsg = msgs.first
            let unreadCount = msgs.filter { $0.senderId == otherUserId && !$0.isRead }.count

            let conversation = ConversationUser(
                id: otherUserId,
                username: "幸存者",  // 暂时使用默认名称，后续可以从profiles表获取
                callsign: nil,
                lastMessage: lastMsg?.content,
                lastMessageTime: lastMsg?.createdAt,
                unreadCount: unreadCount,
                distanceKm: nil
            )
            conversations.append(conversation)
        }

        // 按最后消息时间排序
        return conversations.sorted {
            ($0.lastMessageTime ?? .distantPast) > ($1.lastMessageTime ?? .distantPast)
        }
    }

    /// 获取与某用户的消息
    private func fetchMessagesViaREST(currentUserId: UUID, otherUserId: UUID) async throws -> [DirectMessage] {
        let url = SupabaseConfig.supabaseURL
            .appendingPathComponent("rest/v1/direct_messages")
            .appending(queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "or", value: "(and(sender_id.eq.\(currentUserId.uuidString),recipient_id.eq.\(otherUserId.uuidString)),and(sender_id.eq.\(otherUserId.uuidString),recipient_id.eq.\(currentUserId.uuidString)))"),
                URLQueryItem(name: "order", value: "created_at.asc"),
                URLQueryItem(name: "limit", value: "100")
            ])

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")

        if let accessToken = try? await supabase.auth.session.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw DirectMessageError.fetchFailed
        }

        return try Self.jsonDecoder.decode([DirectMessage].self, from: data)
    }

    /// 发送消息
    private func sendMessageViaREST(
        senderId: UUID,
        recipientId: UUID,
        content: String,
        deviceType: String,
        lat: Double?,
        lon: Double?
    ) async throws {
        let url = SupabaseConfig.supabaseURL
            .appendingPathComponent("rest/v1/direct_messages")

        var body: [String: Any] = [
            "sender_id": senderId.uuidString,
            "recipient_id": recipientId.uuidString,
            "content": content,
            "device_type": deviceType
        ]

        if let lat = lat {
            body["sender_lat"] = lat
        }
        if let lon = lon {
            body["sender_lon"] = lon
        }

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        if let accessToken = try? await supabase.auth.session.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw DirectMessageError.sendFailed
        }
    }

    /// 获取附近玩家
    private func fetchNearbyPlayersViaREST(userId: UUID, lat: Double, lon: Double, rangeKm: Double) async throws -> [NearbyPlayer] {
        // 使用 RPC 函数获取附近玩家（需要数据库支持）
        // 暂时返回空数组，等数据库函数创建后启用
        print("💬 [DirectMessageManager] 附近玩家功能需要数据库RPC支持")
        return []
    }

    /// 标记消息为已读
    private func markMessagesAsRead(from senderId: UUID) async {
        guard let currentUserId = await SupabaseManager.shared.getCurrentUserId() else { return }

        let url = SupabaseConfig.supabaseURL
            .appendingPathComponent("rest/v1/direct_messages")
            .appending(queryItems: [
                URLQueryItem(name: "sender_id", value: "eq.\(senderId.uuidString)"),
                URLQueryItem(name: "recipient_id", value: "eq.\(currentUserId.uuidString)"),
                URLQueryItem(name: "is_read", value: "eq.false")
            ])

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["is_read": true])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")

        if let accessToken = try? await supabase.auth.session.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        _ = try? await URLSession.shared.data(for: request)
        print("💬 [DirectMessageManager] 已标记消息为已读")
    }

    /// 订阅实时私聊消息
    private func subscribeToDirectMessages(currentUserId: UUID, otherUserId: UUID) async {
        // 取消之前的订阅
        await stopSubscription()

        let channelName = "direct_messages:\(currentUserId.uuidString)"
        realtimeChannel = await supabase.realtimeV2.channel(channelName)

        guard let channel = realtimeChannel else {
            print("❌ [DirectMessageManager] 无法创建实时频道")
            return
        }

        // 监听新消息
        let insertions = await channel.postgresChange(
            InsertAction.self,
            table: "direct_messages"
        )

        messageTask = Task { [weak self] in
            for await insertion in insertions {
                await self?.handleNewMessage(insertion, currentUserId: currentUserId, otherUserId: otherUserId)
            }
        }

        await channel.subscribe()
        print("💬 [DirectMessageManager] 已订阅私聊消息实时更新")
    }

    /// 处理新消息
    private func handleNewMessage(_ action: InsertAction, currentUserId: UUID, otherUserId: UUID) async {
        do {
            let message = try action.decodeRecord(as: DirectMessage.self, decoder: Self.jsonDecoder)

            // 检查是否是当前对话的消息
            let isRelevant = (message.senderId == currentUserId && message.recipientId == otherUserId) ||
                             (message.senderId == otherUserId && message.recipientId == currentUserId)

            guard isRelevant else { return }

            // 避免重复
            guard !currentMessages.contains(where: { $0.id == message.id }) else { return }

            await MainActor.run {
                self.currentMessages.append(message)
                print("💬 [DirectMessageManager] 收到新私聊消息")
            }
        } catch {
            print("❌ [DirectMessageManager] 解析新消息失败: \(error)")
        }
    }

    // MARK: - JSON 解码器

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            return parseDate(dateString) ?? Date()
        }
        return decoder
    }()

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

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: dateString)
    }
}

// MARK: - 错误类型

enum DirectMessageError: LocalizedError {
    case notAuthenticated
    case emptyMessage
    case fetchFailed
    case sendFailed
    case deviceCannotSend(String)
    case outOfRange(distanceKm: Double, maxRangeKm: Double)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "请先登录"
        case .emptyMessage:
            return "消息内容不能为空"
        case .fetchFailed:
            return "获取消息失败"
        case .sendFailed:
            return "发送消息失败"
        case .deviceCannotSend(let reason):
            return reason
        case .outOfRange(let distance, let maxRange):
            return "目标超出通讯范围（\(String(format: "%.1f", distance))km > \(String(format: "%.0f", maxRange))km）"
        }
    }
}
