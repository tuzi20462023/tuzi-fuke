//
//  ExplorationManager.swift
//  tuzi-fuke
//
//  探索管理器 - 负责探索会话、距离统计、网格追踪
//  参考源项目 EarthLord/ExplorationManager.swift
//

import Foundation
import CoreLocation
import SwiftUI
import Combine
import Supabase

// MARK: - 探索状态

enum ExplorationState: Equatable {
    case idle           // 空闲
    case exploring      // 探索中
    case ending         // 结束中
    case completed      // 已完成
    case failed(String) // 失败

    static func == (lhs: ExplorationState, rhs: ExplorationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.exploring, .exploring), (.ending, .ending), (.completed, .completed):
            return true
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - 探索会话

struct ExplorationSession: Identifiable {
    let id: UUID
    let userId: UUID
    let startedAt: Date
    var endedAt: Date?
    var status: String

    // 统计数据
    var totalDistance: Double = 0      // 米
    var totalArea: Double = 0          // 平方米
    var gridCount: Int = 0             // 网格数
    var caloriesBurned: Double = 0     // 千卡

    // 路线点
    var routePoints: [CLLocation] = []
}

// MARK: - 探索结果

struct ExplorationResult {
    let session: ExplorationSession
    let success: Bool
    let message: String?

    // 统计摘要
    var distanceKm: Double {
        session.totalDistance / 1000.0
    }

    var durationMinutes: Int {
        guard let endedAt = session.endedAt else { return 0 }
        return Int(endedAt.timeIntervalSince(session.startedAt) / 60)
    }

    var areaDisplay: String {
        if session.totalArea >= 10000 {
            return String(format: "%.2f 公顷", session.totalArea / 10000)
        } else {
            return String(format: "%.0f m²", session.totalArea)
        }
    }
}

// MARK: - 网格坐标（用于面积统计）

struct GridCoordinate: Hashable {
    let x: Int
    let y: Int

    init(location: CLLocation, gridSize: Double = 50.0) {
        // 将经纬度转换为网格坐标
        // 每个网格 50m x 50m
        let metersPerDegree = 111000.0
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        self.y = Int(lat * metersPerDegree / gridSize)
        self.x = Int(lon * metersPerDegree * cos(lat * .pi / 180) / gridSize)
    }
}

// MARK: - ExplorationManager

@MainActor
class ExplorationManager: ObservableObject {

    // MARK: - 单例
    static let shared = ExplorationManager()

    // MARK: - Published 属性
    @Published private(set) var state: ExplorationState = .idle
    @Published private(set) var currentSession: ExplorationSession?
    @Published private(set) var isExploring: Bool = false

    // 实时统计（探索中更新）
    @Published private(set) var currentDistance: Double = 0      // 米
    @Published private(set) var currentGridCount: Int = 0        // 网格数
    @Published private(set) var currentCalories: Double = 0      // 千卡
    @Published private(set) var explorationDuration: TimeInterval = 0  // 秒

    // MARK: - 私有属性
    private var exploredGrids: Set<GridCoordinate> = []
    private var lastLocation: CLLocation?
    private var durationTimer: Timer?
    private let gridSize: Double = 50.0  // 每个网格 50m x 50m
    private let userWeight: Double = 70.0  // 默认体重 70kg

    // Supabase
    private var supabase: SupabaseClient {
        return SupabaseManager.shared.client
    }

    // MARK: - 初始化

    init() {
        appLog(.info, category: "探索", message: "ExplorationManager 初始化")
    }

    // MARK: - 公开方法

    /// 开始探索
    func startExploration(userId: UUID, startLocation: CLLocation?) async -> Bool {
        guard state == .idle else {
            appLog(.warning, category: "探索", message: "已有探索进行中，无法开始新探索")
            return false
        }

        appLog(.info, category: "探索", message: "开始探索...")

        // 创建新会话
        let sessionId = UUID()
        let now = Date()

        var session = ExplorationSession(
            id: sessionId,
            userId: userId,
            startedAt: now,
            status: "active"
        )

        // 记录起点
        if let location = startLocation {
            session.routePoints.append(location)
            lastLocation = location

            // 初始化第一个网格
            let grid = GridCoordinate(location: location, gridSize: gridSize)
            exploredGrids.insert(grid)
        }

        // 保存到数据库
        do {
            try await saveSessionToDatabase(session, startLocation: startLocation)
            appLog(.success, category: "探索", message: "探索会话已创建: \(sessionId)")
        } catch {
            appLog(.error, category: "探索", message: "创建探索会话失败: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
            return false
        }

        // 更新状态
        currentSession = session
        state = .exploring
        isExploring = true
        currentDistance = 0
        currentGridCount = 1
        currentCalories = 0
        explorationDuration = 0

        // 启动计时器
        startDurationTimer()

        appLog(.success, category: "探索", message: "探索开始！")
        return true
    }

    /// 结束探索
    func endExploration(endLocation: CLLocation?) async -> ExplorationResult? {
        guard state == .exploring, var session = currentSession else {
            appLog(.warning, category: "探索", message: "没有进行中的探索")
            return nil
        }

        state = .ending
        appLog(.info, category: "探索", message: "结束探索...")

        // 停止计时器
        stopDurationTimer()

        // 记录终点
        if let location = endLocation {
            session.routePoints.append(location)
            trackLocation(location)
        }

        // 更新会话数据
        session.endedAt = Date()
        session.status = "completed"
        session.totalDistance = currentDistance
        session.totalArea = Double(currentGridCount) * gridSize * gridSize
        session.gridCount = currentGridCount
        session.caloriesBurned = currentCalories

        // 更新数据库
        do {
            try await updateSessionInDatabase(session, endLocation: endLocation)
            appLog(.success, category: "探索", message: "探索会话已保存")
        } catch {
            appLog(.error, category: "探索", message: "保存探索会话失败: \(error.localizedDescription)")
        }

        // 创建结果
        let result = ExplorationResult(
            session: session,
            success: true,
            message: "探索完成！"
        )

        // 重置状态
        currentSession = nil
        state = .completed
        isExploring = false
        exploredGrids.removeAll()
        lastLocation = nil

        // 2秒后重置为idle
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                self.state = .idle
            }
        }

        appLog(.success, category: "探索", message: "探索结束！距离: \(String(format: "%.2f", result.distanceKm))km, 时长: \(result.durationMinutes)分钟, 面积: \(result.areaDisplay)")

        return result
    }

    /// 取消探索
    func cancelExploration() async {
        guard state == .exploring, var session = currentSession else {
            return
        }

        appLog(.info, category: "探索", message: "取消探索...")

        stopDurationTimer()

        session.endedAt = Date()
        session.status = "cancelled"

        // 更新数据库
        do {
            try await updateSessionInDatabase(session, endLocation: lastLocation)
        } catch {
            appLog(.error, category: "探索", message: "取消探索失败: \(error.localizedDescription)")
        }

        // 重置状态
        currentSession = nil
        state = .idle
        isExploring = false
        exploredGrids.removeAll()
        lastLocation = nil
        currentDistance = 0
        currentGridCount = 0
        currentCalories = 0
        explorationDuration = 0

        appLog(.info, category: "探索", message: "探索已取消")
    }

    /// 追踪位置（探索中调用）
    func trackLocation(_ location: CLLocation) {
        guard isExploring, var session = currentSession else { return }

        // 添加到路线
        session.routePoints.append(location)
        currentSession = session

        // 计算距离增量
        if let last = lastLocation {
            let delta = location.distance(from: last)

            // 过滤异常数据（速度过快可能是GPS跳点）
            let timeDelta = location.timestamp.timeIntervalSince(last.timestamp)
            if timeDelta > 0 {
                let speed = delta / timeDelta  // m/s
                if speed < 50 {  // 小于 180km/h 才计入
                    currentDistance += delta

                    // 计算热量（简化公式：距离km × 体重kg × 0.5）
                    currentCalories = (currentDistance / 1000) * userWeight * 0.5
                }
            }
        }

        // 更新网格
        let grid = GridCoordinate(location: location, gridSize: gridSize)
        if !exploredGrids.contains(grid) {
            exploredGrids.insert(grid)
            currentGridCount = exploredGrids.count
        }

        lastLocation = location
    }

    // MARK: - 私有方法

    /// 启动时长计时器
    private func startDurationTimer() {
        stopDurationTimer()

        // 使用 Task 代替 Timer，避免并发问题
        Task { @MainActor [weak self] in
            while let self = self, self.isExploring, let session = self.currentSession {
                self.explorationDuration = Date().timeIntervalSince(session.startedAt)
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
            }
        }
    }

    /// 停止时长计时器
    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    /// 保存会话到数据库（使用 REST API）
    private func saveSessionToDatabase(_ session: ExplorationSession, startLocation: CLLocation?) async throws {
        try await explorationUploader.create(
            id: session.id.uuidString,
            userId: session.userId.uuidString,
            status: session.status,
            startedAt: ISO8601DateFormatter().string(from: session.startedAt),
            startLatitude: startLocation?.coordinate.latitude,
            startLongitude: startLocation?.coordinate.longitude,
            totalDistance: 0,
            totalArea: 0,
            gridCount: 0,
            caloriesBurned: 0,
            supabaseUrl: SupabaseConfig.supabaseURL.absoluteString,
            anonKey: SupabaseConfig.supabaseAnonKey,
            accessToken: try? await supabase.auth.session.accessToken
        )
    }

    /// 更新会话到数据库（使用 REST API）
    private func updateSessionInDatabase(_ session: ExplorationSession, endLocation: CLLocation?) async throws {
        // 转换路线点为基础类型字典数组
        let routePoints: [[String: Double]] = session.routePoints.map { loc in
            [
                "lat": loc.coordinate.latitude,
                "lon": loc.coordinate.longitude,
                "timestamp": loc.timestamp.timeIntervalSince1970
            ]
        }

        var durationSeconds: Int? = nil
        var endedAtString: String? = nil

        if let endedAt = session.endedAt {
            endedAtString = ISO8601DateFormatter().string(from: endedAt)
            durationSeconds = Int(endedAt.timeIntervalSince(session.startedAt))
        }

        try await explorationUploader.update(
            sessionId: session.id.uuidString,
            status: session.status,
            endedAt: endedAtString,
            durationSeconds: durationSeconds,
            endLatitude: endLocation?.coordinate.latitude,
            endLongitude: endLocation?.coordinate.longitude,
            totalDistance: session.totalDistance,
            totalArea: session.totalArea,
            gridCount: session.gridCount,
            caloriesBurned: session.caloriesBurned,
            routePoints: routePoints,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            supabaseUrl: SupabaseConfig.supabaseURL.absoluteString,
            anonKey: SupabaseConfig.supabaseAnonKey,
            accessToken: try? await supabase.auth.session.accessToken
        )
    }

    // MARK: - 格式化显示

    /// 格式化距离显示
    var distanceDisplay: String {
        if currentDistance >= 1000 {
            return String(format: "%.2f km", currentDistance / 1000)
        } else {
            return String(format: "%.0f m", currentDistance)
        }
    }

    /// 格式化时长显示
    var durationDisplay: String {
        let minutes = Int(explorationDuration) / 60
        let seconds = Int(explorationDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// 格式化面积显示
    var areaDisplay: String {
        let area = Double(currentGridCount) * gridSize * gridSize
        if area >= 10000 {
            return String(format: "%.2f 公顷", area / 10000)
        } else {
            return String(format: "%.0f m²", area)
        }
    }

    /// 格式化热量显示
    var caloriesDisplay: String {
        return String(format: "%.0f 千卡", currentCalories)
    }
}
