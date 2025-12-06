//
//  CheckinDataStore.swift
//  tuzi-fuke (地球新主复刻版)
//
//  SwiftData 打卡记录本地缓存
//  Created by AI Assistant on 2025/12/05.
//

import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - 同步状态

enum SyncStatus: String, Codable {
    case synced = "synced"        // 已同步到云端
    case pending = "pending"      // 等待同步
    case pendingDelete = "pending_delete"  // 等待删除
    case failed = "failed"        // 同步失败
}

// MARK: - SwiftData 模型

@Model
final class CachedCheckinPhoto {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var buildingId: UUID?

    // 位置信息
    var locationName: String?
    var latitude: Double?
    var longitude: Double?

    // 环境信息
    var weather: String?
    var temperature: String?
    var timeOfDay: String?

    // 生成信息
    var mode: String  // CheckinMode.rawValue
    var prompt: String?

    // 图片URL
    var imageUrl: String
    var thumbnailUrl: String?

    // 状态
    var isPublic: Bool
    var isDeleted: Bool

    // 同步状态
    var syncStatus: String  // SyncStatus.rawValue
    var syncError: String?
    var lastSyncAttempt: Date?

    // 时间戳
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        userId: UUID,
        buildingId: UUID? = nil,
        locationName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        weather: String? = nil,
        temperature: String? = nil,
        timeOfDay: String? = nil,
        mode: String,
        prompt: String? = nil,
        imageUrl: String,
        thumbnailUrl: String? = nil,
        isPublic: Bool = true,
        isDeleted: Bool = false,
        syncStatus: String = SyncStatus.pending.rawValue,
        syncError: String? = nil,
        lastSyncAttempt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.buildingId = buildingId
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.weather = weather
        self.temperature = temperature
        self.timeOfDay = timeOfDay
        self.mode = mode
        self.prompt = prompt
        self.imageUrl = imageUrl
        self.thumbnailUrl = thumbnailUrl
        self.isPublic = isPublic
        self.isDeleted = isDeleted
        self.syncStatus = syncStatus
        self.syncError = syncError
        self.lastSyncAttempt = lastSyncAttempt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 从云端模型创建
    static func from(_ photo: CheckinPhoto) -> CachedCheckinPhoto {
        return CachedCheckinPhoto(
            id: photo.id,
            userId: photo.userId,
            buildingId: photo.buildingId,
            locationName: photo.locationName,
            latitude: photo.latitude,
            longitude: photo.longitude,
            weather: photo.weather,
            temperature: photo.temperature,
            timeOfDay: photo.timeOfDay,
            mode: photo.mode.rawValue,
            prompt: photo.prompt,
            imageUrl: photo.imageUrl,
            thumbnailUrl: photo.thumbnailUrl,
            isPublic: photo.isPublic,
            isDeleted: photo.isDeleted,
            syncStatus: SyncStatus.synced.rawValue,
            createdAt: photo.createdAt,
            updatedAt: photo.updatedAt
        )
    }

    /// 转换为云端模型
    func toCheckinPhoto() -> CheckinPhoto? {
        guard let modeEnum = CheckinMode(rawValue: mode) else { return nil }

        return CheckinPhoto(
            id: id,
            userId: userId,
            buildingId: buildingId,
            locationName: locationName,
            latitude: latitude,
            longitude: longitude,
            weather: weather,
            temperature: temperature,
            timeOfDay: timeOfDay,
            mode: modeEnum,
            prompt: prompt,
            imageUrl: imageUrl,
            thumbnailUrl: thumbnailUrl,
            isPublic: isPublic,
            isDeleted: isDeleted,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - 本地数据存储管理器

@MainActor
class CheckinDataStore: ObservableObject {
    static let shared = CheckinDataStore()

    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?

    @Published var isReady = false

    private init() {
        setupContainer()
    }

    // MARK: - 初始化

    private func setupContainer() {
        do {
            let schema = Schema([
                CachedCheckinPhoto.self
            ])

            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )

            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )

            modelContext = ModelContext(modelContainer!)
            isReady = true

            print("✅ [CheckinDataStore] SwiftData 初始化成功")

        } catch {
            print("❌ [CheckinDataStore] SwiftData 初始化失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 创建记录

    /// 保存新的打卡记录到本地
    func saveCheckinPhoto(
        userId: UUID,
        buildingId: UUID?,
        locationName: String?,
        latitude: Double?,
        longitude: Double?,
        weather: String?,
        temperature: String?,
        timeOfDay: String?,
        mode: String,
        prompt: String?,
        imageUrl: String,
        thumbnailUrl: String?,
        isPublic: Bool = true
    ) throws -> CachedCheckinPhoto {
        guard let context = modelContext else {
            throw NSError(domain: "CheckinDataStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "ModelContext 未初始化"])
        }

        let photo = CachedCheckinPhoto(
            userId: userId,
            buildingId: buildingId,
            locationName: locationName,
            latitude: latitude,
            longitude: longitude,
            weather: weather,
            temperature: temperature,
            timeOfDay: timeOfDay,
            mode: mode,
            prompt: prompt,
            imageUrl: imageUrl,
            thumbnailUrl: thumbnailUrl,
            isPublic: isPublic,
            syncStatus: SyncStatus.pending.rawValue
        )

        context.insert(photo)
        try context.save()

        print("✅ [CheckinDataStore] 本地保存成功: \(photo.id)")
        return photo
    }

    // MARK: - 查询记录

    /// 获取用户的所有打卡记录（未删除）
    func fetchCheckinPhotos(for userId: UUID, limit: Int = 20) throws -> [CachedCheckinPhoto] {
        guard let context = modelContext else {
            throw NSError(domain: "CheckinDataStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "ModelContext 未初始化"])
        }

        let descriptor = FetchDescriptor<CachedCheckinPhoto>(
            predicate: #Predicate { photo in
                photo.userId == userId && photo.isDeleted == false
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        var fetchDescriptor = descriptor
        fetchDescriptor.fetchLimit = limit

        let photos = try context.fetch(fetchDescriptor)
        print("✅ [CheckinDataStore] 本地查询到 \(photos.count) 条记录")
        return photos
    }

    /// 获取待同步的记录
    func fetchPendingPhotos() throws -> [CachedCheckinPhoto] {
        guard let context = modelContext else {
            throw NSError(domain: "CheckinDataStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "ModelContext 未初始化"])
        }

        let pendingStatus = "pending"
        let descriptor = FetchDescriptor<CachedCheckinPhoto>(
            predicate: #Predicate { photo in
                photo.syncStatus == pendingStatus
            }
        )

        return try context.fetch(descriptor)
    }

    /// 获取待删除的记录
    func fetchPendingDeletePhotos() throws -> [CachedCheckinPhoto] {
        guard let context = modelContext else {
            throw NSError(domain: "CheckinDataStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "ModelContext 未初始化"])
        }

        let pendingDeleteStatus = "pending_delete"
        let descriptor = FetchDescriptor<CachedCheckinPhoto>(
            predicate: #Predicate { photo in
                photo.syncStatus == pendingDeleteStatus
            }
        )

        return try context.fetch(descriptor)
    }

    /// 根据ID查询记录
    func fetchPhoto(by id: UUID) throws -> CachedCheckinPhoto? {
        guard let context = modelContext else {
            throw NSError(domain: "CheckinDataStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "ModelContext 未初始化"])
        }

        let descriptor = FetchDescriptor<CachedCheckinPhoto>(
            predicate: #Predicate { photo in
                photo.id == id
            }
        )

        let photos = try context.fetch(descriptor)
        return photos.first
    }

    // MARK: - 更新记录

    /// 标记记录为已同步
    func markAsSynced(_ photo: CachedCheckinPhoto) throws {
        guard let context = modelContext else {
            throw NSError(domain: "CheckinDataStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "ModelContext 未初始化"])
        }

        photo.syncStatus = SyncStatus.synced.rawValue
        photo.syncError = nil
        photo.lastSyncAttempt = Date()
        photo.updatedAt = Date()

        try context.save()
        print("✅ [CheckinDataStore] 标记为已同步: \(photo.id)")
    }

    /// 标记同步失败
    func markSyncFailed(_ photo: CachedCheckinPhoto, error: String) throws {
        guard let context = modelContext else {
            throw NSError(domain: "CheckinDataStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "ModelContext 未初始化"])
        }

        photo.syncStatus = SyncStatus.failed.rawValue
        photo.syncError = error
        photo.lastSyncAttempt = Date()
        photo.updatedAt = Date()

        try context.save()
        print("⚠️ [CheckinDataStore] 标记同步失败: \(photo.id), 错误: \(error)")
    }

    /// 软删除记录（标记为待删除）
    func markForDeletion(_ photo: CachedCheckinPhoto) throws {
        guard let context = modelContext else {
            throw NSError(domain: "CheckinDataStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "ModelContext 未初始化"])
        }

        photo.isDeleted = true
        photo.syncStatus = SyncStatus.pendingDelete.rawValue
        photo.updatedAt = Date()

        try context.save()
        print("✅ [CheckinDataStore] 标记为待删除: \(photo.id)")
    }

    // MARK: - 删除记录

    /// 物理删除记录
    func deletePhoto(_ photo: CachedCheckinPhoto) throws {
        guard let context = modelContext else {
            throw NSError(domain: "CheckinDataStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "ModelContext 未初始化"])
        }

        context.delete(photo)
        try context.save()
        print("✅ [CheckinDataStore] 物理删除记录: \(photo.id)")
    }

    // MARK: - 批量同步

    /// 从云端数据更新或插入本地缓存
    func upsertFromCloud(_ cloudPhoto: CheckinPhoto) throws {
        guard let context = modelContext else {
            throw NSError(domain: "CheckinDataStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "ModelContext 未初始化"])
        }

        // 检查是否已存在
        if let existing = try fetchPhoto(by: cloudPhoto.id) {
            // 更新现有记录
            existing.buildingId = cloudPhoto.buildingId
            existing.locationName = cloudPhoto.locationName
            existing.latitude = cloudPhoto.latitude
            existing.longitude = cloudPhoto.longitude
            existing.weather = cloudPhoto.weather
            existing.temperature = cloudPhoto.temperature
            existing.timeOfDay = cloudPhoto.timeOfDay
            existing.mode = cloudPhoto.mode.rawValue
            existing.prompt = cloudPhoto.prompt
            existing.imageUrl = cloudPhoto.imageUrl
            existing.thumbnailUrl = cloudPhoto.thumbnailUrl
            existing.isPublic = cloudPhoto.isPublic
            existing.isDeleted = cloudPhoto.isDeleted
            existing.syncStatus = SyncStatus.synced.rawValue
            existing.updatedAt = cloudPhoto.updatedAt

            print("🔄 [CheckinDataStore] 更新本地记录: \(cloudPhoto.id)")
        } else {
            // 插入新记录
            let cached = CachedCheckinPhoto.from(cloudPhoto)
            context.insert(cached)
            print("➕ [CheckinDataStore] 插入新记录: \(cloudPhoto.id)")
        }

        try context.save()
    }

    /// 批量更新云端数据到本地
    func syncFromCloud(_ cloudPhotos: [CheckinPhoto]) throws {
        for photo in cloudPhotos {
            try upsertFromCloud(photo)
        }
        print("✅ [CheckinDataStore] 批量同步完成，共 \(cloudPhotos.count) 条")
    }

    // MARK: - 清理

    /// 清理已删除的记录（已同步删除的）
    func cleanupDeletedPhotos() throws {
        guard let context = modelContext else {
            throw NSError(domain: "CheckinDataStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "ModelContext 未初始化"])
        }

        let syncedStatus = "synced"
        let descriptor = FetchDescriptor<CachedCheckinPhoto>(
            predicate: #Predicate { photo in
                photo.isDeleted == true && photo.syncStatus == syncedStatus
            }
        )

        let photos = try context.fetch(descriptor)
        for photo in photos {
            context.delete(photo)
        }

        try context.save()
        print("🧹 [CheckinDataStore] 清理了 \(photos.count) 条已删除记录")
    }
}
