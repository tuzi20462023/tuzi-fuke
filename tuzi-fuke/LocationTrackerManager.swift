//
//  LocationTrackerManager.swift
//  tuzi-fuke
//
//  位置追踪管理器 - 定时上报玩家位置，支持附近玩家查询
//  参考源项目 tuzi-earthlord
//

import Foundation
import CoreLocation
import Supabase
import Combine

/// 位置追踪管理器 - 定时上报玩家位置，支持附近玩家查询
@MainActor
class LocationTrackerManager: ObservableObject {
    static let shared = LocationTrackerManager()

    @Published var nearbyPlayers: [RadioNearbyPlayer] = []
    @Published var isTracking: Bool = false
    @Published var currentDeviceType: String = "radio"
    @Published var isDeviceEnabled: Bool = true

    private let supabase = SupabaseManager.shared.client
    private var updateTimer: Timer?
    private var heartbeatTimer: Timer?
    private var lastReportedLocation: CLLocation?

    private let updateInterval: TimeInterval = 300    // 5分钟上报一次位置
    private let heartbeatInterval: TimeInterval = 120 // 2分钟心跳
    private let movementThreshold: CLLocationDistance = 50 // 50米触发上报

    private init() {
        print("📍 [LocationTracker] 初始化位置追踪管理器")
    }

    // MARK: - 开始/停止追踪

    /// 开始位置追踪
    func startTracking() {
        guard !isTracking else {
            print("⚠️ [LocationTracker] 已在追踪中")
            return
        }

        print("📍 [LocationTracker] 开始位置追踪")
        isTracking = true

        // 启动定时器（每5分钟上报一次）
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.reportCurrentLocation()
            }
        }

        // 启动心跳定时器（每2分钟）
        startHeartbeat()

        // 立即上报一次
        Task {
            await reportCurrentLocation()
        }
    }

    /// 停止位置追踪
    func stopTracking() {
        print("⏸️ [LocationTracker] 停止位置追踪")
        isTracking = false

        updateTimer?.invalidate()
        updateTimer = nil

        stopHeartbeat()

        // 标记为离线
        Task {
            await markOffline()
        }
    }

    // MARK: - 上报位置

    /// 上报当前位置
    func reportCurrentLocation() async {
        guard isDeviceEnabled else {
            print("🔌 [LocationTracker] 设备已关闭，不上报位置")
            return
        }

        guard let location = LocationManager.shared.currentLocation else {
            print("⚠️ [LocationTracker] 位置未知，跳过上报")
            return
        }

        // 检查是否需要上报（距离上次上报超过阈值）
        if let lastLocation = lastReportedLocation {
            let distance = location.distance(from: lastLocation)
            if distance < movementThreshold {
                print("⏭️ [LocationTracker] 移动距离不足\(Int(movementThreshold))米，跳过上报 (距离: \(Int(distance))米)")
                return
            }
        }

        do {
            try await updatePlayerLocation(location: location)
            lastReportedLocation = location
        } catch {
            print("❌ [LocationTracker] 位置上报失败: \(error)")
        }
    }

    /// 更新玩家位置（调用RPC）
    private func updatePlayerLocation(location: CLLocation) async throws {
        guard let userId = await SupabaseManager.shared.getCurrentUserId() else {
            print("❌ [LocationTracker] 用户未登录")
            return
        }

        print("📤 [LocationTracker] 上报位置: (\(location.coordinate.latitude), \(location.coordinate.longitude))")

        // 调用 RPC
        let url = SupabaseConfig.supabaseURL
            .appendingPathComponent("rest/v1/rpc/update_player_location")

        let body: [String: Any] = [
            "p_user_id": userId.uuidString,
            "p_lat": location.coordinate.latitude,
            "p_lon": location.coordinate.longitude,
            "p_device_type": currentDeviceType
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")

        if let accessToken = try? await supabase.auth.session.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            print("❌ [LocationTracker] RPC失败: \(errorBody)")
            return
        }

        print("✅ [LocationTracker] 位置上报成功")
    }

    /// 标记为离线
    private func markOffline() async {
        guard let userId = await SupabaseManager.shared.getCurrentUserId() else { return }

        let url = SupabaseConfig.supabaseURL
            .appendingPathComponent("rest/v1/player_locations_realtime")
            .appending(queryItems: [
                URLQueryItem(name: "user_id", value: "eq.\(userId.uuidString)")
            ])

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["is_online": false])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")

        if let accessToken = try? await supabase.auth.session.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        _ = try? await URLSession.shared.data(for: request)
        print("👋 [LocationTracker] 已标记为离线")
    }

    // MARK: - 心跳机制

    private func startHeartbeat() {
        guard heartbeatTimer == nil else { return }

        print("💓 [LocationTracker] 启动心跳 (间隔: \(Int(heartbeatInterval))秒)")

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.sendHeartbeat()
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        print("💔 [LocationTracker] 停止心跳")
    }

    private func sendHeartbeat() async {
        guard let userId = await SupabaseManager.shared.getCurrentUserId() else { return }

        let url = SupabaseConfig.supabaseURL
            .appendingPathComponent("rest/v1/player_locations_realtime")
            .appending(queryItems: [
                URLQueryItem(name: "user_id", value: "eq.\(userId.uuidString)")
            ])

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "is_online": true,
            "last_updated": ISO8601DateFormatter().string(from: Date())
        ])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")

        if let accessToken = try? await supabase.auth.session.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        if let (_, response) = try? await URLSession.shared.data(for: request),
           let httpResponse = response as? HTTPURLResponse,
           (200...299).contains(httpResponse.statusCode) {
            print("💓 [LocationTracker] 心跳成功")
        }
    }

    // MARK: - 附近玩家查询

    /// 获取附近玩家列表
    func fetchNearbyPlayers(rangeKm: Double = 100) async {
        guard let location = LocationManager.shared.currentLocation else {
            print("⚠️ [LocationTracker] 位置未知，无法查询附近玩家")
            return
        }

        guard let userId = await SupabaseManager.shared.getCurrentUserId() else {
            print("❌ [LocationTracker] 用户未登录")
            return
        }

        print("🔍 [LocationTracker] 查询附近玩家 (范围: \(rangeKm)km)")

        let url = SupabaseConfig.supabaseURL
            .appendingPathComponent("rest/v1/rpc/get_nearby_players")

        let body: [String: Any] = [
            "p_user_id": userId.uuidString,
            "p_lat": location.coordinate.latitude,
            "p_lon": location.coordinate.longitude,
            "p_range_km": rangeKm
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: body)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = jsonData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")

            if let accessToken = try? await supabase.auth.session.accessToken {
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
                print("❌ [LocationTracker] 查询失败: \(errorBody)")
                return
            }

            let players = try JSONDecoder().decode([RadioNearbyPlayer].self, from: data)
            self.nearbyPlayers = players
            print("✅ [LocationTracker] 找到 \(players.count) 个附近玩家")

        } catch {
            print("❌ [LocationTracker] 查询附近玩家失败: \(error)")
        }
    }

    // MARK: - 设备管理

    func setDeviceType(_ deviceType: String) {
        self.currentDeviceType = deviceType
        print("📻 [LocationTracker] 切换设备: \(deviceType)")

        // 切换设备后立即上报位置
        Task {
            await reportCurrentLocation()
        }
    }
}

// MARK: - 数据模型

/// 附近玩家数据模型
struct RadioNearbyPlayer: Codable, Identifiable {
    let userId: UUID
    let callsign: String?
    let deviceType: String?
    let distanceKm: Double
    let isOnline: Bool

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case callsign
        case deviceType = "device_type"
        case distanceKm = "distance_km"
        case isOnline = "is_online"
    }

    var displayName: String {
        callsign ?? "未知玩家"
    }

    var formattedDistance: String {
        if distanceKm < 1 {
            return String(format: "%.0f米", distanceKm * 1000)
        } else {
            return String(format: "%.1f公里", distanceKm)
        }
    }
}
