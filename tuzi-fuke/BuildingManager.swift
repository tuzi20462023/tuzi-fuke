//
//  BuildingManager.swift
//  tuzi-fuke
//
//  DAY8: 建筑系统管理器 - 简化版
//  Created by AI Assistant on 2025/12/02.
//

import Foundation
import Combine
import CoreLocation
import Supabase

// MARK: - 数据传输结构体 (需要在类外部定义以支持 Sendable)

struct BuildingInsertData: Encodable, Sendable {
    let user_id: String
    let territory_id: String
    let building_template_id: String
    let building_name: String
    let building_template_key: String
    let location: GeoJSONPoint?
    let status: String
    let build_started_at: String
    let build_completed_at: String
    let build_time_hours: Double
    let level: Int
    let durability: Int
    let durability_max: Int

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(user_id, forKey: .user_id)
        try container.encode(territory_id, forKey: .territory_id)
        try container.encode(building_template_id, forKey: .building_template_id)
        try container.encode(building_name, forKey: .building_name)
        try container.encode(building_template_key, forKey: .building_template_key)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encode(status, forKey: .status)
        try container.encode(build_started_at, forKey: .build_started_at)
        try container.encode(build_completed_at, forKey: .build_completed_at)
        try container.encode(build_time_hours, forKey: .build_time_hours)
        try container.encode(level, forKey: .level)
        try container.encode(durability, forKey: .durability)
        try container.encode(durability_max, forKey: .durability_max)
    }

    private enum CodingKeys: String, CodingKey {
        case user_id, territory_id, building_template_id, building_name
        case building_template_key, location, status, build_started_at
        case build_completed_at, build_time_hours, level, durability, durability_max
    }
}

struct BuildingUpdateData: Encodable, Sendable {
    let status: String
    let updated_at: String

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(updated_at, forKey: .updated_at)
    }

    private enum CodingKeys: String, CodingKey {
        case status, updated_at
    }
}

/// 建筑系统管理器 - 简化版 MVP
@MainActor
class BuildingManager: ObservableObject {

    // MARK: - 单例
    static let shared = BuildingManager()

    // MARK: - Published Properties
    @Published var buildingTemplates: [BuildingTemplate] = []
    @Published var playerBuildings: [PlayerBuilding] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Private
    private let supabase = SupabaseManager.shared

    // MARK: - 初始化
    private init() {
        print("✅ [BuildingManager] 初始化完成")
    }

    // MARK: - 获取建筑模板

    /// 从数据库获取所有可用的建筑模板
    func fetchBuildingTemplates() async {
        print("🔄 [BuildingManager] 获取建筑模板...")
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await supabase.client.database
                .from("building_templates")
                .select()
                .eq("is_active", value: true)
                .order("tier")
                .order("required_level")
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)

                // 尝试多种日期格式
                let formatters: [DateFormatter] = {
                    let f1 = DateFormatter()
                    f1.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"
                    f1.locale = Locale(identifier: "en_US_POSIX")

                    let f2 = DateFormatter()
                    f2.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
                    f2.locale = Locale(identifier: "en_US_POSIX")

                    let f3 = DateFormatter()
                    f3.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZZZZZ"
                    f3.locale = Locale(identifier: "en_US_POSIX")

                    return [f1, f2, f3]
                }()

                for formatter in formatters {
                    if let date = formatter.date(from: dateString) {
                        return date
                    }
                }

                // ISO8601
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

            let templates = try decoder.decode([BuildingTemplate].self, from: response.data)
            buildingTemplates = templates

            print("✅ [BuildingManager] 加载了 \(templates.count) 个建筑模板")
            for template in templates {
                print("   - \(template.name) (Tier \(template.tier), \(template.category.displayName))")
            }

        } catch {
            print("❌ [BuildingManager] 获取模板失败: \(error)")
            errorMessage = "获取建筑列表失败: \(error.localizedDescription)"
        }
    }

    /// 根据分类筛选模板
    func templates(for category: NewBuildingCategory) -> [BuildingTemplate] {
        buildingTemplates.filter { $0.category == category }
    }

    // MARK: - 获取玩家建筑

    /// 获取玩家在某个领地的所有建筑
    func fetchPlayerBuildings(territoryId: UUID) async {
        print("🔄 [BuildingManager] 获取领地建筑: \(territoryId)")
        isLoading = true
        defer { isLoading = false }

        guard let userId = await supabase.getCurrentUserId() else {
            print("❌ [BuildingManager] 用户未登录")
            return
        }

        do {
            let response = try await supabase.client.database
                .from("player_buildings")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("territory_id", value: territoryId.uuidString)
                .order("created_at", ascending: false)
                .execute()

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

            let buildings = try decoder.decode([PlayerBuilding].self, from: response.data)
            playerBuildings = buildings

            print("✅ [BuildingManager] 加载了 \(buildings.count) 个玩家建筑")

        } catch {
            print("❌ [BuildingManager] 获取建筑失败: \(error)")
            errorMessage = "获取建筑列表失败"
        }
    }

    // MARK: - 检查建造条件

    /// 检查是否可以建造某个建筑
    func canBuild(template: BuildingTemplate, territoryId: UUID) -> (canBuild: Bool, error: BuildingConstructionError?) {
        // 简化版：暂时不检查资源，只检查数量限制
        let existingCount = playerBuildings.filter {
            $0.territoryId == territoryId &&
            $0.buildingTemplateKey == template.templateId &&
            ($0.status == .active || $0.status == .constructing)
        }.count

        if existingCount >= template.maxPerTerritory {
            return (false, .maxBuildingsReached(template.maxPerTerritory))
        }

        return (true, nil)
    }

    // MARK: - 开始建造

    /// 开始建造建筑
    func startConstruction(request: BuildingConstructionRequest) async -> BuildingConstructionResult {
        print("🏗️ [BuildingManager] 开始建造: \(request.templateId)")

        // 查找模板
        guard let template = buildingTemplates.first(where: { $0.templateId == request.templateId }) else {
            return BuildingConstructionResult(
                success: false,
                building: nil,
                error: .unknown("建筑模板不存在"),
                message: "建筑模板不存在"
            )
        }

        // 检查建造条件
        let (canBuildResult, error) = canBuild(template: template, territoryId: request.territoryId)
        if !canBuildResult, let error = error {
            return BuildingConstructionResult(
                success: false,
                building: nil,
                error: error,
                message: error.localizedDescription
            )
        }

        // 获取用户ID
        guard let userId = await supabase.getCurrentUserId() else {
            return BuildingConstructionResult(
                success: false,
                building: nil,
                error: .unknown("用户未登录"),
                message: "用户未登录"
            )
        }

        // 计算建造时间
        let buildStarted = Date()
        let buildCompleted = buildStarted.addingTimeInterval(template.buildTimeHours * 3600)

        let locationJSON: GeoJSONPoint?
        if let loc = request.location {
            locationJSON = GeoJSONPoint(longitude: loc.longitude, latitude: loc.latitude)
        } else {
            locationJSON = nil
        }

        let insertData = BuildingInsertData(
            user_id: userId.uuidString,
            territory_id: request.territoryId.uuidString,
            building_template_id: template.id.uuidString,
            building_name: request.customName ?? template.name,
            building_template_key: template.templateId,
            location: locationJSON,
            status: PlayerBuildingStatus.constructing.rawValue,
            build_started_at: ISO8601DateFormatter().string(from: buildStarted),
            build_completed_at: ISO8601DateFormatter().string(from: buildCompleted),
            build_time_hours: template.buildTimeHours,
            level: 1,
            durability: template.durabilityMax,
            durability_max: template.durabilityMax
        )

        do {
            let response = try await supabase.client.database
                .from("player_buildings")
                .insert(insertData)
                .select()
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let buildings = try decoder.decode([PlayerBuilding].self, from: response.data)

            guard let newBuilding = buildings.first else {
                return BuildingConstructionResult(
                    success: false,
                    building: nil,
                    error: .unknown("创建失败"),
                    message: "创建建筑失败"
                )
            }

            // 添加到本地列表
            playerBuildings.append(newBuilding)

            print("✅ [BuildingManager] 建造开始: \(newBuilding.buildingName)")

            return BuildingConstructionResult(
                success: true,
                building: newBuilding,
                error: nil,
                message: "建造开始！预计 \(template.formattedBuildTime) 后完成"
            )

        } catch {
            print("❌ [BuildingManager] 建造失败: \(error)")
            return BuildingConstructionResult(
                success: false,
                building: nil,
                error: .networkError(error),
                message: "建造失败: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - 完成建造

    /// 完成建造（将状态改为 active）
    func completeConstruction(buildingId: UUID) async {
        print("🏗️ [BuildingManager] 完成建造: \(buildingId)")

        guard let index = playerBuildings.firstIndex(where: { $0.id == buildingId }) else {
            return
        }

        do {
            let updateData = BuildingUpdateData(
                status: PlayerBuildingStatus.active.rawValue,
                updated_at: ISO8601DateFormatter().string(from: Date())
            )

            try await supabase.client.database
                .from("player_buildings")
                .update(updateData)
                .eq("id", value: buildingId.uuidString)
                .execute()

            // 更新本地状态
            var building = playerBuildings[index]
            building.status = .active
            building.updatedAt = Date()
            playerBuildings[index] = building

            print("✅ [BuildingManager] 建筑完成: \(building.buildingName)")

        } catch {
            print("❌ [BuildingManager] 完成建造失败: \(error)")
        }
    }

    // MARK: - 辅助方法

    /// 获取模板
    func getTemplate(for templateKey: String) -> BuildingTemplate? {
        buildingTemplates.first { $0.templateId == templateKey }
    }

    /// 获取领地内建筑数量
    func buildingCount(in territoryId: UUID) -> Int {
        playerBuildings.filter {
            $0.territoryId == territoryId &&
            ($0.status == .active || $0.status == .constructing)
        }.count
    }
}
