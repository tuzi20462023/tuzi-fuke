//
//  DirectChatView.swift
//  tuzi-fuke
//
//  私聊界面 - L5 一对一通讯
//

import SwiftUI

struct DirectChatView: View {
    let recipientId: UUID
    let recipientName: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var messageManager = DirectMessageManager.shared
    @StateObject private var deviceManager = DeviceManager.shared
    @State private var messageText = ""
    @State private var isSending = false
    @State private var showError = false
    @State private var errorText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 顶部导航栏
            navigationBar

            // 通讯状态栏（L4 距离检测）
            communicationStatusBar

            // 消息列表
            messageList

            // 输入栏
            inputBar
        }
        .background(Color(.systemGroupedBackground))
        .task {
            await messageManager.loadMessages(with: recipientId)
        }
        .onDisappear {
            Task {
                await messageManager.stopSubscription()
            }
        }
        .alert("发送失败", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorText)
        }
    }

    // MARK: - 导航栏

    private var navigationBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("返回")
                        .font(.subheadline)
                }
                .foregroundColor(.blue)
            }

            Spacer()

            VStack(spacing: 2) {
                Text(recipientName)
                    .font(.headline)

                if let player = messageManager.nearbyPlayers.first(where: { $0.id == recipientId }) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(player.isOnline ? Color.green : Color.gray)
                            .frame(width: 6, height: 6)
                        Text(player.isOnline ? "在线" : "离线")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // 占位，保持标题居中
            Color.clear.frame(width: 60)
        }
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - 通讯状态栏

    private var communicationStatusBar: some View {
        let (canSend, reason) = messageManager.canCommunicateWith(userId: recipientId)

        return Group {
            if !canSend, let reason = reason {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(reason)
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            } else if let device = deviceManager.activeDevice {
                HStack {
                    Image(systemName: device.deviceType.icon)
                        .foregroundColor(.blue)
                    Text("\(device.displayName) · 通讯范围 \(String(format: "%.0f", device.effectiveRangeKm))km")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color(.systemGray6))
            }
        }
    }

    // MARK: - 消息列表

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if messageManager.currentMessages.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(messageManager.currentMessages) { message in
                            DirectMessageBubble(
                                message: message,
                                recipientId: recipientId
                            )
                            .id(message.id)
                        }
                    }
                }
                .padding()
            }
            .onChange(of: messageManager.currentMessages.count) { _, _ in
                if let lastMessage = messageManager.currentMessages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isInputFocused = false
        }
    }

    // MARK: - 空状态

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "message.and.waveform")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            Text("开始对话")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("向 \(recipientName) 发送第一条消息")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    // MARK: - 输入栏

    private var inputBar: some View {
        let (canSend, _) = messageManager.canCommunicateWith(userId: recipientId)

        return HStack(spacing: 12) {
            TextField("输入消息...", text: $messageText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .disabled(!canSend)

            Button {
                sendMessage()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.title2)
                    .foregroundColor(canSendButton ? .blue : .gray)
            }
            .disabled(!canSendButton)
        }
        .padding()
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.05), radius: 2, y: -1)
    }

    private var canSendButton: Bool {
        let (canSend, _) = messageManager.canCommunicateWith(userId: recipientId)
        return canSend && !messageText.isEmpty && !isSending
    }

    // MARK: - 发送消息

    private func sendMessage() {
        guard !messageText.isEmpty else { return }

        let content = messageText
        messageText = ""
        isSending = true
        isInputFocused = false

        Task {
            do {
                try await messageManager.sendMessage(to: recipientId, content: content)
            } catch {
                errorText = error.localizedDescription
                showError = true
                messageText = content  // 恢复消息
            }
            isSending = false
        }
    }
}

// MARK: - 私聊消息气泡

struct DirectMessageBubble: View {
    let message: DirectMessage
    let recipientId: UUID

    @State private var currentUserId: UUID?

    private var isSentByMe: Bool {
        guard let currentUserId = currentUserId else { return false }
        return message.senderId == currentUserId
    }

    var body: some View {
        HStack {
            if isSentByMe {
                Spacer(minLength: 60)
            }

            VStack(alignment: isSentByMe ? .trailing : .leading, spacing: 4) {
                // 消息内容
                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isSentByMe ? Color.blue : Color(.systemGray5))
                    .foregroundColor(isSentByMe ? .white : .primary)
                    .cornerRadius(18)

                // 时间和距离
                HStack(spacing: 6) {
                    Text(message.formattedTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if let distanceText = message.distanceText {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(distanceText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if !isSentByMe {
                Spacer(minLength: 60)
            }
        }
        .task {
            currentUserId = await SupabaseManager.shared.getCurrentUserId()
        }
    }
}

// MARK: - 预览

#Preview {
    DirectChatView(recipientId: UUID(), recipientName: "幸存者-001")
}
