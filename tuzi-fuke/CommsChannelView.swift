//
//  CommsChannelView.swift
//  tuzi-fuke
//
//  通讯终端 - 频道面板
//  管理频道订阅与切换
//

import SwiftUI

struct CommsChannelView: View {
    @StateObject private var channelManager = ChannelManager.shared
    @State private var isProcessing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. 当前接入的频道（突出显示）
                currentChannelSection

                // 2. 官方频道列表（可订阅/进入）
                officialChannelsSection

                // 底部留白
                Color.clear.frame(height: 40)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .task {
            await channelManager.loadOfficialChannels()
            await channelManager.loadSubscribedChannels()
        }
    }

    // MARK: - 当前频道区域

    private var currentChannelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("当前接入", icon: "waveform")

            if let current = channelManager.currentChannel {
                // 显示当前选中的频道
                CurrentChannelCard(
                    channel: current,
                    onExit: {
                        channelManager.clearCurrentChannel()
                    }
                )
            } else {
                // 显示公共广播
                PublicBroadcastCard()
            }
        }
    }

    // MARK: - 官方频道区域

    private var officialChannelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("官方频道", icon: "antenna.radiowaves.left.and.right")

            if channelManager.officialChannels.isEmpty {
                Text("暂无官方频道")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(channelManager.officialChannels) { channel in
                    OfficialChannelCard(
                        channel: channel,
                        isSubscribed: channelManager.isSubscribed(to: channel),
                        isCurrentChannel: channelManager.currentChannel?.id == channel.id,
                        onEnter: {
                            Task {
                                await channelManager.selectChannel(channel)
                            }
                        },
                        onToggleSubscribe: {
                            toggleSubscription(for: channel)
                        }
                    )
                }
            }
        }
    }

    // MARK: - 辅助组件

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
        }
        .foregroundColor(.secondary)
        .textCase(.uppercase)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleSubscription(for channel: CommunicationChannel) {
        guard !isProcessing else { return }
        isProcessing = true
        Task {
            if channelManager.isSubscribed(to: channel) {
                _ = await channelManager.unsubscribeFromChannel(channel)
            } else {
                _ = await channelManager.subscribeToChannel(channel)
            }
            isProcessing = false
        }
    }
}

// MARK: - 当前频道卡片（大卡片，突出显示）

struct CurrentChannelCard: View {
    let channel: CommunicationChannel
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // 频道图标（带动画效果）
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.green.opacity(0.3), Color.green.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 56, height: 56)

                    Image(systemName: channel.displayIcon)
                        .font(.title2)
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(channel.channelName)
                            .font(.headline)
                        if channel.isOfficial {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("信号接收中")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                Spacer()

                // 退出按钮
                Button(action: onExit) {
                    Text("返回广播")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.green.opacity(0.2), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - 公共广播卡片

struct PublicBroadcastCard: View {
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 56, height: 56)

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("公共广播")
                    .font(.headline)

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                    Text("全频段接收中")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundColor(.blue)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.blue.opacity(0.15), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - 官方频道卡片（清晰的操作区分）

struct OfficialChannelCard: View {
    let channel: CommunicationChannel
    let isSubscribed: Bool
    let isCurrentChannel: Bool
    let onEnter: () -> Void
    let onToggleSubscribe: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 主体内容（点击进入频道）
            Button(action: onEnter) {
                HStack(spacing: 14) {
                    // 频道图标
                    ZStack {
                        Circle()
                            .fill(iconColor.opacity(0.12))
                            .frame(width: 44, height: 44)

                        Image(systemName: channel.displayIcon)
                            .font(.system(size: 18))
                            .foregroundColor(iconColor)
                    }

                    // 频道信息
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(channel.channelName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)

                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }

                        Text("\(channel.subscriberCount) 人订阅")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // 右侧状态/操作
                    if isCurrentChannel {
                        // 当前正在收听
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text("收听中")
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                    } else {
                        // 进入按钮
                        Text("进入")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            // 分割线
            Divider()
                .padding(.leading, 72)

            // 底部操作栏（订阅按钮独立出来）
            HStack {
                Spacer()

                Button(action: onToggleSubscribe) {
                    HStack(spacing: 4) {
                        Image(systemName: isSubscribed ? "bell.fill" : "bell")
                            .font(.caption)
                        Text(isSubscribed ? "已订阅" : "订阅")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(isSubscribed ? .orange : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isSubscribed ? Color.orange.opacity(0.1) : Color(.systemGray6))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isCurrentChannel ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    private var iconColor: Color {
        guard let code = channel.channelCode else { return .blue }
        switch code {
        case "OFF-ALERT": return .red
        case "OFF-MISSION": return .orange
        case "OFF-NEWS": return .blue
        case "OFF-SURVIVAL": return .green
        default: return .blue
        }
    }
}

// MARK: - 预览

#Preview {
    CommsChannelView()
}
