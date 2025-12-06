//
//  ProfileTabView.swift
//  tuzi-fuke (地球新主复刻版)
//
//  个人中心 Tab - 头像设置、打卡历史等
//  Created by AI Assistant on 2025/12/05.
//

import SwiftUI

struct ProfileTabView: View {
    @ObservedObject private var authManager = AuthManager.shared
    @StateObject private var checkinManager = CheckinManager.shared
    @StateObject private var avatarManager = AvatarManager.shared

    @State private var showingAvatarSettings = false
    @State private var showingCheckinHistory = false

    var body: some View {
        NavigationStack {
            List {
                // 用户信息
                userInfoSection

                // AI打卡功能
                checkinSection

                // 设置
                settingsSection

                // 退出登录
                logoutSection
            }
            .navigationTitle("我的")
            .task {
                await checkinManager.loadTodayCheckinCount()
                await avatarManager.loadAvatars()
            }
            .sheet(isPresented: $showingAvatarSettings) {
                AvatarSettingsView()
            }
            .sheet(isPresented: $showingCheckinHistory) {
                CheckinHistoryView()
            }
        }
    }

    // MARK: - 用户信息

    private var userInfoSection: some View {
        Section {
            HStack(spacing: 16) {
                // 头像
                if let firstAvatar = avatarManager.avatarPhotos.first {
                    AsyncImage(url: URL(string: firstAvatar.thumbnailUrl ?? firstAvatar.photoUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            defaultAvatarImage
                        }
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                } else {
                    defaultAvatarImage
                        .frame(width: 60, height: 60)
                }

                // 用户名和邮箱
                VStack(alignment: .leading, spacing: 4) {
                    Text(authManager.currentUser?.username ?? "幸存者")
                        .font(.headline)
                    if let email = authManager.currentUser?.email {
                        Text(email)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    private var defaultAvatarImage: some View {
        Circle()
            .fill(Color.gray.opacity(0.3))
            .overlay {
                Image(systemName: "person.fill")
                    .font(.title)
                    .foregroundColor(.gray)
            }
    }

    // MARK: - AI打卡功能

    private var checkinSection: some View {
        Section("AI打卡") {
            // AI头像设置
            Button {
                showingAvatarSettings = true
            } label: {
                HStack {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI头像设置")
                            .foregroundColor(.primary)
                        Text(avatarManager.avatarPhotos.isEmpty ? "未上传" : "已上传")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // 打卡历史
            Button {
                showingCheckinHistory = true
            } label: {
                HStack {
                    Image(systemName: "camera.fill")
                        .font(.title2)
                        .foregroundColor(.purple)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("打卡记录")
                            .foregroundColor(.primary)
                        Text("今日已打卡 \(checkinManager.todayCheckinCount)/\(DailyCheckinLimit.maxDailyCheckins) 次")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // 今日打卡状态
            HStack {
                Image(systemName: "calendar")
                    .font(.title2)
                    .foregroundColor(.orange)
                    .frame(width: 32)

                Text("今日剩余打卡次数")

                Spacer()

                HStack(spacing: 4) {
                    ForEach(0..<DailyCheckinLimit.maxDailyCheckins, id: \.self) { index in
                        Circle()
                            .fill(index < checkinManager.remainingCheckins ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 12, height: 12)
                    }
                }
            }
        }
    }

    // MARK: - 设置

    private var settingsSection: some View {
        Section("设置") {
            // 这里可以添加更多设置项
            HStack {
                Image(systemName: "info.circle")
                    .font(.title2)
                    .foregroundColor(.gray)
                    .frame(width: 32)

                Text("关于")

                Spacer()

                Text("v1.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 退出登录

    private var logoutSection: some View {
        Section {
            Button(role: .destructive) {
                Task {
                    await authManager.signOut()
                }
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.title2)
                        .frame(width: 32)

                    Text("退出登录")

                    Spacer()
                }
            }
        }
    }
}

// MARK: - 预览

#Preview {
    ProfileTabView()
}
