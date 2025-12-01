//
//  TerritoryManager.swift
//  tuzi-fuke
//
//  领地管理器 - 负责圈地逻辑、Supabase 上传和查询
//  参考原项目 EarthLord/TerritoryManager.swift
//

import Foundation
import CoreLocation
import SwiftUI
import Combine
import Supabase

// MARK: - 圈地状态

enum ClaimingState {
    case idle           // 空闲，未圈地
    case ready          // 准备圈地（已选择位置）
    case claiming       // 圈地中
    case uploading      // 上传中
    case success        // 成功
    case failed(Error)  // 失败

    var description: String {
        switch self {
        case .idle: return "空闲"
        case .ready: return "准备圈地"
        case .claiming: return "圈地中"
        case .uploading: return "上传中"
        case .success: return "圈地成功"
        case .failed(let error): return "失败: \(error.localizedDescription)"
        }
    }
}

// MARK: - 碰撞类型

enum CollisionType {
    case pointInTerritory           // 点在他人领地内
    case pathCrossTerritory         // 路径穿越他人领地
    case polygonContainsTerritory   // 多边形包含他人领地
    case selfIntersection           // 自相交
}

// MARK: - 预警级别（参考源项目）

enum WarningLevel: Int {
    case safe = 0           // 安全（>100m）
    case caution = 1        // 注意（50-100m）
    case warning = 2        // 警告（25-50m）
    case danger = 3         // 危险（<25m）
    case violation = 4      // 违规（已碰撞）

    var distance: Double {
        switch self {
        case .safe: return 101
        case .caution: return 100
        case .warning: return 50
        case .danger: return 25
        case .violation: return 0
        }
    }

    var emoji: String {
        switch self {
        case .safe: return "✅"
        case .caution: return "⚠️"
        case .warning: return "🟡"
        case .danger: return "🔴"
        case .violation: return "❌"
        }
    }

    var message: String {
        switch self {
        case .safe: return ""
        case .caution: return "注意：接近他人领地"
        case .warning: return "警告：非常接近他人领地"
        case .danger: return "危险：即将进入他人领地"
        case .violation: return "违规：已进入他人领地"
        }
    }
}

// MARK: - 实时碰撞检测结果

struct RealtimeCollisionResult {
    let hasCollision: Bool
    let collisionType: CollisionType?
    let message: String?
    let closestDistance: Double?      // 距离最近领地的距离（米）
    let warningLevel: WarningLevel
    let conflictTerritoryName: String?
}

// MARK: - TerritoryManager

@MainActor
class TerritoryManager: ObservableObject {

    // MARK: - 单例
    static let shared = TerritoryManager()

    // MARK: - Published 属性
    @Published private(set) var claimingState: ClaimingState = .idle
    @Published private(set) var territories: [Territory] = []           // 我的领地
    @Published private(set) var nearbyTerritories: [Territory] = []     // 附近所有领地（含他人）
    @Published private(set) var selectedLocation: CLLocationCoordinate2D?
    @Published var showClaimConfirmation = false
    @Published private(set) var isUploading = false
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    // MARK: - 配置
    let defaultRadius: Double = 50.0  // 默认圈地半径50米
    let minimumRadius: Double = 20.0
    let maximumRadius: Double = 200.0
    let nearbyQueryRadius: Double = 5000  // 附近查询半径5公里

    // MARK: - Supabase 客户端
    private var supabase: SupabaseClient {
        return SupabaseManager.shared.client
    }

    // MARK: - 计算属性

    /// 从 AuthManager 获取当前用户ID
    private var currentUserId: UUID? {
        return AuthManager.shared.currentUser?.id
    }

    /// 是否已登录
    var isLoggedIn: Bool {
        return currentUserId != nil
    }

    // MARK: - 初始化

    init() {
        print("🏴 [TerritoryManager] 初始化领地管理器")
    }

    // MARK: - 公开方法

    /// 选择圈地位置（长按地图触发）
    func selectLocation(_ coordinate: CLLocationCoordinate2D) {
        selectedLocation = coordinate
        claimingState = .ready
        showClaimConfirmation = true
        print("🏴 [TerritoryManager] 选择位置: \(coordinate.latitude), \(coordinate.longitude)")
    }

    /// 取消圈地
    func cancelClaiming() {
        selectedLocation = nil
        claimingState = .idle
        showClaimConfirmation = false
        print("🏴 [TerritoryManager] 取消圈地")
    }

    /// 确认圈地（圆形领地）
    func confirmClaim() async {
        guard let coordinate = selectedLocation else {
            print("❌ [TerritoryManager] 没有选择位置")
            return
        }

        guard let userId = currentUserId else {
            print("❌ [TerritoryManager] 用户未登录")
            claimingState = .failed(TerritoryClaimError.insufficientLevel)
            return
        }

        claimingState = .claiming
        showClaimConfirmation = false

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        // 检查是否可以圈地（与附近领地对比）
        let allTerritories = territories + nearbyTerritories
        let result = Territory.canClaim(
            at: location,
            radius: defaultRadius,
            existingTerritories: allTerritories
        )

        guard result.isSuccess else {
            if case .failed(let error) = result {
                claimingState = .failed(error)
            }
            return
        }

        // 创建新领地
        let newTerritory = Territory.createCircle(
            ownerId: userId,
            center: location,
            radius: defaultRadius
        )

        claimingState = .uploading

        // 上传到 Supabase
        let success = await uploadTerritory(newTerritory)

        if success {
            territories.append(newTerritory)
            claimingState = .success
            selectedLocation = nil

            print("✅ [TerritoryManager] 圆形圈地成功: \(newTerritory.displayName)")
            print("   - 位置: \(coordinate.latitude), \(coordinate.longitude)")
            print("   - 半径: \(defaultRadius)m")
            print("   - 面积: \(Int(newTerritory.area))m²")

            // 2秒后重置状态
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            claimingState = .idle
        } else {
            claimingState = .failed(TerritoryUploadError.uploadFailed(errorMessage ?? "未知错误"))
        }
    }

    /// 删除领地
    func deleteTerritory(_ territory: Territory) {
        territories.removeAll { $0.id == territory.id }
        print("🗑️ [TerritoryManager] 删除领地: \(territory.displayName)")
    }

    /// 获取指定位置附近的领地
    func getNearbyTerritories(from location: CLLocation, within distance: Double = 1000) -> [Territory] {
        return nearbyTerritories.filter { territory in
            territory.distance(to: location) <= distance
        }
    }

    /// 检查位置是否在任何领地内
    func isLocationInTerritory(_ location: CLLocation) -> Territory? {
        let allTerritories = territories + nearbyTerritories
        return allTerritories.first { $0.contains(location) }
    }

    // MARK: - 行走圈地（多边形）

    /// 确认行走圈地（多边形领地）
    /// 参考原项目 EarthLord/TerritoryManager.swift 的 uploadTerritory 方法
    func confirmWalkingClaim(pathLocations: [CLLocation], area: Double, startTime: Date?) async {
        guard pathLocations.count >= 4 else {
            appLog(.error, category: "圈地", message: "路径点数不足，至少需要4个点")
            claimingState = .failed(TerritoryClaimError.insufficientLevel)
            return
        }

        guard let userId = currentUserId else {
            appLog(.error, category: "圈地", message: "用户未登录")
            claimingState = .failed(TerritoryClaimError.insufficientLevel)
            return
        }

        claimingState = .claiming

        // ⚠️ 碰撞检测：检查新路径是否与现有领地重叠
        let collisionResult = checkNewTerritoryCollision(pathLocations: pathLocations)
        if collisionResult.hasCollision {
            appLog(.warning, category: "圈地", message: "❌ 检测到领地重叠！")
            appLog(.warning, category: "圈地", message: "冲突领地: \(collisionResult.conflictTerritoryName ?? "未知")")
            claimingState = .failed(TerritoryClaimError.territoryConflict(collisionResult.message))
            return
        }

        // 创建多边形领地
        let territoryName = "领地 #\(territories.count + 1)"
        let newTerritory = Territory.createPolygon(
            ownerId: userId,
            pathLocations: pathLocations,
            area: area,
            name: territoryName,
            startTime: startTime
        )

        appLog(.info, category: "圈地", message: "🏴 行走圈地")
        appLog(.info, category: "圈地", message: "名称: \(territoryName), 顶点数: \(pathLocations.count), 面积: \(Int(area))m²")

        claimingState = .uploading

        // 上传到 Supabase
        let success = await uploadTerritory(newTerritory)

        if success {
            territories.append(newTerritory)
            claimingState = .success

            appLog(.success, category: "圈地", message: "✅ 行走圈地成功: \(newTerritory.displayName), 面积: \(Int(area))m²")

            // 2秒后重置状态
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            claimingState = .idle
        } else {
            appLog(.error, category: "圈地", message: "❌ 圈地失败: \(errorMessage ?? "未知错误")")
            claimingState = .failed(TerritoryUploadError.uploadFailed(errorMessage ?? "未知错误"))
        }
    }

    // MARK: - 碰撞检测

    /// 碰撞检测结果
    struct CollisionResult {
        let hasCollision: Bool
        let message: String
        let conflictTerritoryName: String?
    }

    /// 检查新领地路径是否与现有领地重叠
    /// 使用简化的边界框检测 + 点在多边形检测
    private func checkNewTerritoryCollision(pathLocations: [CLLocation]) -> CollisionResult {
        let allTerritories = territories + nearbyTerritories

        // 计算新路径的边界框
        let newLats = pathLocations.map { $0.coordinate.latitude }
        let newLons = pathLocations.map { $0.coordinate.longitude }
        let newMinLat = newLats.min() ?? 0
        let newMaxLat = newLats.max() ?? 0
        let newMinLon = newLons.min() ?? 0
        let newMaxLon = newLons.max() ?? 0

        for territory in allTerritories {
            // 1. 边界框快速排除
            if let tMinLat = territory.bboxMinLat,
               let tMaxLat = territory.bboxMaxLat,
               let tMinLon = territory.bboxMinLon,
               let tMaxLon = territory.bboxMaxLon {
                // 边界框不相交，跳过
                if newMaxLat < tMinLat || newMinLat > tMaxLat ||
                   newMaxLon < tMinLon || newMinLon > tMaxLon {
                    continue
                }
            }

            // 2. 检查新路径的点是否在现有领地内
            for location in pathLocations {
                if territory.contains(location) {
                    appLog(.warning, category: "碰撞检测", message: "路径点在领地 \(territory.displayName) 内")
                    return CollisionResult(
                        hasCollision: true,
                        message: "新路径与领地「\(territory.displayName)」重叠",
                        conflictTerritoryName: territory.displayName
                    )
                }
            }

            // 3. 检查现有领地的中心点是否在新路径形成的多边形内
            let centerLocation = CLLocation(
                latitude: territory.centerLatitude,
                longitude: territory.centerLongitude
            )
            if isPointInPolygon(point: centerLocation.coordinate, polygon: pathLocations.map { $0.coordinate }) {
                appLog(.warning, category: "碰撞检测", message: "新路径包含领地 \(territory.displayName)")
                return CollisionResult(
                    hasCollision: true,
                    message: "新路径包含领地「\(territory.displayName)」",
                    conflictTerritoryName: territory.displayName
                )
            }
        }

        appLog(.debug, category: "碰撞检测", message: "✅ 无碰撞，共检查 \(allTerritories.count) 个领地")
        return CollisionResult(hasCollision: false, message: "", conflictTerritoryName: nil)
    }

    /// 判断点是否在多边形内（Ray Casting 算法）
    private func isPointInPolygon(point: CLLocationCoordinate2D, polygon: [CLLocationCoordinate2D]) -> Bool {
        guard polygon.count >= 3 else { return false }

        var inside = false
        var j = polygon.count - 1

        for i in 0..<polygon.count {
            let xi = polygon[i].longitude
            let yi = polygon[i].latitude
            let xj = polygon[j].longitude
            let yj = polygon[j].latitude

            let intersect = ((yi > point.latitude) != (yj > point.latitude)) &&
                            (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi)

            if intersect {
                inside = !inside
            }
            j = i
        }

        return inside
    }

    /// 向后兼容：使用坐标数组的行走圈地
    func confirmWalkingClaim(pathCoordinates: [CLLocationCoordinate2D], area: Double) async {
        // 转换为 CLLocation 数组
        let pathLocations = pathCoordinates.map { coord in
            CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        }
        await confirmWalkingClaim(pathLocations: pathLocations, area: area, startTime: nil)
    }

    // MARK: - Supabase 上传

    /// 上传领地到 Supabase
    /// 参考原项目 EarthLord/TerritoryManager.swift
    private func uploadTerritory(_ territory: Territory) async -> Bool {
        isUploading = true
        errorMessage = nil

        appLog(.info, category: "上传", message: "开始上传领地到 Supabase...")
        appLog(.debug, category: "上传", message: "ID: \(territory.id)")
        appLog(.debug, category: "上传", message: "类型: \(territory.type.rawValue)")
        appLog(.debug, category: "上传", message: "面积: \(Int(territory.area))m²")
        appLog(.debug, category: "上传", message: "user_id: \(territory.ownerId)")
        appLog(.debug, category: "上传", message: "顶点数: \(territory.pointCount ?? 0)")

        do {
            let formatter = ISO8601DateFormatter()

            // 转换 path 数据格式
            let pathData: [PathPointData]? = territory.path?.compactMap { point in
                guard let lat = point["lat"], let lon = point["lon"] else { return nil }
                return PathPointData(lat: lat, lon: lon, timestamp: point["timestamp"])
            }

            // 使用全局定义的上传数据结构
            let uploadData = TerritoryUploadData(
                id: territory.id.uuidString,
                user_id: territory.ownerId.uuidString,
                type: territory.type.rawValue,
                center_latitude: territory.centerLatitude,
                center_longitude: territory.centerLongitude,
                radius: territory.radius,
                is_active: territory.isActive,
                name: territory.name,
                path: pathData,
                polygon: territory.polygonWkt,
                bbox_min_lat: territory.bboxMinLat,
                bbox_max_lat: territory.bboxMaxLat,
                bbox_min_lon: territory.bboxMinLon,
                bbox_max_lon: territory.bboxMaxLon,
                area: territory.calculatedArea,
                perimeter: territory.perimeter,
                point_count: territory.pointCount,
                started_at: territory.startedAt.map { formatter.string(from: $0) },
                completed_at: territory.completedAt.map { formatter.string(from: $0) }
            )

            // 使用独立的 actor 和原生 REST API 执行上传（避免 Swift 6 并发问题）
            let supabaseUrl = SupabaseConfig.supabaseURL.absoluteString
            let anonKey = SupabaseConfig.supabaseAnonKey
            let accessToken = try? await supabase.auth.session.accessToken

            try await territoryUploader.upload(
                uploadData,
                supabaseUrl: supabaseUrl,
                anonKey: anonKey,
                accessToken: accessToken
            )

            appLog(.success, category: "上传", message: "✅ 领地上传成功!")
            isUploading = false
            return true

        } catch {
            appLog(.error, category: "上传", message: "领地上传失败: \(error.localizedDescription)")
            appLog(.error, category: "上传", message: "详细错误: \(error)")
            errorMessage = error.localizedDescription
            isUploading = false
            return false
        }
    }

    // MARK: - Supabase 查询

    /// 查询我的所有领地
    func queryMyTerritories() async {
        guard let userId = currentUserId else {
            print("❌ [TerritoryManager] 用户未登录，无法查询领地")
            return
        }

        isLoading = true

        do {
            print("📥 [TerritoryManager] 查询我的领地...")

            let response = try await supabase.database
                .from("territories")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("is_active", value: true)
                .execute()

            // 解码响应
            let decoder = JSONDecoder()
            let fetchedTerritories = try decoder.decode([Territory].self, from: response.data)

            territories = fetchedTerritories
            print("✅ [TerritoryManager] 查询到 \(fetchedTerritories.count) 块我的领地")

        } catch {
            print("❌ [TerritoryManager] 查询我的领地失败: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// 查询附近所有领地（包括他人）
    /// 使用边界框快速过滤
    func queryNearbyTerritories(center: CLLocation, radius: Double? = nil) async {
        let queryRadius = radius ?? nearbyQueryRadius

        // 计算边界框
        let metersPerDegree = 111000.0  // 纬度每度约111公里
        let latDelta = queryRadius / metersPerDegree
        let lonDelta = queryRadius / (metersPerDegree * cos(center.coordinate.latitude * .pi / 180))

        let minLat = center.coordinate.latitude - latDelta
        let maxLat = center.coordinate.latitude + latDelta
        let minLon = center.coordinate.longitude - lonDelta
        let maxLon = center.coordinate.longitude + lonDelta

        isLoading = true

        do {
            print("📥 [TerritoryManager] 查询附近领地...")
            print("   - 中心: \(center.coordinate.latitude), \(center.coordinate.longitude)")
            print("   - 半径: \(Int(queryRadius))m")

            // 使用边界框过滤
            let response = try await supabase.database
                .from("territories")
                .select()
                .gte("center_latitude", value: minLat)
                .lte("center_latitude", value: maxLat)
                .gte("center_longitude", value: minLon)
                .lte("center_longitude", value: maxLon)
                .eq("is_active", value: true)
                .execute()

            // 解码响应
            let decoder = JSONDecoder()
            let fetchedTerritories = try decoder.decode([Territory].self, from: response.data)

            nearbyTerritories = fetchedTerritories
            print("✅ [TerritoryManager] 查询到 \(fetchedTerritories.count) 块附近领地")

        } catch {
            print("❌ [TerritoryManager] 查询附近领地失败: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// 刷新所有领地数据
    func refreshTerritories(at location: CLLocation? = nil) async {
        await queryMyTerritories()

        if let location = location {
            await queryNearbyTerritories(center: location)
        }
    }

    // MARK: - 实时碰撞检测（参考源项目）

    /// 综合碰撞检测（检查整条轨迹）
    /// 参考源项目 EarthLord/TerritoryManager.swift 的 checkPathCollisionComprehensive 方法
    func checkPathCollisionComprehensive(
        path: [CLLocation],
        currentUserId: UUID,
        locationManager: LocationManager
    ) -> RealtimeCollisionResult {
        guard path.count >= 2 else {
            return RealtimeCollisionResult(
                hasCollision: false,
                collisionType: nil,
                message: nil,
                closestDistance: nil,
                warningLevel: .safe,
                conflictTerritoryName: nil
            )
        }

        // 1. 检查自相交
        if locationManager.hasPathSelfIntersection() {
            appLog(.error, category: "实时碰撞", message: "❌ 检测到自相交")
            return RealtimeCollisionResult(
                hasCollision: true,
                collisionType: .selfIntersection,
                message: "轨迹不能自己交叉！",
                closestDistance: 0,
                warningLevel: .violation,
                conflictTerritoryName: nil
            )
        }

        // 2. 分离他人领地和自己的领地（参考源项目 checkPathCrossTerritories）
        appLog(.debug, category: "实时碰撞", message: "📊 领地统计: 我的=\(territories.count), 附近=\(nearbyTerritories.count)")

        // 他人领地：从 nearbyTerritories 中过滤出不是自己的
        let otherTerritories = nearbyTerritories.filter { $0.ownerId != currentUserId }
        // 自己的领地：直接使用 territories
        let ownTerritories = territories

        appLog(.debug, category: "实时碰撞", message: "📊 他人领地: \(otherTerritories.count), 自己领地: \(ownTerritories.count)")

        // 3. 检查与他人领地的碰撞
        for territory in otherTerritories {
            // 检查路径点是否在领地内
            for location in path {
                if territory.contains(location) {
                    appLog(.error, category: "实时碰撞", message: "❌ 路径进入他人领地「\(territory.displayName)」")
                    return RealtimeCollisionResult(
                        hasCollision: true,
                        collisionType: .pointInTerritory,
                        message: "已进入他人领地「\(territory.displayName)」！",
                        closestDistance: 0,
                        warningLevel: .violation,
                        conflictTerritoryName: territory.displayName
                    )
                }
            }

            // 检查路径是否穿越领地边界
            if doesPathCrossTerritory(path: path, territory: territory) {
                appLog(.error, category: "实时碰撞", message: "❌ 路径穿越他人领地「\(territory.displayName)」")
                return RealtimeCollisionResult(
                    hasCollision: true,
                    collisionType: .pathCrossTerritory,
                    message: "轨迹不能穿越他人的领地！",
                    closestDistance: 0,
                    warningLevel: .violation,
                    conflictTerritoryName: territory.displayName
                )
            }
        }

        // 4. 检查与自己其他领地的碰撞（参考源项目：crossOwnTerritory）
        for territory in ownTerritories {
            // 检查路径点是否在自己的领地内
            for location in path {
                if territory.contains(location) {
                    appLog(.error, category: "实时碰撞", message: "❌ 路径进入自己的领地「\(territory.displayName)」")
                    return RealtimeCollisionResult(
                        hasCollision: true,
                        collisionType: .polygonContainsTerritory, // 用这个表示穿越自己领地
                        message: "轨迹不能穿越你的其他领地！",
                        closestDistance: 0,
                        warningLevel: .violation,
                        conflictTerritoryName: territory.displayName
                    )
                }
            }

            // 检查路径是否穿越自己领地边界
            if doesPathCrossTerritory(path: path, territory: territory) {
                appLog(.error, category: "实时碰撞", message: "❌ 路径穿越自己的领地「\(territory.displayName)」")
                return RealtimeCollisionResult(
                    hasCollision: true,
                    collisionType: .polygonContainsTerritory,
                    message: "轨迹不能穿越你的其他领地！",
                    closestDistance: 0,
                    warningLevel: .violation,
                    conflictTerritoryName: territory.displayName
                )
            }
        }

        // 5. 计算当前位置到最近他人领地的距离（用于预警）
        var minDistance = Double.infinity
        var closestTerritoryName: String?

        if let currentLocation = path.last {
            for territory in otherTerritories {
                let distance = calculateDistanceToTerritory(location: currentLocation, territory: territory)
                if distance < minDistance {
                    minDistance = distance
                    closestTerritoryName = territory.displayName
                }
            }
        }

        // 6. 根据距离确定预警级别
        let warningLevel: WarningLevel
        if minDistance > 100 {
            warningLevel = .safe
        } else if minDistance > 50 {
            warningLevel = .caution
        } else if minDistance > 25 {
            warningLevel = .warning
        } else {
            warningLevel = .danger
        }

        // 7. 返回预警结果
        let message: String?
        if warningLevel != .safe, let name = closestTerritoryName {
            message = "\(warningLevel.emoji) 距离领地「\(name)」\(Int(minDistance))米"
        } else {
            message = nil
        }

        if warningLevel != .safe {
            appLog(.debug, category: "实时碰撞", message: "预警: 距离最近领地 \(Int(minDistance))m, 级别: \(warningLevel)")
        }

        return RealtimeCollisionResult(
            hasCollision: false,
            collisionType: nil,
            message: message,
            closestDistance: minDistance == Double.infinity ? nil : minDistance,
            warningLevel: warningLevel,
            conflictTerritoryName: closestTerritoryName
        )
    }

    /// 检查路径是否穿越领地边界
    private func doesPathCrossTerritory(path: [CLLocation], territory: Territory) -> Bool {
        let territoryCoords = territory.toCoordinates()
        guard territoryCoords.count >= 3 else { return false }

        // 检查路径的每个线段是否与领地边界相交
        for i in 0..<(path.count - 1) {
            let pathStart = path[i].coordinate
            let pathEnd = path[i + 1].coordinate

            for j in 0..<territoryCoords.count {
                let boundaryStart = territoryCoords[j]
                let boundaryEnd = territoryCoords[(j + 1) % territoryCoords.count]

                if segmentsIntersect(pathStart, pathEnd, boundaryStart, boundaryEnd) {
                    return true
                }
            }
        }

        return false
    }

    /// 检测两条线段是否相交（CCW 算法）
    private func segmentsIntersect(
        _ p1: CLLocationCoordinate2D, _ p2: CLLocationCoordinate2D,
        _ p3: CLLocationCoordinate2D, _ p4: CLLocationCoordinate2D
    ) -> Bool {
        func ccw(_ A: CLLocationCoordinate2D, _ B: CLLocationCoordinate2D, _ C: CLLocationCoordinate2D) -> Bool {
            return (C.latitude - A.latitude) * (B.longitude - A.longitude) >
                   (B.latitude - A.latitude) * (C.longitude - A.longitude)
        }

        return ccw(p1, p3, p4) != ccw(p2, p3, p4) &&
               ccw(p1, p2, p3) != ccw(p1, p2, p4)
    }

    /// 计算位置到领地的最近距离
    private func calculateDistanceToTerritory(location: CLLocation, territory: Territory) -> Double {
        // 简化计算：使用到中心点的距离减去等效半径
        let distanceToCenter = location.distance(from: territory.centerLocation)

        if territory.isPolygon {
            // 多边形领地：用到中心点距离减去等效半径作为近似值
            let effectiveRadius = sqrt(territory.area / Double.pi)
            return max(0, distanceToCenter - effectiveRadius)
        } else {
            // 圆形领地：到中心距离减去半径
            return max(0, distanceToCenter - territory.radius)
        }
    }

    /// 检查路径是否与现有领地碰撞（向后兼容）
    func checkPathCollision(path: [CLLocation]) -> (hasCollision: Bool, conflictTerritory: Territory?) {
        let allTerritories = territories + nearbyTerritories

        for territory in allTerritories {
            // 检查路径是否穿过领地
            for location in path {
                if territory.contains(location) {
                    return (true, territory)
                }
            }
        }

        return (false, nil)
    }
}

// MARK: - 错误类型

enum TerritoryUploadError: Error, LocalizedError {
    case uploadFailed(String)
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .uploadFailed(let message):
            return "上传失败: \(message)"
        case .validationFailed(let message):
            return "验证失败: \(message)"
        }
    }
}

