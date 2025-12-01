//
//  ChatView.swift
//  tuzi-fuke
//
//  通信系统 - 聊天界面（MVP版本）
//

import SwiftUI

struct ChatView: View {
    @StateObject private var chatManager = ChatManager.shared
    @State private var messageText: String = ""
    @State private var showError: Bool = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 连接状态栏
                connectionStatusBar

                // 消息列表
                messageList

                // 输入栏
                inputBar
            }
            .navigationTitle("广播频道")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        Task {
                            await chatManager.refresh()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(chatManager.isLoading)
                }
            }
        }
        .task {
            await chatManager.start()
        }
        .alert("发送失败", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(chatManager.errorMessage ?? "未知错误")
        }
    }

    // MARK: - 连接状态栏
    private var connectionStatusBar: some View {
        HStack {
            Circle()
                .fill(chatManager.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(chatManager.isConnected ? "实时连接已建立" : "正在连接...")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            if chatManager.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
    }

    // MARK: - 消息列表
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(chatManager.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: chatManager.messages.count) { _, _ in
                // 滚动到最新消息
                if let lastMessage = chatManager.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - 输入栏
    private var inputBar: some View {
        HStack(spacing: 12) {
            // 消息输入框
            TextField("输入消息...", text: $messageText)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit {
                    sendMessage()
                }

            // 发送按钮
            Button(action: sendMessage) {
                Image(systemName: "paperplane.fill")
                    .foregroundColor(.white)
                    .padding(10)
                    .background(messageText.isEmpty ? Color.gray : Color.blue)
                    .clipShape(Circle())
            }
            .disabled(messageText.isEmpty)
        }
        .padding()
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.1), radius: 2, y: -1)
    }

    // MARK: - 发送消息
    private func sendMessage() {
        let content = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        let textToSend = content
        messageText = ""
        isInputFocused = false

        Task {
            do {
                try await chatManager.sendMessage(content: textToSend)
            } catch {
                chatManager.errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - 消息气泡
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

// MARK: - 预览
#Preview {
    ChatView()
}
