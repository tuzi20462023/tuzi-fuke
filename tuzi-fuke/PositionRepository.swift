//
//  PositionRepository.swift
//  tuzi-fuke (地球新主复刻版)
//
//  位置数据仓储 - 处理Supabase位置数据操作
//  Created by AI Assistant on 2025/11/21.
//

import Foundation
import Supabase

// MARK: - PositionRepository

/// 位置数据仓储 - 负责位置数据的CRUD操作
class PositionRepository: BaseRepository<Position> {

    // MARK: - 初始化
    init() {
        super.init(tableName: "positions")
    }

    // MARK: - 位置特定操作

    /// 批量上传位置数据
    func uploadBatch(_ batch: PositionBatch) async throws -> [Position] {
        await MainActor.run {
            print("📍 [PositionRepository] 开始批量上传位置数据，共 \(batch.count) 条")
        }

        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    let supabase = await SupabaseManager.shared.client
                    let positions = batch.positions

                    // 创建简单的编码数据结构
                    struct PositionUpload: Encodable, Sendable {
                        let id: String
                        let user_id: String
                        let latitude: Double
                        let longitude: Double
                        let altitude: Double
                        let horizontal_accuracy: Double
                        let vertical_accuracy: Double
                        let timestamp: String
                        let speed: Double?
                        let course: Double?
                        let floor: Int?
                        let device_info: String?
                        let app_version: String?
                        let uploaded_at: String
                    }

                    let positionUploads = positions.map { position in
                        PositionUpload(
                            id: position.id.uuidString,
                            user_id: position.userId.uuidString,
                            latitude: position.latitude,
                            longitude: position.longitude,
                            altitude: position.altitude,
                            horizontal_accuracy: position.horizontalAccuracy,
                            vertical_accuracy: position.verticalAccuracy,
                            timestamp: position.timestamp.ISO8601Format(),
                            speed: position.speed,
                            course: position.course,
                            floor: position.floor,
                            device_info: position.deviceInfo,
                            app_version: position.appVersion,
                            uploaded_at: Date().ISO8601Format()
                        )
                    }

                    try await supabase.database
                        .from("positions")
                        .insert(positionUploads)
                        .execute()

                    await MainActor.run {
                        print("✅ [PositionRepository] 真实批量上传成功，共 \(positions.count) 条")
                    }

                    continuation.resume(returning: positions)

                } catch {
                    await MainActor.run {
                        print("❌ [PositionRepository] 上传失败: \(error)")
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// 查询用户的位置历史
    func findByUserId(_ userId: UUID, limit: Int = 100) async throws -> [Position] {
        print("📍 [PositionRepository] 查询用户位置历史: \(userId)")

        // 📝 TODO: 启用Supabase后实现真实查询
        /*
        guard let supabase = SupabaseManager.shared.client else {
            throw DataError.configurationMissing
        }

        let positions: [Position] = try await supabase.database
            .from("positions")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("timestamp", ascending: false)
            .limit(limit)
            .execute()
            .value

        print("✅ [PositionRepository] 查询到 \(positions.count) 条位置记录")
        return positions
        */

        // 🚨 临时实现 - 返回空数组
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3秒
        print("✅ [PositionRepository] 查询完成（临时返回空数组）")
        return []
    }

    /// 查询指定时间范围的位置数据
    func findByTimeRange(
        userId: UUID,
        startTime: Date,
        endTime: Date
    ) async throws -> [Position] {
        print("📍 [PositionRepository] 查询时间范围位置: \(startTime) - \(endTime)")

        // 📝 TODO: 启用Supabase后实现真实查询
        /*
        guard let supabase = SupabaseManager.shared.client else {
            throw DataError.configurationMissing
        }

        let positions: [Position] = try await supabase.database
            .from("positions")
            .select()
            .eq("user_id", value: userId.uuidString)
            .gte("timestamp", value: startTime.ISO8601Format())
            .lte("timestamp", value: endTime.ISO8601Format())
            .order("timestamp", ascending: true)
            .execute()
            .value

        print("✅ [PositionRepository] 查询到 \(positions.count) 条时间范围位置记录")
        return positions
        */

        // 🚨 临时实现
        try await Task.sleep(nanoseconds: 300_000_000)
        print("✅ [PositionRepository] 时间范围查询完成（临时返回空数组）")
        return []
    }

    /// 删除指定时间之前的位置数据（数据清理）
    func deleteOldPositions(userId: UUID, beforeDate: Date) async throws -> Int {
        print("📍 [PositionRepository] 清理旧位置数据，时间点: \(beforeDate)")

        // 📝 TODO: 启用Supabase后实现真实删除
        /*
        guard let supabase = SupabaseManager.shared.client else {
            throw DataError.configurationMissing
        }

        let result = try await supabase.database
            .from("positions")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .lt("timestamp", value: beforeDate.ISO8601Format())
            .execute()

        // 从response中获取删除的行数
        let deletedCount = result.count ?? 0
        print("✅ [PositionRepository] 清理完成，删除了 \(deletedCount) 条旧数据")
        return deletedCount
        */

        // 🚨 临时实现
        try await Task.sleep(nanoseconds: 500_000_000)
        let deletedCount = Int.random(in: 0...10)
        print("✅ [PositionRepository] 清理完成（模拟删除了 \(deletedCount) 条数据）")
        return deletedCount
    }

    /// 统计用户位置数据
    func getPositionStats(userId: UUID) async throws -> PositionStats {
        print("📍 [PositionRepository] 获取用户位置统计: \(userId)")

        // 📝 TODO: 启用Supabase后实现真实统计
        /*
        guard let supabase = SupabaseManager.shared.client else {
            throw DataError.configurationMissing
        }

        // 查询总数
        let countResult = try await supabase.database
            .from("positions")
            .select("*", head: true)
            .eq("user_id", value: userId.uuidString)
            .execute()

        let totalCount = countResult.count ?? 0

        // 查询最新位置
        let latestPositions: [Position] = try await supabase.database
            .from("positions")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("timestamp", ascending: false)
            .limit(1)
            .execute()
            .value

        let latestPosition = latestPositions.first

        return PositionStats(
            totalCount: totalCount,
            latestPosition: latestPosition,
            firstRecordDate: nil, // 需要另外查询
            lastRecordDate: latestPosition?.timestamp
        )
        */

        // 🚨 临时实现
        try await Task.sleep(nanoseconds: 300_000_000)

        let stats = PositionStats(
            totalCount: Int.random(in: 0...100),
            latestPosition: nil,
            firstRecordDate: nil,
            lastRecordDate: nil
        )

        print("✅ [PositionRepository] 统计完成（临时数据）")
        return stats
    }
}

// MARK: - PositionStats 统计数据

/// 位置数据统计信息
struct PositionStats: Codable, Sendable {
    let totalCount: Int
    let latestPosition: Position?
    let firstRecordDate: Date?
    let lastRecordDate: Date?

    var hasData: Bool {
        return totalCount > 0
    }

    var daysSinceFirstRecord: Int? {
        guard let firstDate = firstRecordDate else { return nil }
        return Calendar.current.dateComponents([.day], from: firstDate, to: Date()).day
    }

    func formattedSummary() -> String {
        if totalCount == 0 {
            return "暂无位置记录"
        }

        var summary = "共 \(totalCount) 条位置记录"

        if let latest = latestPosition {
            summary += "\n最新: \(latest.formattedDescription())"
            summary += "\n时间: \(latest.timestamp.formatted(.dateTime))"
        }

        if let days = daysSinceFirstRecord {
            summary += "\n记录天数: \(days) 天"
        }

        return summary
    }
}

// TimeInterval扩展已移除，使用Calendar.dateComponents替代