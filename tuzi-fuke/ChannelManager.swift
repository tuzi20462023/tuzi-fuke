//
//  ChannelManager.swift
//  tuzi-fuke
//
//  频道管理器 - 管理通讯频道和订阅
//

import Foundation
import Combine
import Supabase

// MARK: - ChannelManager

@MainActor
class ChannelManager: ObservableObject {

    // MARK: - 单例
    static let shared = ChannelManager()

    // MARK: - Published 属性
    @Published var officialChannels: [CommunicationChannel] = []  // 官方频道
    @Published var subscribedChannels: [CommunicationChannel] = []  // 已订阅频道
    @Published var currentChannel: CommunicationChannel?  // 当前选中的频道
    @Published var currentChannelMessages: [ChannelMessage] = []  // 当前频道消息
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - 私有属性
    private let supabase = SupabaseManager.shared.client
    private var realtimeChannel: RealtimeChannelV2?

    // MARK: - 初始化
    private init() {
        print("📡 [ChannelManager] 初始化频道管理器")
    }

    // MARK: - 公开方法

    /// 加载所有官方频道
    func loadOfficialChannels() async {
        isLoading = true
        errorMessage = nil

        do {
            let channels = try await fetchChannelsViaREST(channelType: "official")
            officialChannels = channels
            print("✅ [ChannelManager] 加载了 \(channels.count) 个官方频道")
        } catch {
            errorMessage = "加载频道失败: \(error.localizedDescription)"
            print("❌ [ChannelManager] 加载官方频道失败: \(error)")
        }

        isLoading = false
    }

    /// 加载用户已订阅的频道
    func loadSubscribedChannels() async {
        guard let userId = await SupabaseManager.shared.getCurrentUserId() else {
            print("❌ [ChannelManager] 未登录，无法加载订阅")
            return
        }

        do {
            let subscriptions = try await fetchSubscriptionsViaREST(userId: userId)
            let channelIds = subscriptions.map { $0.channelId }

            // 获取订阅的频道详情
            var channels: [CommunicationChannel] = []
            for channelId in channelIds {
                if let channel = try? await fetchChannelById(channelId) {
                    channels.append(channel)
                }
            }

            // 按频道代码排序，保证所有设备显示顺序一致
            subscribedChannels = channels.sorted { ($0.channelCode ?? "") < ($1.channelCode ?? "") }
            print("✅ [ChannelManager] 加载了 \(channels.count) 个已订阅频道")
        } catch {
            print("❌ [ChannelManager] 加载订阅失败: \(error)")
        }
    }

    /// 订阅频道
    func subscribeToChannel(_ channel: CommunicationChannel) async -> Bool {
        guard let userId = await SupabaseManager.shared.getCurrentUserId() else {
            print("❌ [ChannelManager] 未登录，无法订阅")
            return false
        }

        do {
            try await addSubscriptionViaREST(userId: userId, channelId: channel.id)

            // 更新本地状态
            if !subscribedChannels.contains(where: { $0.id == channel.id }) {
                subscribedChannels.append(channel)
            }

            print("✅ [ChannelManager] 成功订阅频道: \(channel.channelName)")
            return true
        } catch {
            print("❌ [ChannelManager] 订阅频道失败: \(error)")
            return false
        }
    }

    /// 取消订阅频道
    func unsubscribeFromChannel(_ channel: CommunicationChannel) async -> Bool {
        guard let userId = await SupabaseManager.shared.getCurrentUserId() else {
            print("❌ [ChannelManager] 未登录，无法取消订阅")
            return false
        }

        do {
            try await removeSubscriptionViaREST(userId: userId, channelId: channel.id)

            // 更新本地状态
            subscribedChannels.removeAll { $0.id == channel.id }

            // 如果当前频道被取消订阅，清空当前频道
            if currentChannel?.id == channel.id {
                currentChannel = nil
                currentChannelMessages = []
            }

            print("✅ [ChannelManager] 取消订阅频道: \(channel.channelName)")
            return true
        } catch {
            print("❌ [ChannelManager] 取消订阅失败: \(error)")
            return false
        }
    }

    /// 检查是否已订阅某频道
    func isSubscribed(to channel: CommunicationChannel) -> Bool {
        return subscribedChannels.contains { $0.id == channel.id }
    }

    /// 选择当前频道
    func selectChannel(_ channel: CommunicationChannel) async {
        currentChannel = channel
        print("📡 [ChannelManager] 切换到频道: \(channel.channelName)")

        // 加载该频道的消息
        await loadChannelMessages(for: channel)

        // 设置实时订阅
        await setupRealtimeForChannel(channel)
    }

    /// 清除当前频道（切换到广播模式）
    func clearCurrentChannel() {
        currentChannel = nil
        currentChannelMessages = []
        print("📡 [ChannelManager] 切换到公共广播")

        // 取消实时订阅
        Task {
            if let oldChannel = realtimeChannel {
                await oldChannel.unsubscribe()
                realtimeChannel = nil
            }
        }
    }

    /// 加载频道消息
    func loadChannelMessages(for channel: CommunicationChannel) async {
        do {
            let messages = try await fetchMessagesViaREST(channelId: channel.id, limit: 50)
            currentChannelMessages = messages
            print("✅ [ChannelManager] 加载了 \(messages.count) 条频道消息")
        } catch {
            print("❌ [ChannelManager] 加载频道消息失败: \(error)")
        }
    }

    /// 刷新数据
    func refresh() async {
        await loadOfficialChannels()
        await loadSubscribedChannels()
    }

    // MARK: - 实时订阅

    /// 设置频道实时订阅
    private func setupRealtimeForChannel(_ channel: CommunicationChannel) async {
        // 取消之前的订阅
        if let oldChannel = realtimeChannel {
            await oldChannel.unsubscribe()
        }

        // 创建新的实时订阅
        let channelName = "channel_messages:\(channel.id.uuidString)"

        realtimeChannel = await supabase.realtimeV2.channel(channelName)

        guard let rtChannel = realtimeChannel else {
            print("❌ [ChannelManager] 无法创建实时频道")
            return
        }

        let insertions = await rtChannel.postgresChange(
            InsertAction.self,
            table: "channel_messages",
            filter: "channel_id=eq.\(channel.id.uuidString)"
        )

        Task {
            for await insertion in insertions {
                await handleNewMessage(insertion)
            }
        }

        await rtChannel.subscribe()
        print("📡 [ChannelManager] 已订阅频道实时更新: \(channel.channelName)")
    }

    /// 处理新消息
    private func handleNewMessage(_ action: InsertAction) async {
        do {
            let message = try action.decodeRecord(as: ChannelMessage.self, decoder: Self.jsonDecoder)

            // 检查是否是当前频道的消息
            guard let current = currentChannel, message.channelId == current.id else {
                print("📨 [ChannelManager] 收到其他频道消息，忽略")
                return
            }

            // 在主线程上更新 UI
            await MainActor.run {
                // 添加到消息列表（避免重复）
                if !self.currentChannelMessages.contains(where: { $0.id == message.id }) {
                    self.currentChannelMessages.append(message)
                    print("📨 [ChannelManager] 收到新频道消息: \(message.content.prefix(20))...")
                }
            }
        } catch {
            print("❌ [ChannelManager] 解析新消息失败: \(error)")
        }
    }

    // MARK: - REST API 方法

    /// 获取频道列表
    private func fetchChannelsViaREST(channelType: String? = nil) async throws -> [CommunicationChannel] {
        var urlComponents = URLComponents(
            url: SupabaseConfig.supabaseURL.appendingPathComponent("rest/v1/communication_channels"),
            resolvingAgainstBaseURL: false
        )!

        var queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "channel_code.asc")  // 按频道代码排序，保证所有设备显示顺序一致
        ]

        if let type = channelType {
            queryItems.append(URLQueryItem(name: "channel_type", value: "eq.\(type)"))
        }

        urlComponents.queryItems = queryItems

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")

        if let accessToken = try? await supabase.auth.session.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(SupabaseConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ChannelError.fetchFailed
        }

        return try Self.jsonDecoder.decode([CommunicationChannel].self, from: data)
    }

    /// 获取单个频道
    private func fetchChannelById(_ channelId: UUID) async throws -> CommunicationChannel {
        let url = SupabaseConfig.supabaseURL
            .appendingPathComponent("rest/v1/communication_channels")
            .appending(queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "id", value: "eq.\(channelId.uuidString)")
            ])

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")

        if let accessToken = try? await supabase.auth.session.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(SupabaseConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ChannelError.fetchFailed
        }

        let channels = try Self.jsonDecoder.decode([CommunicationChannel].self, from: data)
        guard let channel = channels.first else {
            throw ChannelError.channelNotFound
        }
        return channel
    }

    /// 获取用户订阅
    private func fetchSubscriptionsViaREST(userId: UUID) async throws -> [ChannelSubscription] {
        let url = SupabaseConfig.supabaseURL
            .appendingPathComponent("rest/v1/channel_subscriptions")
            .appending(queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "user_id", value: "eq.\(userId.uuidString)")
            ])

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")

        if let accessToken = try? await supabase.auth.session.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(SupabaseConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ChannelError.fetchFailed
        }

        return try Self.jsonDecoder.decode([ChannelSubscription].self, from: data)
    }

    /// 添加订阅
    private func addSubscriptionViaREST(userId: UUID, channelId: UUID) async throws {
        let url = SupabaseConfig.supabaseURL
            .appendingPathComponent("rest/v1/channel_subscriptions")

        let body: [String: Any] = [
            "user_id": userId.uuidString,
            "channel_id": channelId.uuidString
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        if let accessToken = try? await supabase.auth.session.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(SupabaseConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ChannelError.subscribeFailed
        }
    }

    /// 删除订阅
    private func removeSubscriptionViaREST(userId: UUID, channelId: UUID) async throws {
        let url = SupabaseConfig.supabaseURL
            .appendingPathComponent("rest/v1/channel_subscriptions")
            .appending(queryItems: [
                URLQueryItem(name: "user_id", value: "eq.\(userId.uuidString)"),
                URLQueryItem(name: "channel_id", value: "eq.\(channelId.uuidString)")
            ])

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")

        if let accessToken = try? await supabase.auth.session.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(SupabaseConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ChannelError.unsubscribeFailed
        }
    }

    /// 获取频道消息
    /// 注意：获取最新的N条消息，然后反转顺序以便在UI中按时间升序显示（旧消息在上，新消息在下）
    private func fetchMessagesViaREST(channelId: UUID, limit: Int = 50) async throws -> [ChannelMessage] {
        let url = SupabaseConfig.supabaseURL
            .appendingPathComponent("rest/v1/channel_messages")
            .appending(queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "channel_id", value: "eq.\(channelId.uuidString)"),
                URLQueryItem(name: "order", value: "created_at.desc"),  // 先按时间倒序获取最新的N条
                URLQueryItem(name: "limit", value: "\(limit)")
            ])

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")

        if let accessToken = try? await supabase.auth.session.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(SupabaseConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ChannelError.fetchFailed
        }

        // 解码后反转顺序，让旧消息在前、新消息在后（UI显示：旧的在上面，新的在下面）
        let messages = try Self.jsonDecoder.decode([ChannelMessage].self, from: data)
        return messages.reversed()
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

    /// 解析日期
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

    // MARK: - 调试方法

    func printStatus() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📡 ChannelManager 状态")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("官方频道数量: \(officialChannels.count)")
        print("已订阅频道数量: \(subscribedChannels.count)")
        print("当前频道: \(currentChannel?.channelName ?? "无")")
        print("当前频道消息数: \(currentChannelMessages.count)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}

// MARK: - 错误类型

enum ChannelError: LocalizedError {
    case fetchFailed
    case channelNotFound
    case subscribeFailed
    case unsubscribeFailed
    case notSubscribed

    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "获取频道数据失败"
        case .channelNotFound:
            return "频道不存在"
        case .subscribeFailed:
            return "订阅频道失败"
        case .unsubscribeFailed:
            return "取消订阅失败"
        case .notSubscribed:
            return "未订阅该频道"
        }
    }
}
