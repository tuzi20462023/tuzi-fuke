//
//  Territory.swift
//  tuzi-fuke (地球新主复刻版)
//
//  领土数据模型 - 支持圆形和多边形领地
//  参考原项目 EarthLord/Territory.swift
//  Created by AI Assistant on 2025/11/21.
//

import Foundation
import CoreLocation
import MapKit

// MARK: - 领土类型

enum TerritoryType: String, Codable {
    case circle = "circle"     // 圆形领地（长按圈地）
    case polygon = "polygon"   // 多边形领地（行走圈地）
}

// MARK: - 领土数据模型

/// 领土信息模型 - 支持圆形和多边形领地
struct Territory: Codable, Identifiable, Equatable {

    // MARK: - 基础属性
    let id: UUID
    let ownerId: UUID           // 对应 User.id
    var name: String?           // 领地名称（可选）

    // MARK: - 领地类型
    let type: TerritoryType

    // MARK: - 地理信息（圆形领地）
    let centerLatitude: Double
    let centerLongitude: Double
    let radius: Double          // 半径（米），多边形时为等效半径

    // MARK: - 多边形数据（行走圈地）
    let path: [[String: Double]]?   // 路径点数组 [{lat, lon, timestamp?}, ...]
    let polygonWkt: String?         // WKT 格式多边形（用于 PostGIS）

    // MARK: - 边界框（用于快速查询）
    let bboxMinLat: Double?
    let bboxMaxLat: Double?
    let bboxMinLon: Double?
    let bboxMaxLon: Double?

    // MARK: - 面积和周长
    let calculatedArea: Double?     // 实际计算的面积（平方米）
    let perimeter: Double?          // 周长（米）
    let pointCount: Int?            // 路径点数

    // MARK: - 时间戳
    let claimedAt: Date
    let lastUpdatedAt: Date
    let startedAt: Date?            // 开始圈地时间
    let completedAt: Date?          // 完成圈地时间

    // MARK: - 领土状态
    let status: TerritoryStatus
    let level: Int
    let isActive: Bool

    // MARK: - 扩展数据
    let customData: [String: String]?

    // MARK: - 计算属性

    var centerLocation: CLLocation {
        return CLLocation(latitude: centerLatitude, longitude: centerLongitude)
    }

    /// 面积（优先使用实际计算值，否则用圆形公式）
    var area: Double {
        if let calculatedArea = calculatedArea, calculatedArea > 0 {
            return calculatedArea
        }
        return Double.pi * radius * radius
    }

    /// 是否为多边形领地
    var isPolygon: Bool {
        return type == .polygon && path != nil && !path!.isEmpty
    }

    /// 获取多边形顶点坐标
    func toCoordinates() -> [CLLocationCoordinate2D] {
        guard let path = path else { return [] }
        return path.compactMap { point in
            guard let lat = point["lat"], let lon = point["lon"] else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    /// 转换为 CLLocation 数组
    func toLocations() -> [CLLocation] {
        guard let path = path else { return [] }
        return path.compactMap { point in
            guard let lat = point["lat"], let lon = point["lon"] else { return nil }
            let timestamp = point["timestamp"] ?? Date().timeIntervalSince1970
            return CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                altitude: 0,
                horizontalAccuracy: 10,
                verticalAccuracy: -1,
                timestamp: Date(timeIntervalSince1970: timestamp)
            )
        }
    }

    /// 创建 MKPolygon（用于地图渲染）
    func toMKPolygon() -> MKPolygon? {
        let coordinates = toCoordinates()
        guard coordinates.count >= 3 else { return nil }
        // 🔥 修复：直接传递数组，不要用 &var 的方式
        return MKPolygon(coordinates: coordinates, count: coordinates.count)
    }

    // MARK: - CodingKeys (Supabase 兼容)
    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "user_id"        // Supabase 使用 user_id
        case name
        case type
        case centerLatitude = "center_latitude"
        case centerLongitude = "center_longitude"
        case radius
        case path
        case polygonWkt = "polygon"     // Supabase 使用 polygon 字段存 WKT
        case bboxMinLat = "bbox_min_lat"
        case bboxMaxLat = "bbox_max_lat"
        case bboxMinLon = "bbox_min_lon"
        case bboxMaxLon = "bbox_max_lon"
        case calculatedArea = "area"
        case perimeter
        case pointCount = "point_count"
        case claimedAt = "claimed_at"
        case lastUpdatedAt = "last_updated_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case status
        case level
        case isActive = "is_active"
        case customData = "custom_data"
    }

    // MARK: - 自定义解码（处理可选字段和默认值）

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // 必需字段
        id = try container.decode(UUID.self, forKey: .id)
        ownerId = try container.decode(UUID.self, forKey: .ownerId)

        // 可选字段带默认值
        name = try container.decodeIfPresent(String.self, forKey: .name)
        type = try container.decodeIfPresent(TerritoryType.self, forKey: .type) ?? .circle
        centerLatitude = try container.decodeIfPresent(Double.self, forKey: .centerLatitude) ?? 0
        centerLongitude = try container.decodeIfPresent(Double.self, forKey: .centerLongitude) ?? 0
        radius = try container.decodeIfPresent(Double.self, forKey: .radius) ?? 50
        path = try container.decodeIfPresent([[String: Double]].self, forKey: .path)
        polygonWkt = try container.decodeIfPresent(String.self, forKey: .polygonWkt)
        bboxMinLat = try container.decodeIfPresent(Double.self, forKey: .bboxMinLat)
        bboxMaxLat = try container.decodeIfPresent(Double.self, forKey: .bboxMaxLat)
        bboxMinLon = try container.decodeIfPresent(Double.self, forKey: .bboxMinLon)
        bboxMaxLon = try container.decodeIfPresent(Double.self, forKey: .bboxMaxLon)
        calculatedArea = try container.decodeIfPresent(Double.self, forKey: .calculatedArea)
        perimeter = try container.decodeIfPresent(Double.self, forKey: .perimeter)
        pointCount = try container.decodeIfPresent(Int.self, forKey: .pointCount)

        // 日期字段（支持 ISO8601 字符串或 Date）
        if let dateStr = try? container.decode(String.self, forKey: .claimedAt) {
            claimedAt = ISO8601DateFormatter().date(from: dateStr) ?? Date()
        } else {
            claimedAt = try container.decodeIfPresent(Date.self, forKey: .claimedAt) ?? Date()
        }

        if let dateStr = try? container.decode(String.self, forKey: .lastUpdatedAt) {
            lastUpdatedAt = ISO8601DateFormatter().date(from: dateStr) ?? Date()
        } else {
            lastUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt) ?? Date()
        }

        if let dateStr = try? container.decode(String.self, forKey: .startedAt) {
            startedAt = ISO8601DateFormatter().date(from: dateStr)
        } else {
            startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        }

        if let dateStr = try? container.decode(String.self, forKey: .completedAt) {
            completedAt = ISO8601DateFormatter().date(from: dateStr)
        } else {
            completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        }

        status = try container.decodeIfPresent(TerritoryStatus.self, forKey: .status) ?? .active
        level = try container.decodeIfPresent(Int.self, forKey: .level) ?? 1
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        customData = try container.decodeIfPresent([String: String].self, forKey: .customData)
    }

    // MARK: - 完整初始化器

    init(
        id: UUID,
        ownerId: UUID,
        name: String? = nil,
        type: TerritoryType = .circle,
        centerLatitude: Double,
        centerLongitude: Double,
        radius: Double,
        path: [[String: Double]]? = nil,
        polygonWkt: String? = nil,
        bboxMinLat: Double? = nil,
        bboxMaxLat: Double? = nil,
        bboxMinLon: Double? = nil,
        bboxMaxLon: Double? = nil,
        calculatedArea: Double? = nil,
        perimeter: Double? = nil,
        pointCount: Int? = nil,
        claimedAt: Date = Date(),
        lastUpdatedAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        status: TerritoryStatus = .active,
        level: Int = 1,
        isActive: Bool = true,
        customData: [String: String]? = nil
    ) {
        self.id = id
        self.ownerId = ownerId
        self.name = name
        self.type = type
        self.centerLatitude = centerLatitude
        self.centerLongitude = centerLongitude
        self.radius = radius
        self.path = path
        self.polygonWkt = polygonWkt
        self.bboxMinLat = bboxMinLat
        self.bboxMaxLat = bboxMaxLat
        self.bboxMinLon = bboxMinLon
        self.bboxMaxLon = bboxMaxLon
        self.calculatedArea = calculatedArea
        self.perimeter = perimeter
        self.pointCount = pointCount
        self.claimedAt = claimedAt
        self.lastUpdatedAt = lastUpdatedAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.status = status
        self.level = level
        self.isActive = isActive
        self.customData = customData
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

    /// 创建圆形领地的便利方法
    static func createCircle(
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
            name: nil,
            type: .circle,
            centerLatitude: center.coordinate.latitude,
            centerLongitude: center.coordinate.longitude,
            radius: radius,
            claimedAt: now,
            lastUpdatedAt: now,
            status: .active,
            level: level,
            isActive: true,
            customData: customData
        )
    }

    /// 创建多边形领地的便利方法（行走圈地）
    /// 参考原项目 EarthLord/TerritoryManager.swift 的 uploadTerritory 方法
    static func createPolygon(
        ownerId: UUID,
        pathLocations: [CLLocation],
        area: Double,
        name: String? = nil,
        startTime: Date? = nil
    ) -> Territory {
        let now = Date()

        // 转换路径为字典数组
        let pathData: [[String: Double]] = pathLocations.map { location in
            [
                "lat": location.coordinate.latitude,
                "lon": location.coordinate.longitude,
                "timestamp": location.timestamp.timeIntervalSince1970
            ]
        }

        // 计算中心点
        var sumLat: Double = 0
        var sumLon: Double = 0
        for location in pathLocations {
            sumLat += location.coordinate.latitude
            sumLon += location.coordinate.longitude
        }
        let centerLat = sumLat / Double(pathLocations.count)
        let centerLon = sumLon / Double(pathLocations.count)

        // 计算边界框
        let lats = pathLocations.map { $0.coordinate.latitude }
        let lons = pathLocations.map { $0.coordinate.longitude }
        let minLat = lats.min() ?? centerLat
        let maxLat = lats.max() ?? centerLat
        let minLon = lons.min() ?? centerLon
        let maxLon = lons.max() ?? centerLon

        // 计算周长
        var perimeter: Double = 0
        for i in 0..<pathLocations.count {
            let current = pathLocations[i]
            let next = pathLocations[(i + 1) % pathLocations.count]
            perimeter += current.distance(from: next)
        }

        // 构造 WKT 多边形
        var wktCoords = pathLocations.map { "\($0.coordinate.longitude) \($0.coordinate.latitude)" }
        // GeoJSON/WKT 要求首尾相同
        if let first = wktCoords.first {
            wktCoords.append(first)
        }
        let wktPolygon = "SRID=4326;POLYGON((\(wktCoords.joined(separator: ", "))))"

        // 等效半径（用于兼容性）
        let equivalentRadius = sqrt(area / Double.pi)

        return Territory(
            id: UUID(),
            ownerId: ownerId,
            name: name,
            type: .polygon,
            centerLatitude: centerLat,
            centerLongitude: centerLon,
            radius: equivalentRadius,
            path: pathData,
            polygonWkt: wktPolygon,
            bboxMinLat: minLat,
            bboxMaxLat: maxLat,
            bboxMinLon: minLon,
            bboxMaxLon: maxLon,
            calculatedArea: area,
            perimeter: perimeter,
            pointCount: pathLocations.count,
            claimedAt: now,
            lastUpdatedAt: now,
            startedAt: startTime,
            completedAt: now,
            status: .active,
            level: 1,
            isActive: true,
            customData: nil
        )
    }

    /// 向后兼容：创建圆形领地
    static func create(
        ownerId: UUID,
        center: CLLocation,
        radius: Double = 50.0,
        level: Int = 1,
        customData: [String: String]? = nil
    ) -> Territory {
        return createCircle(ownerId: ownerId, center: center, radius: radius, level: level, customData: customData)
    }

    /// 检查指定位置是否在领土范围内
    func contains(_ location: CLLocation) -> Bool {
        if isPolygon {
            // 多边形：使用射线法检测点是否在多边形内
            return containsPointInPolygon(location.coordinate)
        } else {
            // 圆形：检查距离
            let distance = centerLocation.distance(from: location)
            return distance <= radius
        }
    }

    /// 射线法检测点是否在多边形内
    private func containsPointInPolygon(_ point: CLLocationCoordinate2D) -> Bool {
        let coordinates = toCoordinates()
        guard coordinates.count >= 3 else { return false }

        var inside = false
        var j = coordinates.count - 1

        for i in 0..<coordinates.count {
            let xi = coordinates[i].longitude
            let yi = coordinates[i].latitude
            let xj = coordinates[j].longitude
            let yj = coordinates[j].latitude

            let intersect = ((yi > point.latitude) != (yj > point.latitude)) &&
                           (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi)

            if intersect {
                inside = !inside
            }
            j = i
        }

        return inside
    }

    /// 检查与另一个领土是否重叠
    func overlaps(with other: Territory) -> Bool {
        // 简化实现：使用边界框快速判断
        if let minLat = bboxMinLat, let maxLat = bboxMaxLat,
           let minLon = bboxMinLon, let maxLon = bboxMaxLon,
           let otherMinLat = other.bboxMinLat, let otherMaxLat = other.bboxMaxLat,
           let otherMinLon = other.bboxMinLon, let otherMaxLon = other.bboxMaxLon {
            // 边界框不相交则不重叠
            if maxLat < otherMinLat || minLat > otherMaxLat ||
               maxLon < otherMinLon || minLon > otherMaxLon {
                return false
            }
        }

        // 圆形领地：使用中心点距离
        let distance = centerLocation.distance(from: other.centerLocation)
        return distance < (radius + other.radius)
    }

    /// 计算与指定位置的距离
    func distance(to location: CLLocation) -> Double {
        return centerLocation.distance(from: location)
    }

    /// 是否为新圈占的领土 (1小时内)
    var isNewlyClaimed: Bool {
        return Date().timeIntervalSince(claimedAt) < 60 * 60 // 1小时
    }

    /// 获取领土的显示名称
    var displayName: String {
        if let name = name, !name.isEmpty {
            return name
        }
        let shortId = String(id.uuidString.prefix(8))
        return "领地-\(shortId)"
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
    case territoryConflict(String)  // 领地冲突（客户端碰撞检测）

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
        case .territoryConflict(let message):
            return message
        }
    }
}

// MARK: - 调试支持

extension Territory: CustomStringConvertible {
    var description: String {
        let typeStr = type == .polygon ? "多边形" : "圆形"
        let areaStr = Int(area)
        let pointsStr = pointCount != nil ? ", 点数: \(pointCount!)" : ""
        return "Territory(\(typeStr), id: \(String(id.uuidString.prefix(8))), 面积: \(areaStr)m²\(pointsStr), 状态: \(status.displayName))"
    }
}

extension TerritoryStatus: CustomStringConvertible {
    var description: String {
        return "\(emoji) \(displayName)"
    }
}