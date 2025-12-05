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

struct PendingRefundInsertData: Encodable, Sendable {
    let user_id: String
    let resource_id: String
    let quantity: Int
    let source_type: String
    let source_name: String

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(user_id, forKey: .user_id)
        try container.encode(resource_id, forKey: .resource_id)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(source_type, forKey: .source_type)
        try container.encode(source_name, forKey: .source_name)
    }

    private enum CodingKeys: String, CodingKey {
        case user_id, resource_id, quantity, source_type, source_name
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
    private var constructionTimer: Timer?
    private let constructionCheckInterval: TimeInterval = 10.0  // 每10秒检查一次

    // ✅ 建筑模板Bundle化优化
    private var templatesDict: [String: BuildingTemplate] = [:]  // O(1)查找字典
    private var bundledTemplatesVersion: String = "1.0.0"  // Bundle版本号

    // ✅ 玩家建筑缓存标记（避免重复网络请求）
    private var hasLoadedAllBuildings = false
    private var loadedTerritoryIds: Set<UUID> = []

    // MARK: - 测试模式 (测试完毕后改回 false)
    /// 测试模式：建造时间改为30秒
    private let testMode_FastBuild = true
    private let testBuildTimeSeconds: TimeInterval = 30.0

    // MARK: - 初始化
    private init() {
        print("✅ [BuildingManager] 初始化完成")
        // 从本地 Bundle 加载建筑模板（秒开，无需网络）
        loadBundledTemplates()
        startConstructionTimer()
    }

    deinit {
        constructionTimer?.invalidate()
    }

    // MARK: - 建造进度定时器

    /// 启动建造进度检查定时器
    private func startConstructionTimer() {
        constructionTimer?.invalidate()
        constructionTimer = Timer.scheduledTimer(withTimeInterval: constructionCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkConstructionProgress()
            }
        }
        print("⏱️ [BuildingManager] 建造进度定时器已启动，间隔: \(constructionCheckInterval)秒")
    }

    // MARK: - 加载本地模板

    /// ✅ 加载Bundle中的建筑模板（离线优先，秒开）
    private func loadBundledTemplates() {
        print("📦 [BuildingManager] 加载Bundle中的建筑模板...")

        // 尝试多个可能的Bundle路径
        var url: URL? = nil

        // 方案1: 在Resources子目录中
        url = Bundle.main.url(forResource: "building_templates", withExtension: "json", subdirectory: "Resources")
        if url != nil {
            print("✓ 从Bundle路径1找到: Resources/building_templates.json")
        }

        // 方案2: 直接在Bundle root
        if url == nil {
            url = Bundle.main.url(forResource: "building_templates", withExtension: "json")
            if url != nil {
                print("✓ 从Bundle路径2找到: building_templates.json (root)")
            }
        }

        // 方案3: 在BuildingImages同级目录
        if url == nil {
            url = Bundle.main.url(forResource: "Resources/building_templates", withExtension: "json")
            if url != nil {
                print("✓ 从Bundle路径3找到: Resources/building_templates.json")
            }
        }

        guard let fileUrl = url else {
            print("❌❌❌ 找不到building_templates.json文件")
            print("❌❌❌ 已尝试以下路径:")
            print("❌   1. Bundle: Resources/building_templates.json")
            print("❌   2. Bundle: building_templates.json")
            print("❌   3. Bundle: Resources/building_templates.json")
            print("   将回退到网络加载模式")
            return
        }

        print("✓ 找到JSON文件: \(fileUrl.path)")

        do {
            print("✓ 开始读取JSON数据...")
            let data = try Data(contentsOf: fileUrl)
            print("✓ JSON数据读取成功，大小: \(data.count) bytes")

            print("✓ 开始解码JSON...")
            let decoder = JSONDecoder()

            // 配置日期解码策略
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)

                let dateFormatter = DateFormatter()
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")
                dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

                // 支持多种格式
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
                if let date = dateFormatter.date(from: dateString) { return date }

                let iso8601WithFractional = ISO8601DateFormatter()
                iso8601WithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = iso8601WithFractional.date(from: dateString) { return date }

                let iso8601Standard = ISO8601DateFormatter()
                iso8601Standard.formatOptions = [.withInternetDateTime]
                if let date = iso8601Standard.date(from: dateString) { return date }

                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ssZ"
                if let date = dateFormatter.date(from: dateString) { return date }

                throw DecodingError.dataCorruptedError(in: container, debugDescription: "无法解析日期字符串: \(dateString)")
            }

            // 解析JSON结构
            struct TemplatesBundle: Codable {
                let version: String
                let last_updated: String
                let templates: [BuildingTemplate]
            }

            let bundle = try decoder.decode(TemplatesBundle.self, from: data)
            print("✓ JSON解码成功！")

            // 更新模板列表和字典
            print("✓ 开始更新模板列表...")
            // ✅ 排序：先按 tier，再按 required_level（与网络加载保持一致）
            buildingTemplates = bundle.templates.sorted { a, b in
                if a.tier != b.tier {
                    return a.tier < b.tier
                }
                return a.requiredLevel < b.requiredLevel
            }
            templatesDict = Dictionary(uniqueKeysWithValues: buildingTemplates.map { ($0.templateId, $0) })
            bundledTemplatesVersion = bundle.version

            print("✅ Bundle加载成功: \(buildingTemplates.count)个模板, 版本: \(bundle.version)")
            print("✅ 字典索引构建完成: \(templatesDict.count)个模板可快速查找")

            // ✅ 手动触发 UI 更新（确保 sheet 中能立即显示）
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }

        } catch {
            print("❌❌❌ 加载Bundle模板失败: \(error)")
            print("❌❌❌ 错误详情: \(error.localizedDescription)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("❌ 缺少键: \(key), 路径: \(context.codingPath)")
                case .typeMismatch(let type, let context):
                    print("❌ 类型不匹配: \(type), 路径: \(context.codingPath)")
                case .valueNotFound(let type, let context):
                    print("❌ 值不存在: \(type), 路径: \(context.codingPath)")
                case .dataCorrupted(let context):
                    print("❌ 数据损坏: \(context)")
                @unknown default:
                    print("❌ 未知解码错误")
                }
            }
            print("   回退到数据库加载模式")
        }
    }

    /// 检查所有建造中的建筑进度
    private func checkConstructionProgress() async {
        let constructingBuildings = playerBuildings.filter { $0.status == .constructing }

        guard !constructingBuildings.isEmpty else { return }

        print("🔍 [BuildingManager] 检查 \(constructingBuildings.count) 个建造中的建筑")

        let now = Date()
        for building in constructingBuildings {
            if let completedAt = building.buildCompletedAt, now >= completedAt {
                // 建造完成！
                print("🎉 [BuildingManager] 建筑完成: \(building.buildingName)")
                await completeConstruction(buildingId: building.id)
            }
        }
    }

    /// 完成建造，更新状态为 active
    func completeConstruction(buildingId: UUID) async {
        print("🏗️ [BuildingManager] 完成建造: \(buildingId)")

        do {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let updateData = BuildingUpdateData(
                status: PlayerBuildingStatus.active.rawValue,
                updated_at: iso.string(from: Date())
            )

            try await supabase.client.database
                .from("player_buildings")
                .update(updateData)
                .eq("id", value: buildingId.uuidString)
                .execute()

            // 更新本地状态
            if let index = playerBuildings.firstIndex(where: { $0.id == buildingId }) {
                // status 是 var，可以直接修改
                playerBuildings[index].status = .active
                playerBuildings[index].updatedAt = Date()
            }

            print("✅ [BuildingManager] 建筑状态已更新为 active")

        } catch {
            print("❌ [BuildingManager] 完成建造失败: \(error)")
        }
    }

    // MARK: - 获取建筑模板

    /// 从数据库获取所有可用的建筑模板
    /// ✅ 优化：如果Bundle已加载模板，直接返回（秒开）
    func fetchBuildingTemplates() async {
        // ✅ 如果Bundle模板已加载，直接使用
        if !buildingTemplates.isEmpty {
            print("✅ [BuildingManager] 使用Bundle缓存模板: \(buildingTemplates.count)个")
            return
        }

        // 如果Bundle加载失败，回退到网络请求
        print("🔄 [BuildingManager] Bundle模板为空，回退到网络获取...")
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

    /// 获取玩家所有建筑（用于主地图显示）
    /// ✅ 优化：已加载过则直接返回缓存
    func fetchAllPlayerBuildings() async {
        // ✅ 如果已加载过，直接返回
        if hasLoadedAllBuildings && !playerBuildings.isEmpty {
            print("✅ [BuildingManager] 使用缓存的玩家建筑: \(playerBuildings.count)个")
            return
        }

        print("🔄 [BuildingManager] 获取所有玩家建筑...")

        guard let userId = await supabase.getCurrentUserId() else {
            print("❌ [BuildingManager] 用户未登录")
            return
        }

        do {
            let response = try await supabase.client.database
                .from("player_buildings")
                .select()
                .eq("user_id", value: userId.uuidString)
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
            hasLoadedAllBuildings = true

            print("✅ [BuildingManager] 加载了 \(buildings.count) 个玩家建筑（全部）")

        } catch {
            print("❌ [BuildingManager] 获取所有建筑失败: \(error)")
            errorMessage = "获取建筑列表失败"
        }
    }

    /// 获取玩家在某个领地的所有建筑
    /// ✅ 优化：已加载过该领地则直接返回缓存
    func fetchPlayerBuildings(territoryId: UUID) async {
        // ✅ 如果该领地已加载过，直接返回
        if loadedTerritoryIds.contains(territoryId) {
            let cached = playerBuildings.filter { $0.territoryId == territoryId }
            print("✅ [BuildingManager] 使用缓存的领地建筑: \(cached.count)个")
            return
        }

        print("🔄 [BuildingManager] 获取领地建筑: \(territoryId)")

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

            // 合并到 playerBuildings（移除旧的该领地建筑，添加新的）
            playerBuildings.removeAll { $0.territoryId == territoryId }
            playerBuildings.append(contentsOf: buildings)
            loadedTerritoryIds.insert(territoryId)

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
        let actualBuildTimeSeconds: TimeInterval
        let actualBuildTimeHours: Double

        if testMode_FastBuild {
            // 测试模式：30秒建造
            actualBuildTimeSeconds = testBuildTimeSeconds
            actualBuildTimeHours = testBuildTimeSeconds / 3600.0
            print("🧪 [BuildingManager] 测试模式：建造时间 \(Int(testBuildTimeSeconds)) 秒")
        } else {
            // 正常模式：使用模板时间
            actualBuildTimeSeconds = template.buildTimeHours * 3600
            actualBuildTimeHours = template.buildTimeHours
        }

        let buildCompleted = buildStarted.addingTimeInterval(actualBuildTimeSeconds)

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
            build_time_hours: actualBuildTimeHours,
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

            let timeMessage: String
            if testMode_FastBuild {
                timeMessage = "建造开始！预计 \(Int(testBuildTimeSeconds)) 秒后完成 (测试模式)"
            } else {
                timeMessage = "建造开始！预计 \(template.formattedBuildTime) 后完成"
            }

            return BuildingConstructionResult(
                success: true,
                building: newBuilding,
                error: nil,
                message: timeMessage
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

    // MARK: - 辅助方法

    /// 获取模板（O(1)查找优化）
    func getTemplate(for templateKey: String) -> BuildingTemplate? {
        // ✅ 优先使用字典O(1)查找
        if let template = templatesDict[templateKey] {
            return template
        }
        // 回退到数组遍历
        return buildingTemplates.first { $0.templateId == templateKey }
    }

    /// 获取领地内建筑数量
    func buildingCount(in territoryId: UUID) -> Int {
        playerBuildings.filter {
            $0.territoryId == territoryId &&
            ($0.status == .active || $0.status == .constructing)
        }.count
    }

    // MARK: - 建筑拆除

    /// 拆除建筑
    /// - Parameters:
    ///   - buildingId: 建筑ID
    ///   - userId: 用户ID
    /// - Returns: 拆除结果
    func demolishBuilding(buildingId: UUID, userId: UUID) async -> BuildingDemolitionResult {
        print("🗑️ [BuildingManager] 开始拆除建筑: \(buildingId)")

        // 查找建筑
        guard let building = playerBuildings.first(where: { $0.id == buildingId }) else {
            return BuildingDemolitionResult(
                success: false,
                message: "建筑不存在",
                refundedResources: [:]
            )
        }

        // 查找建筑模板
        guard let template = buildingTemplates.first(where: {
            $0.templateId == building.buildingTemplateKey
        }) else {
            return BuildingDemolitionResult(
                success: false,
                message: "建筑模板不存在",
                refundedResources: [:]
            )
        }

        // 计算返还资源（30% 建造成本）
        var refundedResources: [String: Int] = [:]
        for (resource, amount) in template.requiredResources {
            let refundAmount = Int(Double(amount) * 0.3)
            if refundAmount > 0 {
                refundedResources[resource] = refundAmount
            }
        }

        print("📦 [BuildingManager] 计算返还资源: \(refundedResources)")

        // 删除建筑记录
        do {
            try await supabase.client.database
                .from("player_buildings")
                .delete()
                .eq("id", value: buildingId.uuidString)
                .execute()

            print("✅ [BuildingManager] 拆除建筑成功: \(building.buildingName)")

            // 将返还资源存入待领取表
            for (resourceId, quantity) in refundedResources {
                let refundData = PendingRefundInsertData(
                    user_id: userId.uuidString,
                    resource_id: resourceId,
                    quantity: quantity,
                    source_type: "building_demolish",
                    source_name: building.buildingName
                )

                do {
                    try await supabase.client.database
                        .from("pending_refunds")
                        .insert(refundData)
                        .execute()
                    print("📦 [BuildingManager] 待领取资源已存入: \(resourceId) x\(quantity)")
                } catch {
                    print("⚠️ [BuildingManager] 存入待领取资源失败: \(error)")
                }
            }

            // 从本地列表移除
            playerBuildings.removeAll { $0.id == buildingId }

            return BuildingDemolitionResult(
                success: true,
                message: "建筑已拆除，资源已存入待领取",
                refundedResources: refundedResources
            )
        } catch {
            print("❌ [BuildingManager] 拆除失败: \(error)")
            return BuildingDemolitionResult(
                success: false,
                message: "拆除失败: \(error.localizedDescription)",
                refundedResources: [:]
            )
        }
    }
}

// MARK: - 建筑拆除结果

/// 建筑拆除操作的结果
struct BuildingDemolitionResult {
    let success: Bool
    let message: String
    let refundedResources: [String: Int]
}
