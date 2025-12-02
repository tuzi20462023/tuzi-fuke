//
//  CommsMessageView.swift
//  tuzi-fuke
//
//  通讯终端 - 消息面板
//  专注于消息展示与发送
//

import SwiftUI

struct CommsMessageView: View {
    @StateObject private var chatManager = ChatManager.shared
    @StateObject private var deviceManager = DeviceManager.shared
    @StateObject private var channelManager = ChannelManager.shared
    
    @State private var messageText: String = ""
    @State private var showError: Bool = false
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部状态条 (频道名 + 连接状态)
            headerBar
            
            // 2. 消息列表
            messageList
            
            // 3. 底部输入区
            inputBar
        }
        .onTapGesture {
            isInputFocused = false
        }
        .alert("发送失败", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(chatManager.errorMessage ?? "未知错误")
        }
        .task {
            // 确保数据加载
            if chatManager.messages.isEmpty && channelManager.currentChannel == nil {
                await chatManager.start()
            }
        }
    }
    
    // MARK: - 顶部信息栏
    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(currentChannelName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(chatManager.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                        .shadow(color: chatManager.isConnected ? .green.opacity(0.5) : .clear, radius: 2)
                    
                    Text(chatManager.isConnected ? "信号稳定" : "正在连接...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // 刷新按钮
            Button {
                Task { await chatManager.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .disabled(chatManager.isLoading)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.systemGray5)),
            alignment: .bottom
        )
    }
    
    // MARK: - 消息列表
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    // 顶部留白
                    Color.clear.frame(height: 8)
                    
                    if channelManager.currentChannel != nil {
                        // 频道消息
                        ForEach(channelManager.currentChannelMessages) { message in
                            ChannelMessageBubble(message: message)
                                .id(message.id)
                        }
                    } else {
                        // 广播消息
                        ForEach(chatManager.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    
                    // 底部留白，避免被输入框遮挡
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal)
            }
            .background(Color(.systemGroupedBackground)) // 稍微深一点的背景
            .onChange(of: chatManager.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: channelManager.currentChannelMessages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }
    
    // MARK: - 底部输入栏
    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
            
            VStack(spacing: 8) {
                // 状态提示 (只读/错误)
                if isInOfficialChannel {
                    statusBanner(icon: "speaker.slash.fill", text: "官方频道仅供收听", color: .blue)
                } else if !deviceManager.canSendMessage {
                    statusBanner(icon: "exclamationmark.triangle.fill", text: deviceManager.cannotSendReason ?? "设备仅支持接收", color: .orange)
                }
                
                // 输入框区域
                HStack(spacing: 12) {
                    TextField(inputPlaceholder, text: $messageText)
                        .padding(10)
                        .background(Color(.systemGray6))
                        .cornerRadius(20)
                        .focused($isInputFocused)
                        .submitLabel(.send)
                        .disabled(isInOfficialChannel || !deviceManager.canSendMessage)
                        .onSubmit(sendMessage)
                    
                    Button(action: sendMessage) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(canSend ? Color.blue : Color.gray)
                                    .shadow(color: canSend ? .blue.opacity(0.3) : .clear, radius: 3, y: 2)
                            )
                    }
                    .disabled(!canSend)
                }
            }
            .padding(12)
            .background(Color(.systemBackground))
        }
    }
    
    // MARK: - 辅助视图
    
    private func statusBanner(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .foregroundColor(color)
        .cornerRadius(8)
    }
    
    // MARK: - 逻辑处理
    
    private var currentChannelName: String {
        channelManager.currentChannel?.channelName ?? "公共广播"
    }
    
    private var canSend: Bool {
        if let channel = channelManager.currentChannel, channel.isOfficial { return false }
        return !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && deviceManager.canSendMessage
    }
    
    private var isInOfficialChannel: Bool {
        channelManager.currentChannel?.isOfficial == true
    }
    
    private var inputPlaceholder: String {
        if isInOfficialChannel { return "当前频道无法发送消息" }
        if !deviceManager.canSendMessage { return "升级设备以发送消息" }
        return "发送消息..."
    }
    
    private func sendMessage() {
        let content = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        
        messageText = ""
        isInputFocused = false
        
        Task {
            do {
                try await chatManager.sendMessage(content: content)
            } catch {
                chatManager.errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if channelManager.currentChannel == nil {
            if let last = chatManager.messages.last {
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        } else {
            if let last = channelManager.currentChannelMessages.last {
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}
