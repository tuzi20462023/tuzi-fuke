//
//  CheckinView.swift
//  tuzi-fuke (地球新主复刻版)
//
//  打卡视图 - AI明信片生成界面
//  Created by AI Assistant on 2025/12/05.
//

import SwiftUI
import CoreLocation

struct CheckinView: View {
    let building: PlayerBuilding

    @StateObject private var checkinManager = CheckinManager.shared
    @StateObject private var avatarManager = AvatarManager.shared

    @State private var generatedPhoto: CheckinPhoto?
    @State private var showingResult = false
    @State private var showingAvatarSettings = false
    @State private var errorMessage: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 建筑信息
                    buildingInfoSection

                    // 剩余次数
                    remainingCountSection

                    // 头像设置（可选）
                    avatarSection

                    // 生成说明
                    descriptionSection

                    // 打卡按钮
                    checkinButton
                }
                .padding()
            }
            .navigationTitle("AI明信片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .task {
                await checkinManager.loadTodayCheckinCount()
                await avatarManager.loadAvatars()
            }
            .sheet(isPresented: $showingResult) {
                if let photo = generatedPhoto {
                    CheckinResultView(photo: photo) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAvatarSettings) {
                AvatarSettingsView()
            }
            .overlay {
                if checkinManager.isGenerating {
                    generatingOverlay
                }
            }
            .alert("生成失败", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "未知错误")
            }
        }
    }

    // MARK: - 建筑信息

    private var buildingInfoSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "building.2.fill")
                    .font(.title2)
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text(building.buildingName)
                        .font(.headline)
                    if let coord = building.coordinate {
                        Text(String(format: "%.4f, %.4f", coord.latitude, coord.longitude))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Lv.\(building.level)")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    Text(building.status.displayName)
                        .font(.caption)
                        .foregroundColor(statusColor(building.status))
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func statusColor(_ status: PlayerBuildingStatus) -> Color {
        switch status {
        case .active: return .green
        case .constructing: return .blue
        case .damaged: return .orange
        case .inactive: return .gray
        }
    }

    // MARK: - 剩余次数

    private var remainingCountSection: some View {
        HStack {
            Image(systemName: "camera.fill")
                .foregroundColor(.purple)

            Text("今日剩余生成次数")
                .font(.subheadline)

            Spacer()

            HStack(spacing: 4) {
                ForEach(0..<DailyCheckinLimit.maxDailyCheckins, id: \.self) { index in
                    Image(systemName: index < checkinManager.remainingCheckins ? "circle.fill" : "circle")
                        .font(.caption)
                        .foregroundColor(index < checkinManager.remainingCheckins ? .purple : .gray)
                }
            }

            Text("\(checkinManager.remainingCheckins)/\(DailyCheckinLimit.maxDailyCheckins)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(checkinManager.canCheckin ? .purple : .red)
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - 头像设置

    private var avatarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("我的头像")
                    .font(.headline)
                Spacer()
                Button {
                    showingAvatarSettings = true
                } label: {
                    Label(avatarManager.avatarPhotos.isEmpty ? "上传头像" : "更换", systemImage: "photo.badge.plus")
                        .font(.subheadline)
                }
            }

            if avatarManager.avatarPhotos.isEmpty {
                // 没有头像 - 提示上传
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("未上传头像")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("上传头像后，AI会在明信片中加入你的形象")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            } else {
                // 显示头像
                if let avatar = avatarManager.avatarPhotos.first {
                    HStack(spacing: 16) {
                        AsyncImage(url: URL(string: avatar.thumbnailUrl ?? avatar.photoUrl)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                            }
                        }
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text("头像已设置")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Text("AI会在明信片中加入你的形象")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
            }
        }
    }

    // MARK: - 说明

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundColor(.blue)
                Text("AI明信片")
                    .font(.headline)
            }

            Text("根据你的当前位置，AI会搜索该地点的真实信息，为你生成一张精美的旅行明信片风格照片。")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                Label("真实地点", systemImage: "location.fill")
                Label("明信片风格", systemImage: "photo.artframe")
            }
            .font(.caption)
            .foregroundColor(.blue)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - 打卡按钮

    private var checkinButton: some View {
        Button {
            Task {
                await performCheckin()
            }
        } label: {
            HStack {
                Image(systemName: "wand.and.stars")
                Text("生成明信片")
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(checkinManager.canCheckin ? Color.blue : Color.gray)
            .cornerRadius(12)
        }
        .disabled(!checkinManager.canCheckin)
    }

    private func performCheckin() async {
        let result = await checkinManager.generatePostcard(building: building)

        if result.success, let photo = result.photo {
            generatedPhoto = photo
            showingResult = true
        } else {
            errorMessage = result.message
        }
    }

    // MARK: - 生成中遮罩

    private var generatingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // 动画指示器
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 4)
                        .frame(width: 80, height: 80)

                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: checkinManager.isGenerating)

                    Image(systemName: "wand.and.stars")
                        .font(.title)
                        .foregroundColor(.white)
                }

                VStack(spacing: 8) {
                    Text("AI正在创作...")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text("正在搜索真实地点并生成明信片")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(40)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
        }
    }
}

// MARK: - 打卡结果视图

struct CheckinResultView: View {
    let photo: CheckinPhoto
    let onDismiss: () -> Void

    @State private var showingShareSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 成功提示
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        Text("明信片生成成功！")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    .padding(.top)

                    // 生成的图片
                    AsyncImage(url: URL(string: photo.imageUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(12)
                        case .empty:
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    ProgressView()
                                }
                                .cornerRadius(12)
                        case .failure:
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.largeTitle)
                                        .foregroundColor(.gray)
                                }
                                .cornerRadius(12)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal)

                    // 打卡信息
                    VStack(alignment: .leading, spacing: 12) {
                        if let locationName = photo.locationName {
                            HStack {
                                Image(systemName: "location.fill")
                                    .foregroundColor(.blue)
                                Text(locationName)
                            }
                        }

                        HStack {
                            Image(systemName: "clock.fill")
                                .foregroundColor(.orange)
                            Text(photo.formattedDate)
                        }
                    }
                    .font(.subheadline)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // 按钮
                    HStack(spacing: 16) {
                        Button {
                            showingShareSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("分享")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(12)
                        }

                        Button {
                            onDismiss()
                        } label: {
                            HStack {
                                Image(systemName: "checkmark")
                                Text("完成")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom)
            }
            .navigationTitle("生成完成")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = URL(string: photo.imageUrl) {
                ShareSheet(items: [url])
            }
        }
    }
}

// MARK: - 预览

#Preview {
    CheckinView(building: PlayerBuilding(
        id: UUID(),
        userId: UUID(),
        territoryId: UUID(),
        buildingTemplateId: nil,
        buildingName: "测试避难所",
        buildingTemplateKey: "shelter_basic",
        location: GeoJSONPoint(longitude: 121.4737, latitude: 31.2304),
        status: .active,
        buildStartedAt: Date(),
        buildCompletedAt: Date(),
        buildTimeHours: 1.0,
        level: 1,
        durability: 100,
        durabilityMax: 100,
        createdAt: Date(),
        updatedAt: Date()
    ))
}
