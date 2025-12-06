//
//  POIManager.swift
//  tuzi-fuke
//
//  POI 管理器 - 纯查询模式，使用 PostGIS RPC 函数
//  POI 数据由后端 Edge Function 生成，客户端只负责查询和发现
//

import Foundation
import CoreLocation
import SwiftUI
import Combine
import MapKit
import Supabase

// MARK: - 数据库模型

/// POI 数据库模型
struct POIDatabaseModel: Decodable, Sendable {
    let id: UUID
    let name: String
    let type: String
    let description: String?
    let latitude: Double
    let longitude: Double
    let total_items: Int?
    let remaining_items: Int?
}

/// POI 候选数据库模型（用于 MapKit 搜索提交）
struct POICandidateModel: Decodable, Sendable {
    let id: UUID
    let name: String
    let poi_type: String
    let address: String?
    let latitude: Double
    let longitude: Double
}

/// RPC 返回的 POI 模型
struct RPCPOIModel: Decodable, Sendable {
    let id: UUID
    let name: String
    let type: String
    let description: String?
    let latitude: Double
    let longitude: Double
    let total_items: Int?
    let remaining_items: Int?
    let distance_meters: Double?
}

// MARK: - POI 搜索配置

/// POI 搜索关键词配置（用于 MapKit 搜索提交候选）- 旅行风格
private struct POISearchConfig {
    let type: POIType
    let keywords: [String]
    let radius: Double  // 搜索半径（米）

    static let all: [POISearchConfig] = [
        // 咖啡店 - 城市漫步必备
        POISearchConfig(type: .cafe, keywords: ["咖啡", "咖啡店", "咖啡馆", "星巴克", "瑞幸", "Manner"], radius: 1000),
        // 书店 - 文艺探索
        POISearchConfig(type: .bookstore, keywords: ["书店", "书城", "书屋", "西西弗", "新华书店", "诚品"], radius: 1500),
        // 公园 - 自然漫步
        POISearchConfig(type: .park, keywords: ["公园", "广场", "花园", "绿地", "湿地公园"], radius: 2000),
        // 餐厅 - 美食探索
        POISearchConfig(type: .restaurant, keywords: ["餐厅", "美食", "特色菜", "网红店", "老字号"], radius: 1000),
        // 景点 - 文化探索
        POISearchConfig(type: .attraction, keywords: ["景点", "博物馆", "纪念馆", "古迹", "展览馆", "美术馆"], radius: 2500),
        // 商场 - 城市购物
        POISearchConfig(type: .mall, keywords: ["商场", "购物中心", "百货", "万象城", "万达"], radius: 2000),
        // 便利店 - 街角小店
        POISearchConfig(type: .convenienceStore, keywords: ["便利店", "美宜佳", "7-11", "全家", "罗森"], radius: 800),
        // 健身房 - 运动打卡
        POISearchConfig(type: .gym, keywords: ["健身房", "健身中心", "游泳馆", "运动中心", "瑜伽"], radius: 1500),
    ]
}

// MARK: - POIManager

@MainActor
class POIManager: ObservableObject {

    // MARK: - 单例
    static let shared = POIManager()

    // MARK: - Supabase 客户端
    private let supabase = SupabaseManager.shared.client

    // MARK: - Published 属性
    @Published private(set) var cachedPOIs: [POI] = []              // 缓存的 POI（从数据库加载）
    @Published private(set) var discoveredPOIIds: Set<UUID> = []    // 已发现的 POI ID
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String?

    // MARK: - 发现状态
    @Published private(set) var lastDiscoveredPOI: POI?  // 最近发现的 POI（用于弹窗）
    @Published var showDiscoveryAlert: Bool = false       // 是否显示发现弹窗

    // MARK: - 筛选状态
    @Published var selectedTypes: Set<POIType> = Set(POIType.allCases)  // 选中的类型

    // MARK: - 计算属性（用于筛选）
    var allPOIs: [POI] { cachedPOIs }
    var filteredPOIs: [POI] {
        cachedPOIs.filter { selectedTypes.contains($0.type) }
    }

    // 兼容属性 - SimpleMapView 使用
    var nearbyPOIs: [POI] { cachedPOIs }

    // MARK: - 配置
    private let discoveryRange: Double = 100  // 发现范围（米）
    private let cacheRadius: Double = 1000    // 缓存范围（米）
    private let checkDistance: Double = 30    // 移动多少米后重新检查

    // MARK: - 状态
    private var lastCheckLocation: CLLocation?            // 上次检查位置
    private var lastCacheUpdateLocation: CLLocation?      // 上次缓存更新位置
    private var hasSubmittedCandidates: Bool = false      // 是否已提交候选

    // MARK: - 触发记录（防止重复弹窗）
    private var triggeredPOIIds: Set<UUID> = []           // 已触发弹窗的 POI ID（100米内触发过）
    private let resetDistance: Double = 200               // 离开 200 米后重置触发状态

    // MARK: - 初始化

    init() {
        appLog(.info, category: "POI", message: "POIManager 初始化")
    }

    // MARK: - 公开方法

    /// 首次定位成功时调用
    /// 使用 PostGIS RPC 查询附近 POI，同时异步提交 MapKit 候选给后端处理
    func onLocationReady(location: CLLocation, userId: UUID) async {
        // 避免重复初始化
        guard !hasSubmittedCandidates else {
            appLog(.debug, category: "POI", message: "已初始化过，跳过")
            return
        }

        appLog(.info, category: "POI", message: "📍 首次定位成功，使用 PostGIS 查询附近 POI...")
        appLog(.info, category: "POI", message: "   位置: (\(String(format: "%.6f", location.coordinate.latitude)), \(String(format: "%.6f", location.coordinate.longitude)))")

        isLoading = true

        // 步骤1: 使用 PostGIS RPC 查询附近 POI（核心查询）
        await updatePOICacheWithRPC(location: location)

        // 步骤2: 加载用户已发现的 POI
        await loadDiscoveredPOIs(userId: userId)

        // 步骤3: 预先标记当前已在 100 米范围内的 POI（防止首次探索立即弹窗）
        markNearbyPOIsAsTriggered(location: location)

        // ⚠️ 步骤4已禁用: MapKit 搜索会严重影响启动性能（1分钟+白屏）
        // POI 应由后端 Edge Function 预生成，客户端只负责查询数据库
        // 参考原项目 tuzi-earthlord 的实现方式
        //
        // 如需手动触发 POI 候选提交，可在设置页面添加按钮调用：
        // Task {
        //     let candidateCount = await searchAndSubmitCandidates(location: location, userId: userId)
        //     if candidateCount > 0 {
        //         appLog(.info, category: "POI", message: "✅ 已提交 \(candidateCount) 个 POI 候选到后端处理")
        //     }
        // }
        appLog(.info, category: "POI", message: "⏭️ 跳过 MapKit 搜索（性能优化），POI 由后端生成")

        hasSubmittedCandidates = true
        isLoading = false

        appLog(.success, category: "POI", message: "🎉 POI 初始化完成，缓存 \(cachedPOIs.count) 个 POI，预标记 \(triggeredPOIIds.count) 个已在范围内")
    }

    /// 预先标记当前已在发现范围内的 POI（防止首次探索立即弹窗）
    /// 参考原项目 ExplorationManager 的设计：用户需要"走入"范围才触发
    private func markNearbyPOIsAsTriggered(location: CLLocation) {
        // 将 GPS 坐标转换为 GCJ-02
        let gcjCoord = CoordinateConverter.wgs84ToGcj02(location.coordinate)
        let currentLocation = CLLocation(latitude: gcjCoord.latitude, longitude: gcjCoord.longitude)

        for poi in cachedPOIs {
            // 跳过已发现的
            if discoveredPOIIds.contains(poi.id) {
                continue
            }

            let poiLocation = CLLocation(latitude: poi.latitude, longitude: poi.longitude)
            let distance = currentLocation.distance(from: poiLocation)

            // 如果 POI 已经在发现范围内（100米），标记为已触发
            if distance <= discoveryRange {
                triggeredPOIIds.insert(poi.id)
                appLog(.debug, category: "POI", message: "📌 预标记已在范围内的 POI: \(poi.name) (距离: \(Int(distance))米)")
            }
        }
    }

    /// 搜索附近 POI（兼容方法，SimpleMapView 使用）
    func searchNearbyPOIs(location: CLLocation) async {
        await updatePOICacheWithRPC(location: location)
    }

    /// 使用 PostGIS RPC 更新 POI 缓存（核心查询方法）
    func updatePOICacheWithRPC(location: CLLocation) async {
        // 检查是否需要更新（移动超过 300 米才更新）
        if let lastLocation = lastCacheUpdateLocation {
            let distance = location.distance(from: lastLocation)
            if distance < 300 && !cachedPOIs.isEmpty {
                appLog(.debug, category: "POI", message: "距离上次缓存更新不足 300 米，使用缓存")
                return
            }
        }

        appLog(.info, category: "POI", message: "📦 使用 PostGIS RPC 查询附近 POI...")

        // 将 GPS 坐标转换为 GCJ-02（数据库中的坐标是 GCJ-02）
        let gcjCoord = CoordinateConverter.wgs84ToGcj02(location.coordinate)

        do {
            // 使用 RPC 调用 PostGIS 函数
            let response = try await supabase.database
                .rpc("get_pois_within_radius", params: [
                    "p_lat": gcjCoord.latitude,
                    "p_lon": gcjCoord.longitude,
                    "p_radius_km": cacheRadius / 1000.0  // 转换为公里
                ])
                .execute()

            let decoder = JSONDecoder()
            let rpcPOIs = try decoder.decode([RPCPOIModel].self, from: response.data)

            // 转换为 POI 模型
            cachedPOIs = rpcPOIs.map { rpcPOI in
                POI(
                    id: rpcPOI.id,
                    name: rpcPOI.name,
                    type: POIType(rawValue: rpcPOI.type) ?? .other,
                    latitude: rpcPOI.latitude,
                    longitude: rpcPOI.longitude,
                    totalItems: rpcPOI.total_items ?? 100,
                    remainingItems: rpcPOI.remaining_items ?? 100,
                    createdAt: nil
                )
            }

            lastCacheUpdateLocation = location
            appLog(.success, category: "POI", message: "✅ PostGIS 查询完成，共 \(cachedPOIs.count) 个 POI")

        } catch {
            appLog(.error, category: "POI", message: "❌ PostGIS 查询失败: \(error.localizedDescription)")
            // 降级到普通查询
            await updatePOICacheFallback(location: location)
        }
    }

    /// 降级的普通查询（当 RPC 失败时使用）
    private func updatePOICacheFallback(location: CLLocation) async {
        appLog(.warning, category: "POI", message: "⚠️ 降级到普通边界框查询...")

        // 将 GPS 坐标转换为 GCJ-02
        let gcjCoord = CoordinateConverter.wgs84ToGcj02(location.coordinate)

        do {
            // 计算边界框
            let latDelta = cacheRadius / 111000.0
            let lonDelta = cacheRadius / (111000.0 * cos(gcjCoord.latitude * .pi / 180))

            let response = try await supabase.database
                .from("pois")
                .select()
                .gte("latitude", value: gcjCoord.latitude - latDelta)
                .lte("latitude", value: gcjCoord.latitude + latDelta)
                .gte("longitude", value: gcjCoord.longitude - lonDelta)
                .lte("longitude", value: gcjCoord.longitude + lonDelta)
                .eq("is_active", value: true)
                .execute()

            let decoder = JSONDecoder()
            let dbPOIs = try decoder.decode([POIDatabaseModel].self, from: response.data)

            // 转换为 POI 模型
            cachedPOIs = dbPOIs.map { dbPOI in
                POI(
                    id: dbPOI.id,
                    name: dbPOI.name,
                    type: POIType(rawValue: dbPOI.type) ?? .other,
                    latitude: dbPOI.latitude,
                    longitude: dbPOI.longitude,
                    totalItems: dbPOI.total_items ?? 100,
                    remainingItems: dbPOI.remaining_items ?? 100,
                    createdAt: nil
                )
            }

            lastCacheUpdateLocation = location
            appLog(.success, category: "POI", message: "✅ 降级查询完成，共 \(cachedPOIs.count) 个 POI")

        } catch {
            appLog(.error, category: "POI", message: "❌ 降级查询也失败: \(error.localizedDescription)")
        }
    }

    /// 更新 POI 缓存（兼容方法）
    func updatePOICache(location: CLLocation) async {
        await updatePOICacheWithRPC(location: location)
    }

    /// 检查附近 POI（探索时每次位置更新调用）
    /// 参考原项目 ExplorationManager 的 100 米触发机制
    func checkNearbyPOIs(location: CLLocation, userId: UUID) async -> POI? {
        // 检查是否移动了足够距离（至少移动 30 米才重新检查）
        if let lastLocation = lastCheckLocation {
            let distance = location.distance(from: lastLocation)
            if distance < checkDistance {
                return nil
            }
        }

        lastCheckLocation = location
        appLog(.debug, category: "POI发现", message: "🔍 检查附近POI... 缓存: \(cachedPOIs.count)个, 已发现: \(discoveredPOIIds.count)个, 已触发: \(triggeredPOIIds.count)个")

        // 将 GPS 坐标转换为 GCJ-02（与数据库中的坐标系一致）
        let gcjCoord = CoordinateConverter.wgs84ToGcj02(location.coordinate)
        let currentLocation = CLLocation(latitude: gcjCoord.latitude, longitude: gcjCoord.longitude)

        // 先清理远离的 POI（超过 200 米后重置触发状态）
        cleanupDistantTriggeredPOIs(currentLocation: currentLocation)

        // 遍历缓存的 POI 检查距离
        for poi in cachedPOIs {
            // 跳过已发现的（数据库记录）
            if discoveredPOIIds.contains(poi.id) {
                continue
            }

            // 跳过已触发弹窗的（本次探索中已经弹过）
            if triggeredPOIIds.contains(poi.id) {
                continue
            }

            // 计算距离（POI 坐标已经是 GCJ-02）
            let poiLocation = CLLocation(latitude: poi.latitude, longitude: poi.longitude)
            let distance = currentLocation.distance(from: poiLocation)

            // 在发现范围内（100米）
            if distance <= discoveryRange {
                appLog(.success, category: "POI发现", message: "🎉 发现POI: \(poi.name), 距离: \(Int(distance))米")

                // 标记为已触发（防止重复弹窗）
                triggeredPOIIds.insert(poi.id)

                // 记录发现到数据库
                await markPOIDiscovered(poi: poi, userId: userId)

                lastDiscoveredPOI = poi
                showDiscoveryAlert = true
                return poi
            }
        }

        return nil
    }

    /// 清理远离的已触发 POI（超过 200 米后允许再次触发）
    /// 参考原项目 ExplorationManager.cleanupDistantTargets
    private func cleanupDistantTriggeredPOIs(currentLocation: CLLocation) {
        var toRemove: Set<UUID> = []

        for poiId in triggeredPOIIds {
            // 查找 POI
            guard let poi = cachedPOIs.first(where: { $0.id == poiId }) else {
                // POI 不在缓存中，移除
                toRemove.insert(poiId)
                continue
            }

            let poiLocation = CLLocation(latitude: poi.latitude, longitude: poi.longitude)
            let distance = currentLocation.distance(from: poiLocation)

            // 超过重置距离，允许再次触发
            if distance > resetDistance {
                toRemove.insert(poiId)
                appLog(.debug, category: "POI发现", message: "🧹 重置触发状态: \(poi.name) (距离: \(Int(distance))米 > \(Int(resetDistance))米)")
            }
        }

        if !toRemove.isEmpty {
            triggeredPOIIds.subtract(toRemove)
        }
    }

    /// 清除发现弹窗状态
    func clearDiscoveryAlert() {
        showDiscoveryAlert = false
        lastDiscoveredPOI = nil
    }

    /// 重置状态（开始新探索时调用）
    /// 注意：不清空 triggeredPOIIds，这样已经在范围内的 POI 不会立即触发
    /// 只有用户离开 200 米后再进入才会触发
    func resetForNewExploration() {
        lastCheckLocation = nil
        // 不清空 triggeredPOIIds！参考原项目 ExplorationManager 的设计
        // triggeredPOIIds 会在用户离开 200 米后自动清理
        appLog(.info, category: "POI", message: "重置探索状态（保留已触发记录: \(triggeredPOIIds.count)个）")
    }

    /// 重置检查位置（兼容方法）
    func resetCheckLocation() {
        resetForNewExploration()
    }

    /// 完全重置（应用重启时调用）
    func fullReset() {
        lastCheckLocation = nil
        triggeredPOIIds.removeAll()
        appLog(.info, category: "POI", message: "完全重置 POI 状态")
    }

    // MARK: - 筛选方法

    /// 选中所有类型
    func selectAllTypes() {
        selectedTypes = Set(POIType.allCases)
    }

    /// 取消选中所有类型
    func deselectAllTypes() {
        selectedTypes = []
    }

    /// 切换类型筛选
    func toggleTypeFilter(_ type: POIType) {
        if selectedTypes.contains(type) {
            selectedTypes.remove(type)
        } else {
            selectedTypes.insert(type)
        }
    }

    /// 统计指定类型的 POI 数量
    func countByType(_ type: POIType) -> Int {
        cachedPOIs.filter { $0.type == type }.count
    }

    // MARK: - 私有方法

    /// 搜索 MapKit 并提交候选到数据库
    private func searchAndSubmitCandidates(location: CLLocation, userId: UUID) async -> Int {
        var totalCount = 0
        var seenKeys: Set<String> = []

        // 将 GPS 坐标转换为 GCJ-02（MapKit 使用 GCJ-02）
        let gcjCoord = CoordinateConverter.wgs84ToGcj02(location.coordinate)

        for config in POISearchConfig.all {
            for keyword in config.keywords {
                let candidates = await searchMapKit(
                    keyword: keyword,
                    center: gcjCoord,
                    radius: config.radius,
                    type: config.type
                )

                for candidate in candidates {
                    // 生成网格 key（用于去重）
                    let gridKey = generateGridKey(name: candidate.name, lat: candidate.latitude, lon: candidate.longitude)

                    if !seenKeys.contains(gridKey) {
                        seenKeys.insert(gridKey)

                        // 提交到数据库
                        let success = await submitCandidate(candidate: candidate, gridKey: gridKey, userId: userId)
                        if success {
                            totalCount += 1
                        }
                    }
                }

                // 避免请求过快
                try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1秒
            }
        }

        return totalCount
    }

    /// 使用 MapKit 搜索 POI
    private func searchMapKit(keyword: String, center: CLLocationCoordinate2D, radius: Double, type: POIType) async -> [(name: String, type: POIType, address: String?, latitude: Double, longitude: Double)] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = keyword
        request.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )

        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()
            appLog(.debug, category: "POI", message: "   搜索 '\(keyword)': 找到 \(response.mapItems.count) 个结果")

            return response.mapItems.compactMap { item -> (String, POIType, String?, Double, Double)? in
                guard let name = item.name, !name.isEmpty else { return nil }

                // MapKit 返回的坐标是 GCJ-02，直接存储（数据库统一使用 GCJ-02）
                let poiCoord = item.placemark.coordinate

                return (
                    name,
                    type,
                    item.placemark.title,
                    poiCoord.latitude,
                    poiCoord.longitude
                )
            }
        } catch {
            appLog(.warning, category: "POI", message: "   搜索 '\(keyword)' 失败: \(error.localizedDescription)")
            return []
        }
    }

    /// 提交候选到数据库（参考 PositionRepository 的实现方式）
    private func submitCandidate(candidate: (name: String, type: POIType, address: String?, latitude: Double, longitude: Double), gridKey: String, userId: UUID) async -> Bool {
        // 捕获需要的值
        let name = candidate.name
        let poiType = candidate.type.rawValue
        let address = candidate.address
        let latitude = candidate.latitude
        let longitude = candidate.longitude
        let userIdString = userId.uuidString

        return await withCheckedContinuation { continuation in
            Task.detached {
                do {
                    let supabase = await SupabaseManager.shared.client

                    // 在 Task.detached 内部定义结构体，避免 MainActor 隔离问题
                    struct CandidateInsert: Encodable, Sendable {
                        let name: String
                        let poi_type: String
                        let address: String?
                        let latitude: Double
                        let longitude: Double
                        let grid_key: String
                        let submitted_by: String
                    }

                    let insertData = CandidateInsert(
                        name: name,
                        poi_type: poiType,
                        address: address,
                        latitude: latitude,
                        longitude: longitude,
                        grid_key: gridKey,
                        submitted_by: userIdString
                    )

                    // 使用数组插入 + select，与 PositionRepository 保持一致
                    // 不使用 returning: .minimal，因为 SDK 会尝试解码空响应导致错误
                    try await supabase.database
                        .from("mapkit_poi_candidates")
                        .insert([insertData])
                        .select()
                        .execute()

                    await MainActor.run {
                        appLog(.debug, category: "POI", message: "   ✅ [NEW] 提交候选成功: \(name)")
                    }
                    continuation.resume(returning: true)
                } catch {
                    // 详细记录错误信息
                    let errorType = String(describing: Swift.type(of: error))
                    let fullError = String(describing: error)

                    // 忽略重复 key 错误（unique constraint）
                    let errorStr = fullError.lowercased()
                    if errorStr.contains("unique") || errorStr.contains("duplicate") || errorStr.contains("23505") {
                        await MainActor.run {
                            appLog(.debug, category: "POI", message: "   ⏭️ [NEW] 跳过重复候选: \(name)")
                        }
                        continuation.resume(returning: false)
                        return
                    }

                    await MainActor.run {
                        appLog(.error, category: "POI", message: "   ❌ [NEW] 提交候选失败: \(name)")
                        appLog(.error, category: "POI", message: "   错误详情: \(fullError)")
                        appLog(.error, category: "POI", message: "   错误类型: \(errorType)")
                    }
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // NOTE: POI 生成现在由后端 Edge Function (process-poi-candidates) 处理
    // 客户端只负责提交候选和查询 POI

    /// 标记 POI 为已发现
    private func markPOIDiscovered(poi: POI, userId: UUID) async {
        // 先添加到本地集合（避免重复弹窗）
        discoveredPOIIds.insert(poi.id)

        // 捕获需要的值
        let userIdString = userId.uuidString
        let poiIdString = poi.id.uuidString
        let poiName = poi.name
        let poiType = poi.type.rawValue
        let latitude = poi.latitude
        let longitude = poi.longitude

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task.detached {
                do {
                    let supabase = await SupabaseManager.shared.client

                    struct DiscoveryInsert: Encodable, Sendable {
                        let user_id: String
                        let poi_id: String
                        let poi_name: String
                        let poi_type: String
                        let latitude: Double
                        let longitude: Double
                    }

                    let insertData = DiscoveryInsert(
                        user_id: userIdString,
                        poi_id: poiIdString,
                        poi_name: poiName,
                        poi_type: poiType,
                        latitude: latitude,
                        longitude: longitude
                    )

                    try await supabase.database
                        .from("user_poi_discoveries")
                        .insert(insertData)
                        .execute()

                    await MainActor.run {
                        appLog(.success, category: "POI", message: "✅ 发现记录已保存: \(poiName)")
                    }
                } catch {
                    await MainActor.run {
                        appLog(.error, category: "POI", message: "❌ 保存发现记录失败: \(error.localizedDescription)")
                    }
                }
                continuation.resume()
            }
        }
    }

    /// 加载用户已发现的 POI
    func loadDiscoveredPOIs(userId: UUID) async {
        appLog(.info, category: "POI", message: "📖 加载已发现的 POI...")

        do {
            struct DiscoveryResult: Decodable {
                let poi_id: UUID?
            }

            let response = try await supabase.database
                .from("user_poi_discoveries")
                .select("poi_id")
                .eq("user_id", value: userId.uuidString)  // 转换为 String 格式
                .execute()

            let decoder = JSONDecoder()
            let results = try decoder.decode([DiscoveryResult].self, from: response.data)
            discoveredPOIIds = Set(results.compactMap { $0.poi_id })

            appLog(.success, category: "POI", message: "✅ 已加载 \(discoveredPOIIds.count) 个已发现 POI")
        } catch {
            appLog(.error, category: "POI", message: "❌ 加载已发现 POI 失败: \(error.localizedDescription)")
        }
    }

    /// 生成网格 key（用于去重）
    private func generateGridKey(name: String, lat: Double, lon: Double) -> String {
        let latStr = String(format: "%.3f", lat)  // 3位小数，约111米精度
        let lonStr = String(format: "%.3f", lon)
        return "\(name)_\(latStr)_\(lonStr)"
    }
}

// MARK: - POI 错误

enum POIError: Error, LocalizedError {
    case invalidURL
    case networkError(String)
    case serverError(Int, String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 URL"
        case .networkError(let message):
            return "网络错误: \(message)"
        case .serverError(let code, let message):
            return "服务器错误 (\(code)): \(message)"
        case .decodingError(let message):
            return "解码错误: \(message)"
        }
    }
}
