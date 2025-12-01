//
//  POIManager.swift
//  tuzi-fuke
//
//  POI 管理器 - 负责 POI 查询、筛选、发现
//  参考源项目 EarthLord
//

import Foundation
import CoreLocation
import SwiftUI
import Combine

// MARK: - POIManager

@MainActor
class POIManager: ObservableObject {

    // MARK: - 单例
    static let shared = POIManager()

    // MARK: - Published 属性
    @Published private(set) var allPOIs: [POI] = []                    // 所有加载的 POI
    @Published private(set) var filteredPOIs: [POI] = []               // 筛选后的 POI
    @Published private(set) var nearbyPOIs: [POI] = []                 // 附近的 POI
    @Published private(set) var discoveredPOIs: Set<UUID> = []         // 已发现的 POI ID
    @Published var selectedTypes: Set<POIType> = Set(POIType.allCases) // 选中的类型筛选
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String?

    // MARK: - 配置
    private let nearbyRadius: Double = 500  // 附近 POI 半径（米）

    // MARK: - 初始化

    init() {
        appLog(.info, category: "POI", message: "POIManager 初始化")
    }

    // MARK: - 公开方法

    /// 加载附近的 POI
    func loadNearbyPOIs(location: CLLocation, radius: Double? = nil) async {
        let searchRadius = radius ?? nearbyRadius

        appLog(.info, category: "POI", message: "加载附近 POI: 坐标=(\(location.coordinate.latitude), \(location.coordinate.longitude)), 半径=\(searchRadius)m")

        isLoading = true
        lastError = nil

        do {
            let pois = try await fetchPOIsFromDatabase(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                radius: searchRadius
            )

            allPOIs = pois
            nearbyPOIs = pois
            applyTypeFilter()

            appLog(.success, category: "POI", message: "加载到 \(pois.count) 个 POI")
        } catch {
            lastError = error.localizedDescription
            appLog(.error, category: "POI", message: "加载 POI 失败: \(error.localizedDescription)")
        }

        isLoading = false
    }

    /// 刷新 POI 列表
    func refresh(at location: CLLocation) async {
        await loadNearbyPOIs(location: location)
    }

    /// 切换类型筛选
    func toggleTypeFilter(_ type: POIType) {
        if selectedTypes.contains(type) {
            selectedTypes.remove(type)
        } else {
            selectedTypes.insert(type)
        }
        applyTypeFilter()
    }

    /// 选择所有类型
    func selectAllTypes() {
        selectedTypes = Set(POIType.allCases)
        applyTypeFilter()
    }

    /// 取消选择所有类型
    func deselectAllTypes() {
        selectedTypes.removeAll()
        applyTypeFilter()
    }

    /// 发现 POI（收集资源）
    func discoverPOI(_ poi: POI, userId: UUID) async -> Bool {
        guard poi.hasResources else {
            appLog(.warning, category: "POI", message: "POI 没有剩余资源: \(poi.name)")
            return false
        }

        guard !discoveredPOIs.contains(poi.id) else {
            appLog(.warning, category: "POI", message: "POI 已被发现: \(poi.name)")
            return false
        }

        appLog(.info, category: "POI", message: "发现 POI: \(poi.name)")

        do {
            try await recordDiscovery(poiId: poi.id, userId: userId)
            discoveredPOIs.insert(poi.id)
            appLog(.success, category: "POI", message: "POI 发现记录已保存")
            return true
        } catch {
            appLog(.error, category: "POI", message: "保存发现记录失败: \(error.localizedDescription)")
            return false
        }
    }

    /// 检查 POI 是否已发现
    func isDiscovered(_ poi: POI) -> Bool {
        discoveredPOIs.contains(poi.id)
    }

    /// 获取指定类型的 POI 数量
    func countByType(_ type: POIType) -> Int {
        allPOIs.filter { $0.type == type }.count
    }

    // MARK: - 私有方法

    /// 应用类型筛选
    private func applyTypeFilter() {
        if selectedTypes.isEmpty {
            filteredPOIs = []
        } else if selectedTypes.count == POIType.allCases.count {
            filteredPOIs = allPOIs
        } else {
            filteredPOIs = allPOIs.filter { selectedTypes.contains($0.type) }
        }

        appLog(.debug, category: "POI", message: "筛选后 POI 数量: \(filteredPOIs.count)/\(allPOIs.count)")
    }

    /// 从数据库获取 POI
    private func fetchPOIsFromDatabase(latitude: Double, longitude: Double, radius: Double) async throws -> [POI] {
        // 计算边界框（简化的距离过滤）
        let latDelta = radius / 111000.0  // 纬度每度约 111km
        let lonDelta = radius / (111000.0 * cos(latitude * .pi / 180))  // 经度每度随纬度变化

        let minLat = latitude - latDelta
        let maxLat = latitude + latDelta
        let minLon = longitude - lonDelta
        let maxLon = longitude + lonDelta

        // 构建 URL
        let urlString = "\(SupabaseConfig.supabaseURL)/rest/v1/pois?latitude=gte.\(minLat)&latitude=lte.\(maxLat)&longitude=gte.\(minLon)&longitude=lte.\(maxLon)&select=*"

        guard let url = URL(string: urlString) else {
            throw POIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw POIError.networkError("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw POIError.serverError(httpResponse.statusCode, errorMessage)
        }

        let decoder = JSONDecoder()
        let pois = try decoder.decode([POI].self, from: data)

        // 按距离过滤（精确过滤）
        let centerLocation = CLLocation(latitude: latitude, longitude: longitude)
        let filteredByDistance = pois.filter { poi in
            let poiLocation = CLLocation(latitude: poi.latitude, longitude: poi.longitude)
            return poiLocation.distance(from: centerLocation) <= radius
        }

        return filteredByDistance
    }

    /// 记录 POI 发现
    private func recordDiscovery(poiId: UUID, userId: UUID) async throws {
        let urlString = "\(SupabaseConfig.supabaseURL)/rest/v1/user_poi_discoveries"

        guard let url = URL(string: urlString) else {
            throw POIError.invalidURL
        }

        let discovery = [
            "user_id": userId.uuidString,
            "poi_id": poiId.uuidString,
            "items_collected": 1
        ] as [String: Any]

        let jsonData = try JSONSerialization.data(withJSONObject: discovery)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw POIError.networkError("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw POIError.serverError(httpResponse.statusCode, errorMessage)
        }
    }

    /// 加载用户已发现的 POI
    func loadDiscoveredPOIs(userId: UUID) async {
        appLog(.info, category: "POI", message: "加载用户已发现的 POI...")

        let urlString = "\(SupabaseConfig.supabaseURL)/rest/v1/user_poi_discoveries?user_id=eq.\(userId.uuidString)&select=poi_id"

        guard let url = URL(string: urlString) else {
            appLog(.error, category: "POI", message: "URL 无效")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                appLog(.error, category: "POI", message: "加载失败")
                return
            }

            struct DiscoveryRecord: Decodable {
                let poi_id: String
            }

            let records = try JSONDecoder().decode([DiscoveryRecord].self, from: data)
            discoveredPOIs = Set(records.compactMap { UUID(uuidString: $0.poi_id) })

            appLog(.success, category: "POI", message: "已加载 \(discoveredPOIs.count) 个已发现 POI")
        } catch {
            appLog(.error, category: "POI", message: "加载已发现 POI 失败: \(error.localizedDescription)")
        }
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
