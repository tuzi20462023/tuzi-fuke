//
//  CommunicationChannel.swift
//  tuzi-fuke
//
//  通讯频道数据模型
//

import Foundation

// MARK: - 频道类型
enum ChannelType: String, Codable, CaseIterable {
    case official = "official"  // 官方频道（系统预设）
    case `public` = "public"    // 公开频道（用户创建）
    case `private` = "private"  // 私密频道（需要邀请）

    var displayName: String {
        switch self {
        case .official: return "官方频道"
        case .public: return "公开频道"
        case .private: return "私密频道"
        }
    }

    var icon: String {
        switch self {
        case .official: return "megaphone.fill"
        case .public: return "antenna.radiowaves.left.and.right"
        case .private: return "lock.fill"
        }
    }
}

// MARK: - 通讯频道模型
struct CommunicationChannel: Codable, Identifiable, Equatable {
    let id: UUID
    let channelName: String
    let channelCode: String?
    let channelType: ChannelType
    let ownerId: UUID?
    let isPublic: Bool
    let requiresApproval: Bool
    let rangeKm: Double?
    let description: String?
    let icon: String?
    let subscriberCount: Int
    let messageCount: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case channelName = "channel_name"
        case channelCode = "channel_code"
        case channelType = "channel_type"
        case ownerId = "owner_id"
        case isPublic = "is_public"
        case requiresApproval = "requires_approval"
        case rangeKm = "range_km"
        case description
        case icon
        case subscriberCount = "subscriber_count"
        case messageCount = "message_count"
        case createdAt = "created_at"
    }

    // MARK: - 计算属性

    /// 是否是官方频道
    var isOfficial: Bool {
        channelType == .official
    }

    /// 显示图标
    var displayIcon: String {
        icon ?? channelType.icon
    }

    /// 频道类型显示名称
    var typeDisplayName: String {
        channelType.displayName
    }

    // MARK: - Equatable
    static func == (lhs: CommunicationChannel, rhs: CommunicationChannel) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - 频道消息模型
struct ChannelMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let channelId: UUID
    let senderId: UUID?
    let senderName: String?
    let content: String
    let messageType: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case channelId = "channel_id"
        case senderId = "sender_id"
        case senderName = "sender_name"
        case content
        case messageType = "message_type"
        case createdAt = "created_at"
    }

    // MARK: - 计算属性

    /// 发送者显示名称
    var displaySenderName: String {
        if messageType == "system" {
            return "系统广播"
        }
        return senderName ?? "匿名幸存者"
    }

    /// 是否是系统消息
    var isSystemMessage: Bool {
        messageType == "system"
    }

    /// 格式化时间
    var formattedTime: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(createdAt) {
            formatter.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(createdAt) {
            formatter.dateFormat = "'昨天' HH:mm"
        } else {
            formatter.dateFormat = "MM/dd HH:mm"
        }

        return formatter.string(from: createdAt)
    }

    // MARK: - Equatable
    static func == (lhs: ChannelMessage, rhs: ChannelMessage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - 频道订阅模型
struct ChannelSubscription: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let channelId: UUID
    let subscribedAt: Date
    let isMuted: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case channelId = "channel_id"
        case subscribedAt = "subscribed_at"
        case isMuted = "is_muted"
    }
}
