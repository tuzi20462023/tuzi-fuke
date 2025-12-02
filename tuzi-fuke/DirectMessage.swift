//
//  DirectMessage.swift
//  tuzi-fuke
//
//  私聊消息数据模型
//

import Foundation

// MARK: - 私聊消息模型

struct DirectMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let senderId: UUID
    let recipientId: UUID
    let content: String
    let deviceType: String          // 发送者设备类型
    let senderLat: Double?          // 发送者位置（用于L4距离计算）
    let senderLon: Double?
    let distanceKm: Double?         // 与接收者的距离
    let isRead: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case recipientId = "recipient_id"
        case content
        case deviceType = "device_type"
        case senderLat = "sender_lat"
        case senderLon = "sender_lon"
        case distanceKm = "distance_km"
        case isRead = "is_read"
        case createdAt = "created_at"
    }

    // MARK: - 计算属性

    /// 格式化的时间显示
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

    /// 距离显示文本
    var distanceText: String? {
        guard let distance = distanceKm else { return nil }
        if distance < 1 {
            return String(format: "%.0f m", distance * 1000)
        } else {
            return String(format: "%.1f km", distance)
        }
    }

    // MARK: - Equatable

    static func == (lhs: DirectMessage, rhs: DirectMessage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - 对话用户模型（用于私聊列表）

struct ConversationUser: Identifiable, Equatable {
    let id: UUID                    // 用户ID
    let username: String            // 用户名
    let callsign: String?           // 呼号
    var lastMessage: String?        // 最后一条消息
    var lastMessageTime: Date?      // 最后消息时间
    var unreadCount: Int            // 未读消息数
    var distanceKm: Double?         // 与当前用户的距离

    var displayName: String {
        callsign ?? username
    }

    var formattedLastTime: String? {
        guard let time = lastMessageTime else { return nil }
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(time) {
            formatter.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(time) {
            return "昨天"
        } else {
            formatter.dateFormat = "MM/dd"
        }

        return formatter.string(from: time)
    }

    /// 距离显示
    var distanceText: String? {
        guard let distance = distanceKm else { return nil }
        if distance < 1 {
            return String(format: "%.0f m", distance * 1000)
        } else {
            return String(format: "%.1f km", distance)
        }
    }

    /// 是否在通讯范围内（根据设备判断）
    func isInRange(deviceRangeKm: Double) -> Bool {
        guard let distance = distanceKm else { return false }
        return distance <= deviceRangeKm
    }
}

// MARK: - 附近玩家模型（用于选择私聊对象）

struct NearbyPlayer: Identifiable, Codable {
    let id: UUID
    let username: String
    let callsign: String?
    let distanceKm: Double
    let lastSeenAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case callsign
        case distanceKm = "distance_km"
        case lastSeenAt = "last_seen_at"
    }

    var displayName: String {
        callsign ?? username
    }

    var distanceText: String {
        if distanceKm < 1 {
            return String(format: "%.0f m", distanceKm * 1000)
        } else {
            return String(format: "%.1f km", distanceKm)
        }
    }

    var isOnline: Bool {
        guard let lastSeen = lastSeenAt else { return false }
        // 5分钟内算在线
        return Date().timeIntervalSince(lastSeen) < 300
    }
}
