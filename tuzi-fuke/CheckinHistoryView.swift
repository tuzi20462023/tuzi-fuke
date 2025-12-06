//
//  CheckinHistoryView.swift
//  tuzi-fuke (地球新主复刻版)
//
//  打卡历史视图 - 展示用户的所有打卡记录
//  Created by AI Assistant on 2025/12/05.
//

import SwiftUI

struct CheckinHistoryView: View {
    @StateObject private var checkinManager = CheckinManager.shared

    @State private var selectedPhoto: CheckinPhoto?
    @State private var showingDetail = false
    @State private var showingDeleteAlert = false
    @State private var photoToDelete: CheckinPhoto?

    var body: some View {
        NavigationStack {
            Group {
                if checkinManager.isLoading && checkinManager.checkinPhotos.isEmpty {
                    loadingView
                } else if checkinManager.checkinPhotos.isEmpty {
                    emptyView
                } else {
                    photoGrid
                }
            }
            .navigationTitle("打卡记录")
            .task {
                await checkinManager.loadCheckinHistory()
            }
            .refreshable {
                await checkinManager.loadCheckinHistory()
            }
            .sheet(item: $selectedPhoto) { photo in
                CheckinDetailView(photo: photo) {
                    photoToDelete = photo
                    showingDeleteAlert = true
                }
            }
            .alert("删除打卡", isPresented: $showingDeleteAlert) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if let photo = photoToDelete {
                        Task {
                            try? await checkinManager.deleteCheckinPhoto(photoId: photo.id)
                            selectedPhoto = nil
                        }
                    }
                }
            } message: {
                Text("确定要删除这张打卡照片吗？删除后无法恢复。")
            }
        }
    }

    // MARK: - 加载中视图

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("加载中...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 空状态视图

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.badge.clock")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("还没有打卡记录")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("在建筑详情页点击「打卡」\n开始创作你的末世照片吧！")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - 照片网格

    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2)
            ], spacing: 2) {
                ForEach(checkinManager.checkinPhotos) { photo in
                    photoThumbnail(photo: photo)
                }
            }
        }
    }

    private func photoThumbnail(photo: CheckinPhoto) -> some View {
        Button {
            selectedPhoto = photo
        } label: {
            AsyncImage(url: URL(string: photo.thumbnailUrl ?? photo.imageUrl)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            ProgressView()
                        }
                case .failure:
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        }
                @unknown default:
                    EmptyView()
                }
            }
            .aspectRatio(1, contentMode: .fill)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                // 模式图标
                Image(systemName: photo.mode.icon)
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(4)
                    .padding(4)
            }
        }
    }
}

// MARK: - 打卡详情视图

struct CheckinDetailView: View {
    let photo: CheckinPhoto
    let onDelete: () -> Void

    @State private var showingShareSheet = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 照片
                    AsyncImage(url: URL(string: photo.imageUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .empty:
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    ProgressView()
                                }
                        case .failure:
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    VStack {
                                        Image(systemName: "exclamationmark.triangle")
                                            .font(.largeTitle)
                                        Text("加载失败")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.gray)
                                }
                        @unknown default:
                            EmptyView()
                        }
                    }

                    // 详情信息
                    VStack(alignment: .leading, spacing: 16) {
                        // 模式
                        detailRow(
                            icon: photo.mode.icon,
                            iconColor: .purple,
                            title: "打卡模式",
                            value: photo.mode.displayName
                        )

                        // 时间
                        detailRow(
                            icon: "clock.fill",
                            iconColor: .orange,
                            title: "打卡时间",
                            value: photo.formattedDate
                        )

                        // 位置
                        if let locationName = photo.locationName {
                            detailRow(
                                icon: "location.fill",
                                iconColor: .blue,
                                title: "位置",
                                value: locationName
                            )
                        }

                        // 天气
                        if let weather = photo.weather {
                            detailRow(
                                icon: "cloud.fill",
                                iconColor: .gray,
                                title: "天气",
                                value: weather + (photo.temperature.map { " \($0)" } ?? "")
                            )
                        }

                        // 时间段
                        if let timeOfDayRaw = photo.timeOfDay,
                           let timeOfDay = TimeOfDay(rawValue: timeOfDayRaw) {
                            detailRow(
                                icon: "sun.horizon.fill",
                                iconColor: .yellow,
                                title: "时间段",
                                value: timeOfDay.displayName
                            )
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    // 操作按钮
                    HStack(spacing: 16) {
                        Button {
                            showingShareSheet = true
                        } label: {
                            Label("分享", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(12)
                        }

                        Button {
                            onDelete()
                        } label: {
                            Label("删除", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(12)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("打卡详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = URL(string: photo.imageUrl) {
                ShareSheet(items: [url])
            }
        }
    }

    private func detailRow(icon: String, iconColor: Color, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 24)

            Text(title)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

// MARK: - 预览

#Preview("历史列表") {
    CheckinHistoryView()
}

#Preview("详情") {
    CheckinDetailView(
        photo: CheckinPhoto(
            id: UUID(),
            userId: UUID(),
            buildingId: UUID(),
            locationName: "上海市浦东新区",
            latitude: 31.2304,
            longitude: 121.4737,
            weather: "多云",
            temperature: "22°C",
            timeOfDay: "afternoon",
            mode: .landscape,
            prompt: nil,
            imageUrl: "https://example.com/photo.jpg",
            thumbnailUrl: nil,
            isPublic: true,
            isDeleted: false,
            createdAt: Date(),
            updatedAt: Date()
        ),
        onDelete: {}
    )
}
