//
//  ChannelListView.swift
//  tuzi-fuke
//
//  频道列表界面 - 显示官方频道和用户订阅
//

import SwiftUI

struct ChannelListView: View {
    @StateObject private var channelManager = ChannelManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 选项卡
                Picker("", selection: $selectedTab) {
                    Text("官方频道").tag(0)
                    Text("我的订阅").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                // 内容
                if channelManager.isLoading {
                    Spacer()
                    ProgressView("加载中...")
                    Spacer()
                } else {
                    TabView(selection: $selectedTab) {
                        // 官方频道列表
                        officialChannelsList
                            .tag(0)

                        // 已订阅频道列表
                        subscribedChannelsList
                            .tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .navigationTitle("通讯频道")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await channelManager.loadOfficialChannels()
            await channelManager.loadSubscribedChannels()
        }
    }

    // MARK: - 官方频道列表

    private var officialChannelsList: some View {
        Group {
            if channelManager.officialChannels.isEmpty {
                emptyView(message: "暂无官方频道")
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(channelManager.officialChannels) { channel in
                            ChannelCard(
                                channel: channel,
                                isSubscribed: channelManager.isSubscribed(to: channel),
                                onSubscribe: {
                                    Task {
                                        _ = await channelManager.subscribeToChannel(channel)
                                    }
                                },
                                onUnsubscribe: {
                                    Task {
                                        _ = await channelManager.unsubscribeFromChannel(channel)
                                    }
                                },
                                onSelect: {
                                    Task {
                                        await channelManager.selectChannel(channel)
                                        dismiss()
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
    }

    // MARK: - 已订阅频道列表

    private var subscribedChannelsList: some View {
        Group {
            if channelManager.subscribedChannels.isEmpty {
                emptyView(message: "还没有订阅任何频道\n去「官方频道」看看吧")
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(channelManager.subscribedChannels) { channel in
                            ChannelCard(
                                channel: channel,
                                isSubscribed: true,
                                onSubscribe: {},
                                onUnsubscribe: {
                                    Task {
                                        _ = await channelManager.unsubscribeFromChannel(channel)
                                    }
                                },
                                onSelect: {
                                    Task {
                                        await channelManager.selectChannel(channel)
                                        dismiss()
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
    }

    // MARK: - 空状态视图

    private func emptyView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }
}

// MARK: - 频道卡片

struct ChannelCard: View {
    let channel: CommunicationChannel
    let isSubscribed: Bool
    let onSubscribe: () -> Void
    let onUnsubscribe: () -> Void
    let onSelect: () -> Void

    @State private var isProcessing = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // 频道图标
                ZStack {
                    Circle()
                        .fill(channelColor.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: channel.displayIcon)
                        .font(.system(size: 24))
                        .foregroundColor(channelColor)
                }

                // 频道信息
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(channel.channelName)
                            .font(.headline)
                            .foregroundColor(.primary)

                        if channel.isOfficial {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }

                    if let description = channel.description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    // 订阅人数
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                        Text("\(channel.subscriberCount) 订阅")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }

                Spacer()

                // 订阅按钮
                subscribeButton
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
    }

    // 订阅按钮
    private var subscribeButton: some View {
        Button {
            guard !isProcessing else { return }
            isProcessing = true

            if isSubscribed {
                onUnsubscribe()
            } else {
                onSubscribe()
            }

            // 延迟重置处理状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                isProcessing = false
            }
        } label: {
            if isProcessing {
                ProgressView()
                    .frame(width: 70, height: 32)
            } else if isSubscribed {
                Text("已订阅")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray5))
                    .cornerRadius(16)
            } else {
                Text("订阅")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .cornerRadius(16)
            }
        }
        .buttonStyle(.plain)
    }

    // 频道颜色
    private var channelColor: Color {
        switch channel.channelCode {
        case "OFF-SURVIVAL":
            return .green
        case "OFF-NEWS":
            return .blue
        case "OFF-MISSION":
            return .orange
        case "OFF-ALERT":
            return .red
        default:
            return channel.channelType == .official ? .purple : .gray
        }
    }
}

// MARK: - 预览

#Preview {
    ChannelListView()
}
