//
//  Position.swift
//  tuzi-fuke (地球新主复刻版)
//
//  GPS位置数据模型
//  Created by AI Assistant on 2025/11/21.
//

import Foundation
import CoreLocation
import UIKit

// MARK: - Position 数据模型

/// GPS位置记录 - 用于存储用户位置历史
struct Position: Codable, Identifiable, Sendable {

    // MARK: - 基础属性
    let id: UUID
    let userId: UUID
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let timestamp: Date

    // MARK: - 扩展属性
    let speed: Double?              // 移动速度 (m/s)
    let course: Double?             // 移动方向 (度)
    let floor: Int?                 // 楼层 (如果有)

    // MARK: - 元数据
    let deviceInfo: String?         // 设备信息
    let appVersion: String?         // 应用版本
    let uploadedAt: Date?           // 上传时间

    // MARK: - 计算属性

    /// CLLocation坐标
    var coordinate: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// 是否为有效位置
    var isValid: Bool {
        return horizontalAccuracy > 0 && horizontalAccuracy <= 100
    }

    /// 位置精度等级
    var accuracyLevel: PositionAccuracy {
        if horizontalAccuracy <= 5 {
            return .excellent
        } else if horizontalAccuracy <= 10 {
            return .good
        } else if horizontalAccuracy <= 50 {
            return .fair
        } else {
            return .poor
        }
    }

    // MARK: - JSON映射
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case latitude
        case longitude
        case altitude
        case horizontalAccuracy = "horizontal_accuracy"
        case verticalAccuracy = "vertical_accuracy"
        case timestamp
        case speed
        case course
        case floor
        case deviceInfo = "device_info"
        case appVersion = "app_version"
        case uploadedAt = "uploaded_at"
    }

    // MARK: - 初始化方法

    /// 从CLLocation创建Position
    init(from location: CLLocation, userId: UUID) {
        self.id = UUID()
        self.userId = userId
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
        self.horizontalAccuracy = location.horizontalAccuracy
        self.verticalAccuracy = location.verticalAccuracy
        self.timestamp = location.timestamp

        self.speed = location.speed >= 0 ? location.speed : nil
        self.course = location.course >= 0 ? location.course : nil
        self.floor = location.floor?.level

        self.deviceInfo = UIDevice.current.model
        self.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        self.uploadedAt = nil  // 上传时设置
    }

    /// 完整初始化
    init(
        id: UUID = UUID(),
        userId: UUID,
        latitude: Double,
        longitude: Double,
        altitude: Double,
        horizontalAccuracy: Double,
        verticalAccuracy: Double,
        timestamp: Date,
        speed: Double? = nil,
        course: Double? = nil,
        floor: Int? = nil,
        deviceInfo: String? = nil,
        appVersion: String? = nil,
        uploadedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.timestamp = timestamp
        self.speed = speed
        self.course = course
        self.floor = floor
        self.deviceInfo = deviceInfo
        self.appVersion = appVersion
        self.uploadedAt = uploadedAt
    }

    // MARK: - 便利方法

    /// 转换为CLLocation
    func toCLLocation() -> CLLocation {
        return CLLocation(
            coordinate: coordinate,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            timestamp: timestamp
        )
    }

    /// 计算与另一个位置的距离
    func distance(to other: Position) -> CLLocationDistance {
        let location1 = self.toCLLocation()
        let location2 = other.toCLLocation()
        return location1.distance(from: location2)
    }

    /// 格式化显示
    func formattedDescription() -> String {
        return String(format: "%.6f, %.6f (±%.1fm)", latitude, longitude, horizontalAccuracy)
    }
}

// MARK: - PositionAccuracy 枚举

/// 位置精度等级
enum PositionAccuracy: String, CaseIterable, Codable {
    case excellent = "excellent"    // ≤5米
    case good = "good"              // ≤10米
    case fair = "fair"              // ≤50米
    case poor = "poor"              // >50米

    var description: String {
        switch self {
        case .excellent: return "优秀 (≤5m)"
        case .good: return "良好 (≤10m)"
        case .fair: return "一般 (≤50m)"
        case .poor: return "较差 (>50m)"
        }
    }

    var color: String {
        switch self {
        case .excellent: return "🟢"
        case .good: return "🟡"
        case .fair: return "🟠"
        case .poor: return "🔴"
        }
    }
}

// MARK: - PositionUploadStatus 枚举

/// 位置上传状态
enum PositionUploadStatus {
    case pending        // 等待上传
    case uploading      // 上传中
    case uploaded       // 已上传
    case failed(Error)  // 上传失败

    var description: String {
        switch self {
        case .pending: return "等待上传"
        case .uploading: return "上传中..."
        case .uploaded: return "已上传"
        case .failed(let error): return "上传失败: \(error.localizedDescription)"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "⏳"
        case .uploading: return "⬆️"
        case .uploaded: return "✅"
        case .failed: return "❌"
        }
    }
}

// MARK: - PositionBatch 批量上传

/// 位置批量上传数据
struct PositionBatch: Sendable {
    let positions: [Position]
    let batchId: UUID
    let createdAt: Date

    init(positions: [Position]) {
        self.positions = positions
        self.batchId = UUID()
        self.createdAt = Date()
    }

    var count: Int {
        return positions.count
    }

    var timeRange: (start: Date, end: Date)? {
        guard !positions.isEmpty else {
            return nil
        }
        let sortedPositions = positions.sorted { $0.timestamp < $1.timestamp }
        return (start: sortedPositions.first!.timestamp, end: sortedPositions.last!.timestamp)
    }
}