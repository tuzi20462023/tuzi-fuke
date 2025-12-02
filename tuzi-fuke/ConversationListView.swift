//
//  ConversationListView.swift
//  tuzi-fuke
//
//  私聊列表界面 - 显示所有对话
//

import SwiftUI

struct ConversationListView: View {
    @StateObject private var messageManager = DirectMessageManager.shared
    @StateObject private var deviceManager = DeviceManager.shared
    @State private var showNearbyPlayers = false

    var body: some View {
        VStack(spacing: 0) {
            // 设备状态提示
            deviceStatusBar

            // 对话列表
            if messageManager.isLoading {
                loadingView
            } else if messageManager.conversations.isEmpty {
                emptyStateView
            } else {
                conversationList
            }
        }
        .navigationTitle("私聊")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNearbyPlayers = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
        }
        .task {
            await messageManager.loadConversations()
        }
        .sheet(isPresented: $showNearbyPlayers) {
            NearbyPlayersView()
        }
    }

    // MARK: - 设备状态栏

    private var deviceStatusBar: some View {
        Group {
            if let device = deviceManager.activeDevice {
                HStack {
                    Image(systemName: device.deviceType.icon)
                        .foregroundColor(device.canSend ? .blue : .orange)

                    if device.canSend {
                        Text("通讯范围: \(String(format: "%.0f", device.effectiveRangeKm))km")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("当前设备仅能接收，无法发送私聊")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
            }
        }
    }

    // MARK: - 对话列表

    private var conversationList: some View {
        List {
            ForEach(messageManager.conversations) { conversation in
                NavigationLink {
                    DirectChatView(
                        recipientId: conversation.id,
                        recipientName: conversation.displayName
                    )
                } label: {
                    ConversationRow(conversation: conversation)
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await messageManager.loadConversations()
        }
    }

    // MARK: - 加载中

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("加载中...")
            Spacer()
        }
    }

    // MARK: - 空状态

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "message.badge.waveform")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("还没有私聊记录")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("点击右上角按钮\n查找附近的幸存者开始对话")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showNearbyPlayers = true
            } label: {
                HStack {
                    Image(systemName: "person.badge.plus")
                    Text("查找附近幸存者")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - 对话行

struct ConversationRow: View {
    let conversation: ConversationUser
    @StateObject private var deviceManager = DeviceManager.shared

    var body: some View {
        HStack(spacing: 12) {
            // 头像
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 50, height: 50)

                Text(conversation.displayName.prefix(1).uppercased())
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    if let distanceText = conversation.distanceText {
                        Text("· \(distanceText)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let lastMessage = conversation.lastMessage {
                    Text(lastMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 右侧信息
            VStack(alignment: .trailing, spacing: 4) {
                if let timeText = conversation.formattedLastTime {
                    Text(timeText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if conversation.unreadCount > 0 {
                    Text("\(conversation.unreadCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 附近玩家视图

struct NearbyPlayersView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var messageManager = DirectMessageManager.shared
    @StateObject private var deviceManager = DeviceManager.shared
    @State private var selectedPlayer: NearbyPlayer?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 范围说明
                rangeInfoBar

                // 玩家列表
                if messageManager.nearbyPlayers.isEmpty {
                    emptyStateView
                } else {
                    playerList
                }
            }
            .navigationTitle("附近幸存者")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await messageManager.loadNearbyPlayers()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                await messageManager.loadNearbyPlayers()
            }
        }
        .sheet(item: $selectedPlayer) { player in
            NavigationView {
                DirectChatView(
                    recipientId: player.id,
                    recipientName: player.displayName
                )
            }
        }
    }

    // MARK: - 范围说明

    private var rangeInfoBar: some View {
        Group {
            if let device = deviceManager.activeDevice {
                HStack {
                    Image(systemName: device.deviceType.icon)
                        .foregroundColor(.blue)

                    Text("当前设备可通讯范围: \(String(format: "%.0f", device.effectiveRangeKm))km")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding()
                .background(Color(.systemGray6))
            }
        }
    }

    // MARK: - 玩家列表

    private var playerList: some View {
        List {
            ForEach(messageManager.nearbyPlayers) { player in
                NearbyPlayerRow(
                    player: player,
                    deviceRangeKm: deviceManager.activeDevice?.effectiveRangeKm ?? 0
                )
                .onTapGesture {
                    selectedPlayer = player
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - 空状态

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "person.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("附近没有其他幸存者")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("尝试扩大搜索范围\n或升级你的通讯设备")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
    }
}

// MARK: - 附近玩家行

struct NearbyPlayerRow: View {
    let player: NearbyPlayer
    let deviceRangeKm: Double

    private var isInRange: Bool {
        player.distanceKm <= deviceRangeKm
    }

    var body: some View {
        HStack(spacing: 12) {
            // 头像
            ZStack {
                Circle()
                    .fill(player.isOnline ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
                    .frame(width: 50, height: 50)

                Text(player.displayName.prefix(1).uppercased())
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(player.isOnline ? .green : .gray)
            }

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(player.displayName)
                        .font(.headline)

                    if player.isOnline {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                    }
                }

                HStack {
                    Image(systemName: "location.fill")
                        .font(.caption2)
                    Text(player.distanceText)
                        .font(.caption)
                }
                .foregroundColor(isInRange ? .blue : .orange)
            }

            Spacer()

            // 通讯状态
            if isInRange {
                VStack(spacing: 2) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(.green)
                    Text("可通讯")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            } else {
                VStack(spacing: 2) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .foregroundColor(.orange)
                    Text("超出范围")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(isInRange ? 1.0 : 0.6)
    }
}

// MARK: - 预览

#Preview {
    NavigationView {
        ConversationListView()
    }
}
