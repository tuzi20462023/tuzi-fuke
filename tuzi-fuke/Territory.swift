//
//  Territory.swift
//  tuzi-fuke (地球新主复刻版)
//
//  领土数据模型 - 支持可变体架构
//  Created by AI Assistant on 2025/11/21.
//

import Foundation
import CoreLocation

// MARK: - 领土数据模型

/// 领土信息模型 - 支持多种游戏变体的领土系统
struct Territory: Codable, Identifiable, Equatable {

    // MARK: - 基础属性
    let id: UUID
    let ownerId: UUID // 对应User.id

    // MARK: - 地理信息
    let centerLatitude: Double
    let centerLongitude: Double
    let radius: Double // 半径（米）

    // MARK: - 时间戳
    let claimedAt: Date
    let lastUpdatedAt: Date

    // MARK: - 领土状态
    let status: TerritoryStatus
    let level: Int

    // MARK: - 扩展数据 (支持变体自定义)
    let customData: [String: String]?

    // MARK: - 计算属性
    var centerLocation: CLLocation {
        return CLLocation(latitude: centerLatitude, longitude: centerLongitude)
    }

    var area: Double {
        // 计算圆形区域面积（平方米）
        return Double.pi * radius * radius
    }

    // MARK: - CodingKeys (Supabase兼容)
    enum CodingKeys: String, CodingKey {
        case id = "id"
        case ownerId = "owner_id"
        case centerLatitude = "center_latitude"
        case centerLongitude = "center_longitude"
        case radius = "radius"
        case claimedAt = "claimed_at"
        case lastUpdatedAt = "last_updated_at"
        case status = "status"
        case level = "level"
        case customData = "custom_data"
    }
}

// MARK: - 领土状态枚举

enum TerritoryStatus: String, Codable, CaseIterable {
    case active = "active"         // 活跃状态
    case contested = "contested"   // 争夺中
    case abandoned = "abandoned"   // 已废弃
    case protected = "protected"   // 受保护状态

    var displayName: String {
        switch self {
        case .active: return "活跃"
        case .contested: return "争夺中"
        case .abandoned: return "废弃"
        case .protected: return "受保护"
        }
    }

    var emoji: String {
        switch self {
        case .active: return "✅"
        case .contested: return "⚔️"
        case .abandoned: return "🏚️"
        case .protected: return "🛡️"
        }
    }
}

// MARK: - Territory 扩展方法

extension Territory {

    /// 创建新领土的便利方法
    static func create(
        ownerId: UUID,
        center: CLLocation,
        radius: Double = 50.0,
        level: Int = 1,
        customData: [String: String]? = nil
    ) -> Territory {
        let now = Date()

        return Territory(
            id: UUID(),
            ownerId: ownerId,
            centerLatitude: center.coordinate.latitude,
            centerLongitude: center.coordinate.longitude,
            radius: radius,
            claimedAt: now,
            lastUpdatedAt: now,
            status: .active,
            level: level,
            customData: customData
        )
    }

    /// 检查指定位置是否在领土范围内
    func contains(_ location: CLLocation) -> Bool {
        let distance = centerLocation.distance(from: location)
        return distance <= radius
    }

    /// 检查与另一个领土是否重叠
    func overlaps(with other: Territory) -> Bool {
        let distance = centerLocation.distance(from: other.centerLocation)
        return distance < (radius + other.radius)
    }

    /// 计算与指定位置的距离
    func distance(to location: CLLocation) -> Double {
        return centerLocation.distance(from: location)
    }

    /// 更新领土状态
    func updatedStatus(_ newStatus: TerritoryStatus) -> Territory {
        return Territory(
            id: self.id,
            ownerId: self.ownerId,
            centerLatitude: self.centerLatitude,
            centerLongitude: self.centerLongitude,
            radius: self.radius,
            claimedAt: self.claimedAt,
            lastUpdatedAt: Date(),
            status: newStatus,
            level: self.level,
            customData: self.customData
        )
    }

    /// 升级领土
    func upgraded() -> Territory {
        return Territory(
            id: self.id,
            ownerId: self.ownerId,
            centerLatitude: self.centerLatitude,
            centerLongitude: self.centerLongitude,
            radius: self.radius * 1.2, // 升级时半径增加20%
            claimedAt: self.claimedAt,
            lastUpdatedAt: Date(),
            status: self.status,
            level: self.level + 1,
            customData: self.customData
        )
    }

    /// 是否为新圈占的领土 (1小时内)
    var isNewlyClaimed: Bool {
        return Date().timeIntervalSince(claimedAt) < 60 * 60 // 1小时
    }

    /// 获取领土的显示名称
    var displayName: String {
        let shortId = String(id.uuidString.prefix(8))
        return "领土-\(shortId)"
    }

    /// 获取领土等级对应的颜色
    var levelColor: String {
        switch level {
        case 1: return "#4CAF50"      // 绿色
        case 2: return "#2196F3"      // 蓝色
        case 3: return "#9C27B0"      // 紫色
        case 4: return "#FF9800"      // 橙色
        case 5...: return "#F44336"   // 红色
        default: return "#757575"     // 灰色
        }
    }
}

// MARK: - 领土验证

extension Territory {

    /// 验证领土数据的有效性
    func isValid() -> Bool {
        // 基础验证
        guard radius > 0 && radius <= 1000 else { return false } // 半径1-1000米
        guard level > 0 && level <= 100 else { return false }    // 等级1-100
        guard centerLatitude >= -90 && centerLatitude <= 90 else { return false }
        guard centerLongitude >= -180 && centerLongitude <= 180 else { return false }

        return true
    }

    /// 验证领土是否可以在指定位置圈占
    static func canClaim(
        at location: CLLocation,
        radius: Double,
        existingTerritories: [Territory]
    ) -> TerritoryClaimResult {

        // 检查半径是否合理
        guard radius >= 10 && radius <= 500 else {
            return .failed(.invalidRadius)
        }

        // 检查位置坐标是否有效
        let coordinate = location.coordinate
        guard coordinate.latitude >= -90 && coordinate.latitude <= 90,
              coordinate.longitude >= -180 && coordinate.longitude <= 180 else {
            return .failed(.invalidLocation)
        }

        // 检查是否与现有领土重叠
        let newTerritory = Territory.create(
            ownerId: UUID(), // 临时ID
            center: location,
            radius: radius
        )

        for existing in existingTerritories {
            if newTerritory.overlaps(with: existing) {
                return .failed(.overlapsExisting(existing.id))
            }
        }

        return .success
    }
}

// MARK: - 领土圈占结果

enum TerritoryClaimResult {
    case success
    case failed(TerritoryClaimError)

    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}

enum TerritoryClaimError: Error, LocalizedError {
    case invalidRadius
    case invalidLocation
    case overlapsExisting(UUID)
    case tooManyTerritories
    case insufficientLevel

    var errorDescription: String? {
        switch self {
        case .invalidRadius:
            return "圈占半径无效，请选择10-500米范围"
        case .invalidLocation:
            return "位置坐标无效"
        case .overlapsExisting:
            return "与现有领土重叠，请选择其他位置"
        case .tooManyTerritories:
            return "领土数量已达上限"
        case .insufficientLevel:
            return "等级不足，无法圈占此区域"
        }
    }
}

// MARK: - 调试支持

extension Territory: CustomStringConvertible {
    var description: String {
        return "Territory(id: \(String(id.uuidString.prefix(8))), center: \(centerLatitude), \(centerLongitude), radius: \(radius)m, level: \(level), status: \(status.displayName))"
    }
}

extension TerritoryStatus: CustomStringConvertible {
    var description: String {
        return "\(emoji) \(displayName)"
    }
}