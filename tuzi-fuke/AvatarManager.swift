//
//  AvatarManager.swift
//  tuzi-fuke (地球新主复刻版)
//
//  用户头像管理器 - 管理用于AI生成的个人照片
//  Created by AI Assistant on 2025/12/05.
//

import Foundation
import SwiftUI
import Combine
import UIKit
import Supabase

// MARK: - 头像管理器

@MainActor
class AvatarManager: ObservableObject {
    static let shared = AvatarManager()

    private let supabase = SupabaseManager.shared

    /// Storage bucket 名称
    private let bucketName = "avatars"

    /// 最大头像数量
    static let maxAvatarCount = 1

    // MARK: - 发布属性

    @Published var avatarPhotos: [UserAvatarPhoto] = []
    @Published var isLoading = false
    @Published var error: String?

    private init() {}

    // MARK: - 加载头像列表

    /// 加载当前用户的所有头像
    func loadAvatars() async {
        guard let userId = await SupabaseManager.shared.getCurrentUserId() else {
            error = "未登录"
            return
        }

        isLoading = true
        error = nil

        do {
            let response = try await supabase.client.database
                .from("user_avatar_photos")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("is_active", value: true)
                .order("display_order", ascending: true)
                .execute()

            let decoder = Self.makeDecoder()
            let photos = try decoder.decode([UserAvatarPhoto].self, from: response.data)
            self.avatarPhotos = photos
            print("✅ [AvatarManager] 加载了 \(photos.count) 个头像")

        } catch {
            print("❌ [AvatarManager] 加载头像失败: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - 上传头像

    /// 上传新头像
    /// - Parameter image: 要上传的图片
    /// - Returns: 上传成功的头像记录
    func uploadAvatar(image: UIImage) async throws -> UserAvatarPhoto {
        guard let userId = await SupabaseManager.shared.getCurrentUserId() else {
            throw AvatarError.notLoggedIn
        }

        // 检查数量限制
        if avatarPhotos.count >= Self.maxAvatarCount {
            throw AvatarError.maxCountReached
        }

        isLoading = true
        defer { isLoading = false }

        // 1. 压缩图片
        guard let imageData = compressImage(image) else {
            throw AvatarError.compressionFailed
        }

        // 2. 生成文件名（注意：UUID 必须小写，与 Supabase auth.uid() 一致）
        let fileName = "\(userId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"

        // 3. 上传到 Storage
        do {
            try await supabase.client.storage
                .from(bucketName)
                .upload(
                    path: fileName,
                    file: imageData,
                    options: FileOptions(contentType: "image/jpeg")
                )
        } catch {
            print("❌ [AvatarManager] 上传到Storage失败: \(error.localizedDescription)")
            throw AvatarError.uploadFailed(error.localizedDescription)
        }

        // 4. 获取公开URL
        let publicURL = try supabase.client.storage
            .from(bucketName)
            .getPublicURL(path: fileName)

        // 5. 生成缩略图URL（使用Supabase图像转换）
        let thumbnailURL = publicURL.absoluteString + "?width=200&height=200"

        // 6. 保存记录到数据库
        let insertData = UserAvatarPhotoInsert(
            userId: userId,
            photoUrl: publicURL.absoluteString,
            thumbnailUrl: thumbnailURL,
            displayOrder: avatarPhotos.count
        )

        let response = try await supabase.client.database
            .from("user_avatar_photos")
            .insert(insertData)
            .select()
            .single()
            .execute()

        let decoder = Self.makeDecoder()
        let photo = try decoder.decode(UserAvatarPhoto.self, from: response.data)

        // 7. 更新本地列表
        avatarPhotos.append(photo)

        print("✅ [AvatarManager] 头像上传成功: \(photo.id)")
        return photo
    }

    // MARK: - 删除头像

    /// 删除头像
    /// - Parameter photoId: 头像ID
    func deleteAvatar(photoId: UUID) async throws {
        guard await SupabaseManager.shared.getCurrentUserId() != nil else {
            throw AvatarError.notLoggedIn
        }

        isLoading = true
        defer { isLoading = false }

        // 1. 查找头像记录
        guard avatarPhotos.contains(where: { $0.id == photoId }) else {
            throw AvatarError.notFound
        }

        // 2. 从数据库标记为非活跃（软删除）
        try await supabase.client.database
            .from("user_avatar_photos")
            .update(["is_active": false])
            .eq("id", value: photoId.uuidString)
            .execute()

        // 3. 从Storage删除文件（可选，这里保留文件以防需要恢复）
        // 如果要彻底删除，取消下面的注释
        /*
        if let url = URL(string: photo.photoUrl) {
            let path = url.lastPathComponent
            try await supabase.storage
                .from(bucketName)
                .remove(paths: [path])
        }
        */

        // 4. 更新本地列表
        avatarPhotos.removeAll { $0.id == photoId }

        // 5. 重新排序
        await reorderAvatars()

        print("✅ [AvatarManager] 头像删除成功: \(photoId)")
    }

    // MARK: - 重新排序

    /// 重新排序头像
    private func reorderAvatars() async {
        for (index, photo) in avatarPhotos.enumerated() {
            do {
                try await supabase.client.database
                    .from("user_avatar_photos")
                    .update(["display_order": index])
                    .eq("id", value: photo.id.uuidString)
                    .execute()
            } catch {
                print("⚠️ [AvatarManager] 更新排序失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 获取头像图片

    /// 获取头像图片
    /// - Parameter photo: 头像记录
    /// - Returns: UIImage
    func getAvatarImage(photo: UserAvatarPhoto) async throws -> UIImage {
        guard let url = URL(string: photo.photoUrl) else {
            throw AvatarError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        guard let image = UIImage(data: data) else {
            throw AvatarError.invalidImageData
        }

        return image
    }

    // MARK: - 辅助方法

    /// 压缩图片
    private func compressImage(_ image: UIImage, maxSize: CGFloat = 1024) -> Data? {
        var targetImage = image

        // 缩放图片
        let size = image.size
        if size.width > maxSize || size.height > maxSize {
            let scale = maxSize / max(size.width, size.height)
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)

            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            if let resized = UIGraphicsGetImageFromCurrentImageContext() {
                targetImage = resized
            }
            UIGraphicsEndImageContext()
        }

        // 压缩为JPEG
        return targetImage.jpegData(compressionQuality: 0.8)
    }

    /// 是否可以添加更多头像
    var canAddMoreAvatars: Bool {
        return avatarPhotos.count < Self.maxAvatarCount
    }

    /// 剩余可上传数量
    var remainingAvatarSlots: Int {
        return max(0, Self.maxAvatarCount - avatarPhotos.count)
    }

    // MARK: - JSON 解码器

    /// 创建配置好的JSON解码器
    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: dateString) {
                return date
            }
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "无法解析日期: \(dateString)")
        }
        return decoder
    }
}

// MARK: - 错误类型

enum AvatarError: Error, LocalizedError {
    case notLoggedIn
    case maxCountReached
    case compressionFailed
    case uploadFailed(String)
    case notFound
    case invalidURL
    case invalidImageData

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "请先登录"
        case .maxCountReached:
            return "头像数量已达上限(3张)"
        case .compressionFailed:
            return "图片压缩失败"
        case .uploadFailed(let msg):
            return "上传失败: \(msg)"
        case .notFound:
            return "头像不存在"
        case .invalidURL:
            return "无效的图片URL"
        case .invalidImageData:
            return "无效的图片数据"
        }
    }
}
