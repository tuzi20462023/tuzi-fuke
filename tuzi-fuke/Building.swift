//
//  Building.swift
//  tuzi-fuke (地球新主复刻版)
//
//  建筑数据模型 - 支持可变体架构
//  Created by AI Assistant on 2025/11/21.
//  Updated: DAY8 - 添加 BuildingTemplate, PlayerBuilding 等新模型
//

import Foundation
import CoreLocation

// MARK: - ========== DAY8 新增模型 ==========

// MARK: - 建筑模板 (从数据库读取)

/// 建筑模板 - 定义可建造的建筑类型
struct BuildingTemplate: Identifiable, Codable {
    let id: UUID
    let templateId: String          // 如 "shelter_basic"
    let name: String
    let tier: Int                   // 1/2/3 级建筑
    let category: NewBuildingCategory
    let description: String?
    let icon: String                // SF Symbol 名称
    let requiredLevel: Int
    let requiredResources: [String: Int]
    let buildTimeHours: Double
    let effects: [String: AnyCodableValue]
    let maxPerTerritory: Int
    let maxLevel: Int
    let durabilityMax: Int
    let isActive: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case templateId = "template_id"
        case name
        case tier
        case category
        case description
        case icon
        case requiredLevel = "required_level"
        case requiredResources = "required_resources"
        case buildTimeHours = "build_time_hours"
        case effects
        case maxPerTerritory = "max_per_territory"
        case maxLevel = "max_level"
        case durabilityMax = "durability_max"
        case isActive = "is_active"
        case createdAt = "created_at"
    }

    /// 格式化建造时间显示
    var formattedBuildTime: String {
        if buildTimeHours < 1 {
            return "\(Int(buildTimeHours * 60))分钟"
        } else if buildTimeHours == Double(Int(buildTimeHours)) {
            return "\(Int(buildTimeHours))小时"
        } else {
            let hours = Int(buildTimeHours)
            let minutes = Int((buildTimeHours - Double(hours)) * 60)
            return "\(hours)小时\(minutes)分钟"
        }
    }

    /// 格式化资源需求显示
    var formattedResources: String {
        requiredResources.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
    }
}

// MARK: - 新建筑分类 (DAY8)

enum NewBuildingCategory: String, Codable, CaseIterable {
    case survival = "survival"       // 生存
    case storage = "storage"         // 存储
    case production = "production"   // 生产
    case energy = "energy"           // 能源
    case defense = "defense"         // 防御

    var displayName: String {
        switch self {
        case .survival: return "生存"
        case .storage: return "存储"
        case .production: return "生产"
        case .energy: return "能源"
        case .defense: return "防御"
        }
    }

    var icon: String {
        switch self {
        case .survival: return "house.fill"
        case .storage: return "archivebox.fill"
        case .production: return "hammer.fill"
        case .energy: return "bolt.fill"
        case .defense: return "shield.fill"
        }
    }

    var color: String {
        switch self {
        case .survival: return "blue"
        case .storage: return "brown"
        case .production: return "green"
        case .energy: return "yellow"
        case .defense: return "red"
        }
    }
}

// MARK: - 玩家建筑 (已建造的建筑)

/// 玩家已建造的建筑
struct PlayerBuilding: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let territoryId: UUID
    let buildingTemplateId: UUID?
    var buildingName: String
    let buildingTemplateKey: String     // 如 "shelter_basic"
    let location: GeoJSONPoint?
    var status: PlayerBuildingStatus
    let buildStartedAt: Date
    var buildCompletedAt: Date?
    let buildTimeHours: Double?
    var level: Int
    var durability: Int
    var durabilityMax: Int
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case territoryId = "territory_id"
        case buildingTemplateId = "building_template_id"
        case buildingName = "building_name"
        case buildingTemplateKey = "building_template_key"
        case location
        case status
        case buildStartedAt = "build_started_at"
        case buildCompletedAt = "build_completed_at"
        case buildTimeHours = "build_time_hours"
        case level
        case durability
        case durabilityMax = "durability_max"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// 计算剩余建造时间（秒）
    func remainingBuildTime() -> TimeInterval {
        guard status == .constructing, let completedAt = buildCompletedAt else {
            return 0
        }
        return max(0, completedAt.timeIntervalSinceNow)
    }

    /// 建造进度百分比 (0.0 - 1.0)
    func buildProgress() -> Double {
        guard status == .constructing, let hours = buildTimeHours else {
            return status == .active ? 1.0 : 0.0
        }
        let totalTime = hours * 3600
        let elapsed = Date().timeIntervalSince(buildStartedAt)
        return min(1.0, elapsed / totalTime)
    }

    /// 格式化剩余时间
    var formattedRemainingTime: String {
        let remaining = remainingBuildTime()
        if remaining <= 0 {
            return "即将完成"
        }
        let hours = Int(remaining / 3600)
        let minutes = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 0 {
            return "\(hours)小时\(minutes)分钟"
        } else {
            return "\(minutes)分钟"
        }
    }

    /// 获取坐标
    var coordinate: CLLocationCoordinate2D? {
        guard let loc = location, loc.coordinates.count >= 2 else { return nil }
        return CLLocationCoordinate2D(latitude: loc.coordinates[1], longitude: loc.coordinates[0])
    }
}

// MARK: - 玩家建筑状态

enum PlayerBuildingStatus: String, Codable {
    case constructing = "constructing"  // 建造中
    case active = "active"              // 运行中
    case damaged = "damaged"            // 损坏
    case inactive = "inactive"          // 停用

    var displayName: String {
        switch self {
        case .constructing: return "建造中"
        case .active: return "运行中"
        case .damaged: return "已损坏"
        case .inactive: return "已停用"
        }
    }

    var color: String {
        switch self {
        case .constructing: return "blue"
        case .active: return "green"
        case .damaged: return "orange"
        case .inactive: return "gray"
        }
    }
}

// MARK: - GeoJSON Point

struct GeoJSONPoint: Codable, Sendable {
    let type: String
    let coordinates: [Double]  // [longitude, latitude]

    init(longitude: Double, latitude: Double) {
        self.type = "Point"
        self.coordinates = [longitude, latitude]
    }
}

// MARK: - 建造请求

struct BuildingConstructionRequest {
    let templateId: String
    let territoryId: UUID
    let location: CLLocationCoordinate2D?
    let customName: String?
}

// MARK: - 建造结果

struct BuildingConstructionResult {
    let success: Bool
    let building: PlayerBuilding?
    let error: BuildingConstructionError?
    let message: String
}

enum BuildingConstructionError: Error, LocalizedError {
    case insufficientResources([String: Int])
    case levelTooLow(required: Int, current: Int)
    case maxBuildingsReached(Int)
    case outsideTerritory
    case tooCloseToExisting
    case networkError(Error)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .insufficientResources(let resources):
            let list = resources.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            return "资源不足: \(list)"
        case .levelTooLow(let required, let current):
            return "等级不足（需要\(required)级，当前\(current)级）"
        case .maxBuildingsReached(let max):
            return "已达到该建筑的最大数量（\(max)）"
        case .outsideTerritory:
            return "建筑必须建在领地内"
        case .tooCloseToExisting:
            return "距离其他建筑太近"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .unknown(let msg):
            return msg
        }
    }
}

// MARK: - AnyCodableValue (简化版，用于解析 JSONB)

struct AnyCodableValue: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let stringVal = try? container.decode(String.self) {
            value = stringVal
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else {
            value = 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intVal = value as? Int {
            try container.encode(intVal)
        } else if let doubleVal = value as? Double {
            try container.encode(doubleVal)
        } else if let stringVal = value as? String {
            try container.encode(stringVal)
        } else if let boolVal = value as? Bool {
            try container.encode(boolVal)
        }
    }

    var intValue: Int? { value as? Int }
    var doubleValue: Double? { value as? Double }
    var stringValue: String? { value as? String }

    /// 用于 UI 显示的字符串
    var displayString: String {
        if let intVal = value as? Int {
            return "\(intVal)"
        } else if let doubleVal = value as? Double {
            return String(format: "%.1f", doubleVal)
        } else if let stringVal = value as? String {
            return stringVal
        } else if let boolVal = value as? Bool {
            return boolVal ? "是" : "否"
        }
        return "\(value)"
    }
}

// MARK: - ========== 以下是原有的简化版模型（保持向后兼容）==========

// MARK: - 建筑数据模型

/// 建筑信息模型 - 支持多种游戏变体的建筑系统
struct Building: Codable, Identifiable, Equatable {

    // MARK: - 基础属性
    let id: UUID
    let ownerId: UUID      // 对应User.id
    let territoryId: UUID  // 所属领土ID

    // MARK: - 地理信息
    let latitude: Double
    let longitude: Double

    // MARK: - 建筑属性
    let buildingType: BuildingType
    let level: Int

    // MARK: - 时间戳
    let builtAt: Date
    let lastUpdatedAt: Date

    // MARK: - 建筑状态
    let status: BuildingStatus
    let health: Double // 0.0-1.0

    // MARK: - 扩展数据 (支持变体自定义)
    let customData: [String: String]?

    // MARK: - 计算属性
    var location: CLLocation {
        return CLLocation(latitude: latitude, longitude: longitude)
    }

    var isOperational: Bool {
        return status == .active && health > 0.1
    }

    // MARK: - CodingKeys (Supabase兼容)
    enum CodingKeys: String, CodingKey {
        case id = "id"
        case ownerId = "owner_id"
        case territoryId = "territory_id"
        case latitude = "latitude"
        case longitude = "longitude"
        case buildingType = "building_type"
        case level = "level"
        case builtAt = "built_at"
        case lastUpdatedAt = "last_updated_at"
        case status = "status"
        case health = "health"
        case customData = "custom_data"
    }
}

// MARK: - 建筑类型枚举

enum BuildingType: String, Codable, CaseIterable {
    // 基础建筑类型 (支持所有变体)
    case residence = "residence"       // 住宅
    case factory = "factory"           // 工厂
    case farm = "farm"                 // 农场
    case warehouse = "warehouse"       // 仓库
    case workshop = "workshop"         // 维修站

    // 防御建筑
    case watchtower = "watchtower"     // 瞭望塔
    case bunker = "bunker"             // 地堡

    // 资源建筑
    case mine = "mine"                 // 矿场
    case powerPlant = "power_plant"    // 发电站
    case waterTreatment = "water_treatment" // 净水站

    var displayName: String {
        switch self {
        case .residence: return "住宅"
        case .factory: return "工厂"
        case .farm: return "农场"
        case .warehouse: return "仓库"
        case .workshop: return "维修站"
        case .watchtower: return "瞭望塔"
        case .bunker: return "地堡"
        case .mine: return "矿场"
        case .powerPlant: return "发电站"
        case .waterTreatment: return "净水站"
        }
    }

    var emoji: String {
        switch self {
        case .residence: return "🏠"
        case .factory: return "🏭"
        case .farm: return "🌾"
        case .warehouse: return "📦"
        case .workshop: return "🔧"
        case .watchtower: return "🗼"
        case .bunker: return "🏰"
        case .mine: return "⛏️"
        case .powerPlant: return "⚡"
        case .waterTreatment: return "💧"
        }
    }

    var category: BuildingCategory {
        switch self {
        case .residence:
            return .residential
        case .factory, .workshop, .powerPlant:
            return .industrial
        case .farm, .mine, .waterTreatment:
            return .resource
        case .warehouse:
            return .storage
        case .watchtower, .bunker:
            return .defense
        }
    }

    /// 建筑的基础建造成本
    var baseCost: Int {
        switch self {
        case .residence: return 100
        case .factory: return 200
        case .farm: return 150
        case .warehouse: return 120
        case .workshop: return 180
        case .watchtower: return 80
        case .bunker: return 300
        case .mine: return 250
        case .powerPlant: return 400
        case .waterTreatment: return 220
        }
    }
}

// MARK: - 建筑分类

enum BuildingCategory: String, Codable, CaseIterable {
    case residential = "residential"   // 居住
    case industrial = "industrial"     // 工业
    case resource = "resource"         // 资源
    case storage = "storage"           // 存储
    case defense = "defense"           // 防御

    var displayName: String {
        switch self {
        case .residential: return "居住建筑"
        case .industrial: return "工业建筑"
        case .resource: return "资源建筑"
        case .storage: return "存储建筑"
        case .defense: return "防御建筑"
        }
    }
}

// MARK: - 建筑状态枚举

enum BuildingStatus: String, Codable, CaseIterable {
    case building = "building"       // 建造中
    case active = "active"           // 运行中
    case inactive = "inactive"       // 停用
    case damaged = "damaged"         // 损坏
    case destroyed = "destroyed"     // 已摧毁

    var displayName: String {
        switch self {
        case .building: return "建造中"
        case .active: return "运行中"
        case .inactive: return "停用"
        case .damaged: return "损坏"
        case .destroyed: return "已摧毁"
        }
    }

    var emoji: String {
        switch self {
        case .building: return "🏗️"
        case .active: return "✅"
        case .inactive: return "⏸️"
        case .damaged: return "⚠️"
        case .destroyed: return "💥"
        }
    }
}

// MARK: - Building 扩展方法

extension Building {

    /// 创建新建筑的便利方法
    static func create(
        ownerId: UUID,
        territoryId: UUID,
        location: CLLocation,
        type: BuildingType,
        level: Int = 1,
        customData: [String: String]? = nil
    ) -> Building {
        let now = Date()

        return Building(
            id: UUID(),
            ownerId: ownerId,
            territoryId: territoryId,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            buildingType: type,
            level: level,
            builtAt: now,
            lastUpdatedAt: now,
            status: .building,
            health: 1.0,
            customData: customData
        )
    }

    /// 计算与指定位置的距离
    func distance(to location: CLLocation) -> Double {
        return self.location.distance(from: location)
    }

    /// 更新建筑状态
    func updatedStatus(_ newStatus: BuildingStatus) -> Building {
        return Building(
            id: self.id,
            ownerId: self.ownerId,
            territoryId: self.territoryId,
            latitude: self.latitude,
            longitude: self.longitude,
            buildingType: self.buildingType,
            level: self.level,
            builtAt: self.builtAt,
            lastUpdatedAt: Date(),
            status: newStatus,
            health: self.health,
            customData: self.customData
        )
    }

    /// 升级建筑
    func upgraded() -> Building {
        return Building(
            id: self.id,
            ownerId: self.ownerId,
            territoryId: self.territoryId,
            latitude: self.latitude,
            longitude: self.longitude,
            buildingType: self.buildingType,
            level: self.level + 1,
            builtAt: self.builtAt,
            lastUpdatedAt: Date(),
            status: self.status,
            health: self.health,
            customData: self.customData
        )
    }

    /// 修复建筑
    func repaired() -> Building {
        return Building(
            id: self.id,
            ownerId: self.ownerId,
            territoryId: self.territoryId,
            latitude: self.latitude,
            longitude: self.longitude,
            buildingType: self.buildingType,
            level: self.level,
            builtAt: self.builtAt,
            lastUpdatedAt: Date(),
            status: .active,
            health: 1.0,
            customData: self.customData
        )
    }

    /// 更新建筑健康度
    func updatedHealth(_ newHealth: Double) -> Building {
        let clampedHealth = max(0.0, min(1.0, newHealth))
        let newStatus: BuildingStatus

        if clampedHealth <= 0.0 {
            newStatus = .destroyed
        } else if clampedHealth < 0.3 {
            newStatus = .damaged
        } else {
            newStatus = self.status
        }

        return Building(
            id: self.id,
            ownerId: self.ownerId,
            territoryId: self.territoryId,
            latitude: self.latitude,
            longitude: self.longitude,
            buildingType: self.buildingType,
            level: self.level,
            builtAt: self.builtAt,
            lastUpdatedAt: Date(),
            status: newStatus,
            health: clampedHealth,
            customData: self.customData
        )
    }

    /// 获取建筑的显示名称
    var displayName: String {
        let shortId = String(id.uuidString.prefix(6))
        return "\(buildingType.displayName)-\(shortId)"
    }

    /// 获取建筑的完整描述
    var fullDescription: String {
        return "\(buildingType.emoji) \(buildingType.displayName) Lv.\(level) (\(Int(health * 100))%)"
    }

    /// 是否为新建造的建筑 (1小时内)
    var isNewlyBuilt: Bool {
        return Date().timeIntervalSince(builtAt) < 60 * 60 // 1小时
    }

    /// 获取建筑等级对应的效率加成
    var efficiencyBonus: Double {
        return 1.0 + (Double(level - 1) * 0.2) // 每级+20%效率
    }

    /// 计算升级成本
    var upgradeCost: Int {
        return buildingType.baseCost * level * 2
    }
}

// MARK: - 建筑验证

extension Building {

    /// 验证建筑数据的有效性
    func isValid() -> Bool {
        // 基础验证
        guard level > 0 && level <= 50 else { return false }    // 等级1-50
        guard health >= 0.0 && health <= 1.0 else { return false } // 健康度0-100%
        guard latitude >= -90 && latitude <= 90 else { return false }
        guard longitude >= -180 && longitude <= 180 else { return false }

        return true
    }

    /// 验证建筑是否可以在指定位置建造
    static func canBuild(
        type: BuildingType,
        at location: CLLocation,
        in territory: Territory,
        existingBuildings: [Building]
    ) -> BuildingPlacementResult {

        // 检查位置是否在领土内
        guard territory.contains(location) else {
            return .failed(.outsideTerritory)
        }

        // 检查是否与现有建筑太近 (最小距离20米)
        let minimumDistance: Double = 20.0
        for existing in existingBuildings {
            if existing.territoryId == territory.id {
                let distance = existing.distance(to: location)
                if distance < minimumDistance {
                    return .failed(.tooCloseToExisting(existing.id))
                }
            }
        }

        // 检查建筑类型限制 (每个领土最多5个相同类型建筑)
        let sameTypeCount = existingBuildings.filter {
            $0.territoryId == territory.id && $0.buildingType == type
        }.count

        guard sameTypeCount < 5 else {
            return .failed(.tooManyOfSameType)
        }

        return .success
    }
}

// MARK: - 建筑放置结果

enum BuildingPlacementResult {
    case success
    case failed(BuildingPlacementError)

    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}

enum BuildingPlacementError: Error, LocalizedError {
    case outsideTerritory
    case tooCloseToExisting(UUID)
    case tooManyOfSameType
    case insufficientResources
    case invalidLocation

    var errorDescription: String? {
        switch self {
        case .outsideTerritory:
            return "建筑必须建在自己的领土内"
        case .tooCloseToExisting:
            return "距离其他建筑太近，请选择其他位置"
        case .tooManyOfSameType:
            return "同类型建筑数量已达上限"
        case .insufficientResources:
            return "资源不足，无法建造"
        case .invalidLocation:
            return "位置无效"
        }
    }
}

// MARK: - 调试支持

extension Building: CustomStringConvertible {
    var description: String {
        return "Building(id: \(String(id.uuidString.prefix(6))), type: \(buildingType.displayName), level: \(level), status: \(status.displayName), health: \(Int(health * 100))%)"
    }
}

extension BuildingType: CustomStringConvertible {
    var description: String {
        return "\(emoji) \(displayName)"
    }
}

extension BuildingStatus: CustomStringConvertible {
    var description: String {
        return "\(emoji) \(displayName)"
    }
}