//
//  ChatView.swift
//  tuzi-fuke
//
//  通信系统 - 聊天界面（MVP版本）
//

import SwiftUI

struct ChatView: View {
    @StateObject private var chatManager = ChatManager.shared
    @StateObject private var deviceManager = DeviceManager.shared
    @State private var messageText: String = ""
    @State private var showError: Bool = false
    @State private var showDeviceStore: Bool = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 连接状态栏
                connectionStatusBar

                // 设备状态栏
                deviceStatusBar

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
            await deviceManager.loadDevices()
            await chatManager.start()
        }
        .alert("发送失败", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(chatManager.errorMessage ?? "未知错误")
        }
        .sheet(isPresented: $showDeviceStore) {
            DeviceStoreView()
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

    // MARK: - 设备状态栏
    private var deviceStatusBar: some View {
        HStack(spacing: 8) {
            if let device = deviceManager.activeDevice {
                // 设备图标
                Image(systemName: device.deviceType.icon)
                    .foregroundColor(device.canSend ? .blue : .orange)

                // 设备名称
                Text(device.displayName)
                    .font(.caption)
                    .fontWeight(.medium)

                // 发送能力指示
                if device.canSend {
                    Text("可收发")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                } else {
                    Text("仅接收")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                }

                Spacer()

                // 电池状态
                HStack(spacing: 2) {
                    Image(systemName: batteryIcon(level: device.batteryLevel))
                        .foregroundColor(batteryColor(level: device.batteryLevel))
                    Text("\(Int(device.batteryLevel))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // 升级按钮
                Button {
                    showDeviceStore = true
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(.blue)
                }
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .foregroundColor(.red)
                Text("无通讯设备")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()

                // 购买设备按钮
                Button {
                    showDeviceStore = true
                } label: {
                    Text("购买设备")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(.systemGray6).opacity(0.5))
    }

    // 电池图标
    private func batteryIcon(level: Double) -> String {
        switch level {
        case 75...100: return "battery.100"
        case 50..<75: return "battery.75"
        case 25..<50: return "battery.50"
        case 1..<25: return "battery.25"
        default: return "battery.0"
        }
    }

    // 电池颜色
    private func batteryColor(level: Double) -> Color {
        switch level {
        case 50...100: return .green
        case 20..<50: return .yellow
        default: return .red
        }
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
        VStack(spacing: 0) {
            // 设备不能发送时的提示
            if !deviceManager.canSendMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(deviceManager.cannotSendReason ?? "当前设备无法发送消息")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            }

            HStack(spacing: 12) {
                // 消息输入框
                TextField(deviceManager.canSendMessage ? "输入消息..." : "仅接收模式", text: $messageText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        sendMessage()
                    }
                    .disabled(!deviceManager.canSendMessage)

                // 发送按钮
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                        .padding(10)
                        .background(canSend ? Color.blue : Color.gray)
                        .clipShape(Circle())
                }
                .disabled(!canSend)
            }
            .padding()
            .background(Color(.systemBackground))
            .shadow(color: .black.opacity(0.1), radius: 2, y: -1)
        }
    }

    // 是否可以发送
    private var canSend: Bool {
        return !messageText.isEmpty && deviceManager.canSendMessage
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
