//
//  CheckinManager.swift
//  tuzi-fuke (地球新主复刻版)
//
//  打卡管理器 - 处理AI明信片生成和管理
//  Created by AI Assistant on 2025/12/05.
//

import Foundation
import SwiftUI
import Combine
import UIKit
import CoreLocation
import Supabase

// MARK: - 打卡管理器

@MainActor
class CheckinManager: ObservableObject {
    static let shared = CheckinManager()

    private let supabase = SupabaseManager.shared.client
    private let geminiService = GeminiService.shared
    private let avatarManager = AvatarManager.shared
    private let dataStore = CheckinDataStore.shared

    /// Storage bucket 名称
    private let bucketName = "checkin-photos"

    // MARK: - 发布属性

    @Published var todayCheckinCount = 0
    @Published var checkinPhotos: [CheckinPhoto] = []
    @Published var isLoading = false
    @Published var isGenerating = false
    @Published var error: String?

    /// 后台同步任务
    private var syncTask: Task<Void, Never>?

    private init() {
        // 启动后台同步任务
        startBackgroundSync()
    }

    deinit {
        syncTask?.cancel()
    }

    // MARK: - 加载今日打卡次数

    /// 加载今日打卡次数
    func loadTodayCheckinCount() async {
        guard let userId = await SupabaseManager.shared.getCurrentUserId() else {
            return
        }

        let today = formatDate(Date())

        do {
            // 尝试获取今日记录
            let response = try await supabase.database
                .from("daily_checkin_limits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("date", value: today)
                .execute()

            let decoder = Self.makeDecoder()
            let limits = try decoder.decode([DailyCheckinLimit].self, from: response.data)

            if let limit = limits.first {
                self.todayCheckinCount = limit.checkinCount
            } else {
                self.todayCheckinCount = 0
            }

            print("✅ [CheckinManager] 今日打卡次数: \(todayCheckinCount)")

        } catch {
            print("⚠️ [CheckinManager] 加载今日打卡次数失败: \(error.localizedDescription)")
            self.todayCheckinCount = 0
        }
    }

    /// 剩余打卡次数
    var remainingCheckins: Int {
        return max(0, DailyCheckinLimit.maxDailyCheckins - todayCheckinCount)
    }

    /// 是否还能打卡
    var canCheckin: Bool {
        return remainingCheckins > 0
    }

    // MARK: - 生成明信片

    /// 在建筑处生成明信片
    /// - Parameter building: 建筑信息
    /// - Returns: 生成结果
    func generatePostcard(building: PlayerBuilding) async -> CheckinResult {
        guard let userId = await SupabaseManager.shared.getCurrentUserId() else {
            return CheckinResult(success: false, photo: nil, error: .unknown("未登录"), message: "请先登录")
        }

        // 检查每日限制
        if !canCheckin {
            return CheckinResult(
                success: false,
                photo: nil,
                error: .dailyLimitReached,
                message: "今日生成次数已用完，明天再来吧！"
            )
        }

        // 获取建筑坐标
        guard let coordinate = building.coordinate else {
            return CheckinResult(
                success: false,
                photo: nil,
                error: .buildingNotFound,
                message: "建筑位置信息无效"
            )
        }

        // 获取头像（如果有）
        var avatarImage: UIImage?
        if let avatar = avatarManager.avatarPhotos.first {
            do {
                avatarImage = try await avatarManager.getAvatarImage(photo: avatar)
                print("📷 [CheckinManager] 已加载用户头像")
            } catch {
                print("⚠️ [CheckinManager] 无法加载头像: \(error.localizedDescription)")
                // 继续生成，只是不带头像
            }
        }

        isGenerating = true
        error = nil

        do {
            // 1. 构建位置
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

            // 2. 调用Gemini生成明信片
            print("🎨 [CheckinManager] 开始生成AI明信片...")
            print("📍 [CheckinManager] 位置: \(coordinate.latitude), \(coordinate.longitude)")

            let generatedImage = try await geminiService.generateCheckinImage(
                location: location,
                avatarImage: avatarImage
            )

            // 3. 上传图片到Storage
            let imageURL = try await uploadCheckinImage(generatedImage, userId: userId)

            // 4. 先保存到本地 SwiftData（立即可用）
            let cachedPhoto = try dataStore.saveCheckinPhoto(
                userId: userId,
                buildingId: building.id,
                locationName: building.buildingName,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                weather: nil,
                temperature: nil,
                timeOfDay: TimeOfDay.current().rawValue,
                mode: "postcard",
                prompt: "明信片模式 - 位置: \(coordinate.latitude), \(coordinate.longitude)",
                imageUrl: imageURL,
                thumbnailUrl: imageURL + "?width=400&height=400",
                isPublic: true
            )

            // 5. 转换为显示模型并立即更新UI
            if let displayPhoto = cachedPhoto.toCheckinPhoto() {
                checkinPhotos.insert(displayPhoto, at: 0)
                todayCheckinCount += 1
                print("✅ [CheckinManager] 本地保存成功，UI已更新")
            }

            // 6. 后台异步同步到云端
            Task {
                await syncToCloud(cachedPhoto: cachedPhoto, userId: userId)
            }

            isGenerating = false

            print("✅ [CheckinManager] 明信片生成成功!")
            return CheckinResult(
                success: true,
                photo: cachedPhoto.toCheckinPhoto(),
                error: nil,
                message: "明信片生成成功！"
            )

        } catch let geminiError as GeminiError {
            isGenerating = false
            let message = geminiError.localizedDescription
            self.error = message
            return CheckinResult(
                success: false,
                photo: nil,
                error: .aiGenerationFailed(message),
                message: message
            )

        } catch {
            isGenerating = false
            let message = error.localizedDescription
            self.error = message
            return CheckinResult(
                success: false,
                photo: nil,
                error: .unknown(message),
                message: message
            )
        }
    }

    /// 同步本地记录到云端
    private func syncToCloud(cachedPhoto: CachedCheckinPhoto, userId: UUID) async {
        do {
            // 构建插入数据
            let insertData = CheckinPhotoInsert(
                userId: userId,
                buildingId: cachedPhoto.buildingId,
                locationName: cachedPhoto.locationName,
                latitude: cachedPhoto.latitude,
                longitude: cachedPhoto.longitude,
                weather: cachedPhoto.weather,
                temperature: cachedPhoto.temperature,
                timeOfDay: cachedPhoto.timeOfDay,
                mode: cachedPhoto.mode,
                prompt: cachedPhoto.prompt,
                imageUrl: cachedPhoto.imageUrl,
                thumbnailUrl: cachedPhoto.thumbnailUrl,
                isPublic: cachedPhoto.isPublic
            )

            // 保存到 Supabase
            let response = try await supabase.database
                .from("checkin_photos")
                .insert(insertData)
                .select()
                .single()
                .execute()

            let decoder = Self.makeDecoder()
            let cloudPhoto = try decoder.decode(CheckinPhoto.self, from: response.data)

            // 标记为已同步
            try dataStore.markAsSynced(cachedPhoto)

            // 更新每日打卡次数
            await updateDailyCheckinCount(userId: userId)

            print("☁️ [CheckinManager] 云端同步成功: \(cloudPhoto.id)")

        } catch {
            print("⚠️ [CheckinManager] 云端同步失败: \(error.localizedDescription)")
            // 标记为同步失败
            try? dataStore.markSyncFailed(cachedPhoto, error: error.localizedDescription)
        }
    }

    // MARK: - 上传图片

    private func uploadCheckinImage(_ image: UIImage, userId: UUID) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            throw CheckinError.uploadFailed("图片压缩失败")
        }

        // 注意：UUID 必须小写，与 Supabase auth.uid() 一致
        let fileName = "\(userId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"

        try await supabase.storage
            .from(bucketName)
            .upload(
                path: fileName,
                file: imageData,
                options: FileOptions(contentType: "image/jpeg")
            )

        let publicURL = try supabase.storage
            .from(bucketName)
            .getPublicURL(path: fileName)

        return publicURL.absoluteString
    }

    // MARK: - 更新每日打卡次数

    private func updateDailyCheckinCount(userId: UUID) async {
        let today = formatDate(Date())

        do {
            // 使用 upsert 更新或插入
            let upsertData = DailyCheckinLimitUpsert(
                userId: userId.uuidString,
                date: today,
                checkinCount: todayCheckinCount + 1
            )
            try await supabase.database
                .from("daily_checkin_limits")
                .upsert(upsertData)
                .execute()

        } catch {
            print("⚠️ [CheckinManager] 更新每日打卡次数失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 加载打卡历史

    /// 加载打卡历史（本地优先 + 后台同步）
    /// - Parameter limit: 加载数量限制
    func loadCheckinHistory(limit: Int = 20) async {
        guard let userId = await SupabaseManager.shared.getCurrentUserId() else {
            return
        }

        isLoading = true

        // 1. 优先从本地加载（立即显示）
        do {
            let cachedPhotos = try dataStore.fetchCheckinPhotos(for: userId, limit: limit)
            let displayPhotos = cachedPhotos.compactMap { $0.toCheckinPhoto() }
            self.checkinPhotos = displayPhotos
            print("✅ [CheckinManager] 从本地加载了 \(displayPhotos.count) 条记录")
        } catch {
            print("⚠️ [CheckinManager] 本地加载失败: \(error.localizedDescription)")
        }

        isLoading = false

        // 2. 后台静默同步云端数据
        Task {
            await syncFromCloud(userId: userId, limit: limit)
        }
    }

    /// 从云端同步数据到本地
    private func syncFromCloud(userId: UUID, limit: Int) async {
        do {
            let response = try await supabase.database
                .from("checkin_photos")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("is_deleted", value: false)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()

            let decoder = Self.makeDecoder()
            let cloudPhotos = try decoder.decode([CheckinPhoto].self, from: response.data)

            // 同步到本地缓存
            try dataStore.syncFromCloud(cloudPhotos)

            // 更新UI
            let cachedPhotos = try dataStore.fetchCheckinPhotos(for: userId, limit: limit)
            let displayPhotos = cachedPhotos.compactMap { $0.toCheckinPhoto() }
            self.checkinPhotos = displayPhotos

            print("☁️ [CheckinManager] 云端同步完成，共 \(cloudPhotos.count) 条记录")

        } catch {
            print("⚠️ [CheckinManager] 云端同步失败: \(error.localizedDescription)")
            // 失败时保持本地数据不变
        }
    }

    // MARK: - 删除打卡照片

    /// 删除打卡照片（本地优先 + 后台异步删除云端）
    func deleteCheckinPhoto(photoId: UUID) async throws {
        // 1. 先从UI移除（立即响应）
        checkinPhotos.removeAll { $0.id == photoId }
        print("✅ [CheckinManager] UI已移除: \(photoId)")

        // 2. 标记本地记录为待删除
        if let cachedPhoto = try? dataStore.fetchPhoto(by: photoId) {
            try dataStore.markForDeletion(cachedPhoto)
            print("✅ [CheckinManager] 本地标记为待删除: \(photoId)")
        }

        // 3. 后台异步删除云端
        Task {
            await deleteFromCloud(photoId: photoId)
        }
    }

    /// 从云端删除记录
    private func deleteFromCloud(photoId: UUID) async {
        do {
            try await supabase.database
                .from("checkin_photos")
                .update(["is_deleted": true])
                .eq("id", value: photoId.uuidString)
                .execute()

            // 云端删除成功后，物理删除本地记录
            if let cachedPhoto = try? dataStore.fetchPhoto(by: photoId) {
                try dataStore.deletePhoto(cachedPhoto)
                print("☁️ [CheckinManager] 云端删除成功，本地已清理: \(photoId)")
            }

        } catch {
            print("⚠️ [CheckinManager] 云端删除失败: \(error.localizedDescription)")
            // 失败时保持本地待删除状态，等待重试
        }
    }

    // MARK: - 后台同步

    /// 启动后台同步任务
    private func startBackgroundSync() {
        syncTask = Task {
            while !Task.isCancelled {
                // 每 30 秒检查一次待同步/待删除的记录
                try? await Task.sleep(for: .seconds(30))

                if Task.isCancelled { break }

                await performBackgroundSync()
            }
        }
    }

    /// 执行后台同步
    private func performBackgroundSync() async {
        guard let userId = await SupabaseManager.shared.getCurrentUserId() else {
            return
        }

        // 1. 同步待上传的记录
        do {
            let pendingPhotos = try dataStore.fetchPendingPhotos()
            for photo in pendingPhotos {
                await syncToCloud(cachedPhoto: photo, userId: userId)
            }
            if !pendingPhotos.isEmpty {
                print("🔄 [CheckinManager] 后台同步了 \(pendingPhotos.count) 条待上传记录")
            }
        } catch {
            print("⚠️ [CheckinManager] 后台同步失败: \(error.localizedDescription)")
        }

        // 2. 同步待删除的记录
        do {
            let pendingDeletePhotos = try dataStore.fetchPendingDeletePhotos()
            for photo in pendingDeletePhotos {
                await deleteFromCloud(photoId: photo.id)
            }
            if !pendingDeletePhotos.isEmpty {
                print("🔄 [CheckinManager] 后台删除了 \(pendingDeletePhotos.count) 条待删除记录")
            }
        } catch {
            print("⚠️ [CheckinManager] 后台删除失败: \(error.localizedDescription)")
        }

        // 3. 清理已同步的删除记录
        try? dataStore.cleanupDeletedPhotos()
    }

    /// 手动触发同步
    func manualSync() async {
        print("🔄 [CheckinManager] 手动触发同步...")
        await performBackgroundSync()
    }

    // MARK: - 辅助方法

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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

// MARK: - 分享功能

extension CheckinManager {
    /// 生成分享图片
    func generateShareImage(photo: CheckinPhoto) async throws -> UIImage {
        guard let url = URL(string: photo.imageUrl) else {
            throw CheckinError.unknown("无效的图片URL")
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        guard let image = UIImage(data: data) else {
            throw CheckinError.unknown("无法加载图片")
        }

        return image
    }
}
