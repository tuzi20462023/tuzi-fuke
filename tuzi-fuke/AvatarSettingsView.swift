//
//  AvatarSettingsView.swift
//  tuzi-fuke (地球新主复刻版)
//
//  头像设置视图 - 用户管理AI生成用的个人照片
//  Created by AI Assistant on 2025/12/05.
//

import SwiftUI
import PhotosUI

struct AvatarSettingsView: View {
    @StateObject private var avatarManager = AvatarManager.shared
    @State private var selectedItem: PhotosPickerItem?
    @State private var showingImagePicker = false
    @State private var showingDeleteAlert = false
    @State private var avatarToDelete: UserAvatarPhoto?
    @State private var isUploading = false
    @State private var uploadError: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 说明
                    headerSection

                    // 头像列表
                    avatarListSection

                    // 添加按钮
                    if avatarManager.canAddMoreAvatars {
                        addAvatarSection
                    }
                }
                .padding()
            }
            .navigationTitle("AI头像设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .task {
                await avatarManager.loadAvatars()
            }
            .alert("删除头像", isPresented: $showingDeleteAlert) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if let avatar = avatarToDelete {
                        Task {
                            try? await avatarManager.deleteAvatar(photoId: avatar.id)
                        }
                    }
                }
            } message: {
                Text("确定要删除这张头像吗？删除后无法恢复。")
            }
            .alert("上传失败", isPresented: .init(
                get: { uploadError != nil },
                set: { if !$0 { uploadError = nil } }
            )) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(uploadError ?? "未知错误")
            }
            .overlay {
                if isUploading {
                    uploadingOverlay
                }
            }
        }
    }

    // MARK: - 说明区域

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("AI打卡头像")
                    .font(.headline)
            }

            Text("上传你的照片，AI将在打卡时生成你在末世场景中的自拍照。")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                Image(systemName: "lock.shield")
                    .foregroundColor(.green)
                Text("照片仅用于AI生成，不会公开展示")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - 头像列表

    private var avatarListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("已上传的头像")
                    .font(.headline)
                Spacer()
                Text("\(avatarManager.avatarPhotos.count)/\(AvatarManager.maxAvatarCount)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if avatarManager.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding()
            } else if avatarManager.avatarPhotos.isEmpty {
                emptyAvatarView
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(avatarManager.avatarPhotos) { photo in
                        avatarCard(photo: photo)
                    }
                }
            }
        }
    }

    private var emptyAvatarView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("还没有上传头像")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("上传头像后可以使用自拍模式打卡")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func avatarCard(photo: UserAvatarPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: URL(string: photo.thumbnailUrl ?? photo.photoUrl)) { phase in
                switch phase {
                case .empty:
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            ProgressView()
                        }
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
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
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // 删除按钮
            Button {
                avatarToDelete = photo
                showingDeleteAlert = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .shadow(radius: 2)
            }
            .offset(x: 8, y: -8)
        }
    }

    // MARK: - 添加头像

    private var addAvatarSection: some View {
        PhotosPicker(
            selection: $selectedItem,
            matching: .images
        ) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                Text("添加头像")
                    .font(.headline)
            }
            .foregroundColor(.blue)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
        }
        .onChange(of: selectedItem) { _, newValue in
            guard let newValue else { return }
            Task {
                await handleSelectedImage(newValue)
            }
        }
    }

    private func handleSelectedImage(_ item: PhotosPickerItem) async {
        isUploading = true
        defer { isUploading = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                uploadError = "无法读取图片"
                return
            }

            _ = try await avatarManager.uploadAvatar(image: image)
            selectedItem = nil

        } catch {
            uploadError = error.localizedDescription
        }
    }

    // MARK: - 上传中遮罩

    private var uploadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("正在上传...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
        }
    }
}

// MARK: - 预览

#Preview {
    AvatarSettingsView()
}
