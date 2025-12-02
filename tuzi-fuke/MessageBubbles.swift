//
//  MessageBubbles.swift
//  tuzi-fuke
//
//  消息气泡组件
//

import SwiftUI

// MARK: - 广播消息气泡
struct MessageBubble: View {
    let message: Message
    @State private var currentUserId: UUID?

    private var isOwnMessage: Bool {
        guard let currentUserId = currentUserId else { return false }
        return message.senderId == currentUserId
    }

    var body: some View {
        HStack {
            if isOwnMessage {
                Spacer(minLength: 60)
            }

            VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 4) {
                // 发送者名称
                if !isOwnMessage {
                    HStack(spacing: 4) {
                        Image(systemName: message.messageType.icon)
                            .font(.caption2)
                        Text(message.displaySenderName)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.secondary)
                }

                // 消息内容
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        isOwnMessage
                            ? Color.blue
                            : (message.isSystemMessage ? Color.orange.opacity(0.2) : Color(.systemGray5))
                    )
                    .foregroundColor(isOwnMessage ? .white : .primary)
                    .cornerRadius(16)

                // 时间戳
                Text(message.formattedTime)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !isOwnMessage {
                Spacer(minLength: 60)
            }
        }
        .task {
            currentUserId = await SupabaseManager.shared.getCurrentUserId()
        }
    }
}

// MARK: - 频道消息气泡
struct ChannelMessageBubble: View {
    let message: ChannelMessage

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            // 系统消息居中显示
            if message.isSystemMessage {
                VStack(spacing: 4) {
                    // 时间（移到最上面）
                    Text(message.formattedTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    // 系统广播标签
                    HStack(spacing: 4) {
                        Image(systemName: "megaphone.fill")
                            .font(.caption2)
                        Text("系统广播")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.orange)

                    // 消息内容
                    Text(message.content)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            } else {
                // 普通用户消息左对齐
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        // 时间（移到最上面）
                        Text(message.formattedTime)
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        // 发送者名称
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                                .font(.caption2)
                            Text(message.displaySenderName)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.secondary)

                        // 消息内容
                        Text(message.content)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(16)
                    }
                    Spacer(minLength: 60)
                }
            }
        }
    }
}
