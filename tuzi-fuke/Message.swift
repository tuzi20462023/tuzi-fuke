//
//  Message.swift
//  tuzi-fuke
//
//  通信系统 - 消息数据模型（MVP版本）
//

import Foundation

// MARK: - 消息类型
enum MessageType: String, Codable, CaseIterable {
    case broadcast = "broadcast"    // 广播消息（所有人可见）
    case system = "system"          // 系统消息

    var displayName: String {
        switch self {
        case .broadcast: return "广播"
        case .system: return "系统"
        }
    }

    var icon: String {
        switch self {
        case .broadcast: return "megaphone.fill"
        case .system: return "info.circle.fill"
        }
    }
}

// MARK: - 消息模型
struct Message: Codable, Identifiable, Equatable {
    let id: UUID
    let senderId: UUID
    let content: String
    let messageType: MessageType
    let senderName: String?
    let createdAt: Date

    // MARK: - CodingKeys（匹配数据库字段）
    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case content
        case messageType = "message_type"
        case senderName = "sender_name"
        case createdAt = "created_at"
    }

    // MARK: - 计算属性

    /// 是否是系统消息
    var isSystemMessage: Bool {
        messageType == .system
    }

    /// 发送者显示名称
    var displaySenderName: String {
        if isSystemMessage {
            return "系统"
        }
        return senderName ?? "匿名幸存者"
    }

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

    // MARK: - Equatable
    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id
    }
}

