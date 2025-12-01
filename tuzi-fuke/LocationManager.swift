//
//  LocationManager.swift
//  tuzi-fuke (地球新主复刻版)
//
//  GPS定位管理器 - 支持可变体架构设计
//  Created by AI Assistant on 2025/11/21.
//

import Foundation
import CoreLocation
import SwiftUI
import Combine
import UIKit  // 用于震动反馈

// MARK: - 定位协议 (支持变体扩展)

/// 定位管理器协议 - 支持不同游戏的定位需求
protocol LocationManagerProtocol: ObservableObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var currentLocation: CLLocation? { get }
    var locationState: LocationState { get }
    var isLocationServiceEnabled: Bool { get }

    func requestLocationPermission()
    func startLocationUpdates() async throws
    func stopLocationUpdates()
    func getCurrentLocation() async throws -> CLLocation

}

// MARK: - 定位状态枚举

enum LocationState {
    case idle
    case requesting
    case updating
    case failed(LocationError)
    case denied

    var isActive: Bool {
        if case .updating = self {
            return true
        }
        return false
    }
}

// MARK: - 定位错误类型

enum LocationError: Error, LocalizedError {
    case permissionDenied
    case locationServiceDisabled
    case locationUnavailable
    case accuracyTooLow
    case timeout
    case unknownError(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "位置权限被拒绝，请在设置中开启位置权限"
        case .locationServiceDisabled:
            return "位置服务已关闭，请在设置中开启位置服务"
        case .locationUnavailable:
            return "无法获取当前位置，请检查GPS信号"
        case .accuracyTooLow:
            return "位置精度过低，请移动到空旷区域"
        case .timeout:
            return "定位超时，请重试"
        case .unknownError(let message):
            return "定位错误: \(message)"
        }
    }
}

// MARK: - LocationManager 主实现

/// GPS定位管理器 - 支持多种游戏场景的定位需求
@MainActor
class LocationManager: NSObject, LocationManagerProtocol {

    // MARK: - 单例
    static let shared = LocationManager()

    // MARK: - Published 属性
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var locationState: LocationState = .idle
    @Published private(set) var lastLocationUpdate: Date?

    // MARK: - 计算属性
    var isLocationServiceEnabled: Bool {
        // 缓存值以避免主线程调用
        return _isLocationServiceEnabled
    }

    // 私有缓存属性（初始化时在后台检查）
    private var _isLocationServiceEnabled: Bool = true

    var hasLocationPermission: Bool {
        return authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    // MARK: - 私有属性
    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var isUpdatingLocation = false

    // MARK: - 数据采集和上传属性
    private var collectionTimer: Timer?
    private var uploadTimer: Timer?
    private(set) var pendingPositions: [Position] = []
    private var positionRepository: PositionRepository?

    // MARK: - 采集配置
    @Published private(set) var isCollecting = false
    @Published private(set) var collectionInterval: TimeInterval = 30.0  // 30秒采集一次
    @Published private(set) var uploadInterval: TimeInterval = 300.0     // 5分钟上传一次
    @Published private(set) var maxBatchSize = 20                        // 最大批量上传数量
    @Published private(set) var totalCollectedCount = 0
    @Published private(set) var totalUploadedCount = 0
    @Published private(set) var lastUploadTime: Date?
    @Published private(set) var uploadStatus: PositionUploadStatus = .pending

    // MARK: - 配置属性
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    var distanceFilter: CLLocationDistance = 5.0  // 5米（与原项目一致）
    var locationTimeout: TimeInterval = 30.0       // 30秒

    // MARK: - 路径追踪属性（圈地功能）
    @Published private(set) var isTracking = false          // 是否正在追踪路径
    @Published private(set) var trackingPath: [CLLocation] = []  // 追踪的路径点
    @Published private(set) var isPathClosed = false        // 路径是否闭环
    @Published private(set) var enclosedArea: Double = 0    // 闭环面积（平方米）
    @Published private(set) var trackingStartTime: Date?    // 追踪开始时间
    @Published private(set) var pathUpdateVersion: Int = 0  // 路径更新版本号（用于强制刷新UI）
    @Published private(set) var hasSelfIntersection = false // 是否检测到自相交

    // MARK: - 实时碰撞检测属性（参考源项目）
    @Published var collisionWarning: String?                // 碰撞警告消息（显示在UI上）
    @Published private(set) var currentWarningLevel: WarningLevel = .safe  // 当前预警级别

    private var pathUpdateTimer: Timer?

    // 闭环检测阈值（与原项目一致）
    // 圈地判定阈值（与UI显示保持一致）
    private let closureDistanceThreshold: CLLocationDistance = 8.0   // 起点终点距离阈值(米) - 更严格
    private let minimumPathPoints = 10                               // 最少路径点数
    private let minimumTotalDistance: Double = 60.0                  // 最小总行走距离(米)
    private let minimumEnclosedArea: Double = 120.0                  // 最小领地面积(平米)
    // 注意：已移除 maximumCompactness 检查，原项目没有此限制，且实测发现限制太严格

    // 震动反馈生成器
    private let lightFeedback = UIImpactFeedbackGenerator(style: .light)
    private let heavyFeedback = UIImpactFeedbackGenerator(style: .heavy)
    private let successFeedback = UINotificationFeedbackGenerator()

    // MARK: - 初始化
    override init() {
        super.init()
        print("📍 [LocationManager] 初始化定位管理器")
        setupLocationManager()
        setupPositionRepository()
    }

    // MARK: - 公共方法

    /// 请求位置权限
    func requestLocationPermission() {
        print("📍 [LocationManager] 请求位置权限")

        guard isLocationServiceEnabled else {
            locationState = .failed(.locationServiceDisabled)
            print("❌ [LocationManager] 位置服务未开启")
            return
        }

        locationState = .requesting

        switch authorizationStatus {
        case .notDetermined:
            // 请求权限
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            locationState = .denied
            print("❌ [LocationManager] 位置权限被拒绝")
        case .authorizedWhenInUse:
            // 如果需要后台位置，请求always权限
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            locationState = .idle
            print("✅ [LocationManager] 已获得完整位置权限")
        @unknown default:
            locationState = .failed(.unknownError("未知权限状态"))
        }
    }

    /// 开始位置更新
    func startLocationUpdates() async throws {
        print("📍 [LocationManager] 开始位置更新")

        guard hasLocationPermission else {
            throw LocationError.permissionDenied
        }

        guard isLocationServiceEnabled else {
            throw LocationError.locationServiceDisabled
        }

        guard !isUpdatingLocation else {
            print("⚠️ [LocationManager] 位置更新已在进行中")
            return
        }

        isUpdatingLocation = true
        locationState = .updating

        locationManager.startUpdatingLocation()

        print("✅ [LocationManager] 位置更新已启动")
    }

    /// 停止位置更新
    func stopLocationUpdates() {
        print("📍 [LocationManager] 停止位置更新")

        isUpdatingLocation = false
        locationManager.stopUpdatingLocation()
        locationState = .idle

        print("✅ [LocationManager] 位置更新已停止")
    }

    /// 获取单次位置 (用于一次性定位)
    func getCurrentLocation() async throws -> CLLocation {
        print("📍 [LocationManager] 获取当前位置")

        guard hasLocationPermission else {
            throw LocationError.permissionDenied
        }

        guard isLocationServiceEnabled else {
            throw LocationError.locationServiceDisabled
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation

            // 设置超时
            Task {
                try? await Task.sleep(nanoseconds: UInt64(locationTimeout * 1_000_000_000))
                if locationContinuation != nil {
                    locationContinuation?.resume(throwing: LocationError.timeout)
                    locationContinuation = nil
                }
            }

            // 请求单次位置更新
            locationManager.requestLocation()
        }
    }

    // MARK: - 数据采集和上传方法

    /// 开始定时位置数据采集
    func startLocationCollection(userId: UUID) async throws {
        print("📍 [LocationManager] 开始定时位置数据采集")

        guard hasLocationPermission else {
            throw LocationError.permissionDenied
        }

        guard !isCollecting else {
            print("⚠️ [LocationManager] 位置采集已在进行中")
            return
        }

        // 开始位置更新
        try await startLocationUpdates()

        isCollecting = true

        // 立即采集一次位置数据
        await collectCurrentLocation(userId: userId)

        // 设置采集定时器
        await MainActor.run {
            collectionTimer = Timer.scheduledTimer(withTimeInterval: collectionInterval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.collectCurrentLocation(userId: userId)
                }
            }
        }

        // 设置上传定时器
        await MainActor.run {
            uploadTimer = Timer.scheduledTimer(withTimeInterval: uploadInterval, repeats: true) { [weak self] _ in
                Task { [weak self] in
                    await self?.uploadPendingPositions()
                }
            }
        }

        print("✅ [LocationManager] 位置数据采集已启动")
        print("   - 采集间隔: \(collectionInterval)秒")
        print("   - 上传间隔: \(uploadInterval)秒")
    }

    /// 停止位置数据采集
    func stopLocationCollection() {
        print("📍 [LocationManager] 停止位置数据采集")

        collectionTimer?.invalidate()
        collectionTimer = nil

        uploadTimer?.invalidate()
        uploadTimer = nil

        stopLocationUpdates()
        isCollecting = false

        // 立即上传剩余数据
        Task {
            await uploadPendingPositions()
        }

        print("✅ [LocationManager] 位置数据采集已停止")
    }

    /// 采集当前位置数据
    private func collectCurrentLocation(userId: UUID) async {
        guard let currentLocation = self.currentLocation else {
            print("⚠️ [LocationManager] 当前位置不可用")
            return
        }

        // 验证位置精度
        guard isLocationAccuracyAcceptable(currentLocation) else {
            print("⚠️ [LocationManager] 位置精度不够，跳过采集")
            return
        }

        // 创建Position对象
        let position = Position(from: currentLocation, userId: userId)

        // 添加到待上传队列
        await MainActor.run {
            pendingPositions.append(position)
            totalCollectedCount += 1
        }

        print("📍 [LocationManager] 位置数据已采集: \(position.formattedDescription())")
        print("   - 待上传队列: \(pendingPositions.count) 条")

        // 如果达到最大批量大小，立即上传
        if pendingPositions.count >= maxBatchSize {
            await uploadPendingPositions()
        }
    }

    /// 上传待处理的位置数据
    private func uploadPendingPositions() async {
        guard !pendingPositions.isEmpty else {
            print("📍 [LocationManager] 没有待上传的位置数据")
            return
        }

        guard let repository = positionRepository else {
            print("❌ [LocationManager] PositionRepository未初始化")
            return
        }

        let batch = PositionBatch(positions: pendingPositions)
        await MainActor.run {
            uploadStatus = .uploading
        }

        print("📍 [LocationManager] 开始上传位置数据批次: \(batch.count) 条")

        do {
            let uploadedPositions = try await repository.uploadBatch(batch)

            await MainActor.run {
                totalUploadedCount += uploadedPositions.count
                lastUploadTime = Date()
                uploadStatus = .uploaded
                pendingPositions.removeAll()
            }

            print("✅ [LocationManager] 位置数据上传成功: \(uploadedPositions.count) 条")

        } catch {
            await MainActor.run {
                uploadStatus = .failed(error)
            }
            print("❌ [LocationManager] 位置数据上传失败: \(error.localizedDescription)")
        }
    }

    /// 手动触发位置上传
    func uploadNow() async {
        print("📍 [LocationManager] 手动触发位置上传")
        print("   - 当前待上传: \(pendingPositions.count) 条")
        await uploadPendingPositions()
    }

    /// 配置采集参数
    func configureCollection(
        interval: TimeInterval? = nil,
        uploadInterval: TimeInterval? = nil,
        batchSize: Int? = nil
    ) {
        if let interval = interval {
            self.collectionInterval = interval
        }
        if let uploadInterval = uploadInterval {
            self.uploadInterval = uploadInterval
        }
        if let batchSize = batchSize {
            self.maxBatchSize = batchSize
        }

        print("📍 [LocationManager] 采集配置已更新:")
        print("   - 采集间隔: \(collectionInterval)秒")
        print("   - 上传间隔: \(self.uploadInterval)秒")
        print("   - 批量大小: \(maxBatchSize)")
    }

    // MARK: - 路径追踪方法（圈地功能）

    /// 开始路径追踪（圈地）
    func startPathTracking() {
        guard !isTracking else {
            appLog(.warning, category: "路径追踪", message: "已在进行中，忽略")
            return
        }

        appLog(.success, category: "路径追踪", message: "🚀 开始圈地！")

        isTracking = true
        trackingPath.removeAll()
        isPathClosed = false
        hasSelfIntersection = false
        enclosedArea = 0
        trackingStartTime = Date()

        // 启用后台定位
        locationManager.allowsBackgroundLocationUpdates = true

        // 设置路径更新定时器（每2秒检查一次）
        pathUpdateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recordPathPoint()
            }
        }

        appLog(.info, category: "路径追踪", message: "后台定位已启用，定时器已启动")
    }

    /// 停止路径追踪
    func stopPathTracking() {
        appLog(.info, category: "路径追踪", message: "🛑 停止圈地")

        isTracking = false

        pathUpdateTimer?.invalidate()
        pathUpdateTimer = nil

        // 禁用后台定位（节省电量）
        locationManager.allowsBackgroundLocationUpdates = false

        // 检测闭环
        checkPathClosure()

        appLog(.info, category: "路径追踪", message: "已停止，总点数: \(trackingPath.count)")
    }

    /// 清除路径
    func clearPath() {
        trackingPath.removeAll()
        isPathClosed = false
        hasSelfIntersection = false
        enclosedArea = 0
        trackingStartTime = nil
        pathUpdateVersion += 1   // 通知地图刷新，移除残留轨迹
        collisionWarning = nil   // 清除碰撞警告
        currentWarningLevel = .safe
        appLog(.info, category: "路径追踪", message: "🗑️ 路径已清除")
    }

    /// 更新碰撞警告状态（由 SimpleMapView 调用）
    func updateCollisionWarning(_ warning: String?, level: WarningLevel) {
        collisionWarning = warning
        currentWarningLevel = level
    }

    /// 记录路径点
    private func recordPathPoint() {
        guard isTracking, let location = currentLocation else { return }

        // 验证精度
        guard isLocationAccuracyAcceptable(location, minimumAccuracy: 50) else {
            print("⚠️ [LocationManager] GPS精度不够，跳过记录")
            return
        }

        if trackingPath.isEmpty {
            // 第一个点，必须记录
            trackingPath.append(location)
            pathUpdateVersion += 1  // 强制UI刷新
            lightFeedback.impactOccurred()  // 轻震动反馈
            print("📍 [路径追踪] 起点: \(trackingPath.count)个点, v\(pathUpdateVersion)")
        } else {
            guard let lastPoint = trackingPath.last else { return }

            let distanceFromLast = location.distance(from: lastPoint)
            let timeFromLast = location.timestamp.timeIntervalSince(lastPoint.timestamp)

            // 移动超过5米 或 超过30秒且有微小移动(>2米)
            if distanceFromLast > 5 {
                trackingPath.append(location)
                pathUpdateVersion += 1  // 强制UI刷新
                lightFeedback.impactOccurred()  // 轻震动反馈
                print("📍 [路径追踪] 距离触发: \(Int(distanceFromLast))m, 点数=\(trackingPath.count), v\(pathUpdateVersion)")
            } else if timeFromLast > 30 && distanceFromLast > 2 {
                trackingPath.append(location)
                pathUpdateVersion += 1  // 强制UI刷新
                lightFeedback.impactOccurred()  // 轻震动反馈
                print("📍 [路径追踪] 时间触发: \(Int(timeFromLast))s, 点数=\(trackingPath.count), v\(pathUpdateVersion)")
            }
        }

        // 检查闭环
        checkPathClosure()
    }

    /// 检查路径是否形成闭环
    /// 参考原项目 EarthLord/LocationManager.swift 的 checkPathClosure 方法
    func checkPathClosure() {
        guard !trackingPath.isEmpty else {
            isPathClosed = false
            appLog(.debug, category: "闭环检测", message: "路径为空")
            return
        }

        guard trackingPath.count >= minimumPathPoints else {
            isPathClosed = false
            appLog(.debug, category: "闭环检测", message: "点数不足: \(trackingPath.count)/\(minimumPathPoints)")
            return
        }

        // 第一步：自相交检测（必须在其他检测之前，参考原项目）
        if hasPathSelfIntersection() {
            if !hasSelfIntersection {
                hasSelfIntersection = true
                successFeedback.notificationOccurred(.warning)
                appLog(.error, category: "自相交", message: "检测到路径自相交！")
            }
            isPathClosed = false
            return
        } else {
            if hasSelfIntersection {
                appLog(.success, category: "自相交", message: "自相交已解除")
            }
            hasSelfIntersection = false
        }

        guard let firstPoint = trackingPath.first,
              let lastPoint = trackingPath.last else {
            isPathClosed = false
            return
        }

        // 计算起终点距离
        let distance = firstPoint.distance(from: lastPoint)

        // 计算总行走距离
        let totalDistance = calculateTotalPathDistance()

        // 计算面积
        let area = calculatePolygonArea()

        appLog(.info, category: "闭环检测", message: "起终点=\(Int(distance))m, 总距离=\(Int(totalDistance))m, 面积=\(Int(area))m², 点数=\(trackingPath.count)")

        // 检查所有条件
        if distance <= closureDistanceThreshold &&
           totalDistance >= minimumTotalDistance &&
           area >= minimumEnclosedArea {
            // 只在状态变化时震动（避免重复震动）
            if !isPathClosed {
                successFeedback.notificationOccurred(.success)  // 成功震动
                heavyFeedback.impactOccurred()  // 额外强震动
                appLog(.success, category: "闭环检测", message: "✅ 闭环成功! 面积: \(Int(area))m²")
            }
            isPathClosed = true
            enclosedArea = area
        } else {
            isPathClosed = false
            if distance > closureDistanceThreshold {
                appLog(.warning, category: "闭环检测", message: "起终点距离: \(Int(distance))m (需≤\(Int(closureDistanceThreshold))m)")
            }
            if totalDistance < minimumTotalDistance {
                appLog(.warning, category: "闭环检测", message: "行走距离: \(Int(totalDistance))m (需≥\(Int(minimumTotalDistance))m)")
            }
            if area < minimumEnclosedArea {
                appLog(.warning, category: "闭环检测", message: "面积: \(Int(area))m² (需≥\(Int(minimumEnclosedArea))m²)")
            }
        }
    }

    /// 计算紧凑度（供UI显示）
    func calculateCompactness() -> Double {
        let totalDistance = calculateTotalPathDistance()
        let area = calculatePolygonArea()
        guard area > 0 else { return 999 }
        return (totalDistance * totalDistance) / (4 * .pi * area)
    }

    /// 计算路径总距离
    func calculateTotalPathDistance() -> Double {
        guard trackingPath.count > 1 else { return 0 }

        var totalDistance: Double = 0
        for i in 1..<trackingPath.count {
            totalDistance += trackingPath[i-1].distance(from: trackingPath[i])
        }
        return totalDistance
    }

    /// 使用Shoelace公式计算多边形面积
    func calculatePolygonArea() -> Double {
        guard trackingPath.count >= 3 else { return 0 }

        var area: Double = 0
        let earthRadius: Double = 6371000 // 地球半径(米)

        for i in 0..<trackingPath.count {
            let current = trackingPath[i]
            let next = trackingPath[(i + 1) % trackingPath.count]

            let lat1 = current.coordinate.latitude * .pi / 180
            let lon1 = current.coordinate.longitude * .pi / 180
            let lat2 = next.coordinate.latitude * .pi / 180
            let lon2 = next.coordinate.longitude * .pi / 180

            area += (lon2 - lon1) * (2 + sin(lat1) + sin(lat2))
        }

        area = abs(area * earthRadius * earthRadius / 2.0)
        return area
    }

    // MARK: - 自相交检测（参考原项目 CCW 算法）

    /// 检测路径是否存在自相交
    /// 使用 CCW (Counter-Clockwise) 算法检测线段相交
    /// - Returns: true 表示存在自相交，false 表示路径有效
    func hasPathSelfIntersection() -> Bool {
        guard trackingPath.count >= 4 else { return false }

        // 使用快照避免并发修改
        let pathSnapshot = trackingPath

        // 检查每条线段与所有非相邻线段是否相交
        for i in 0..<(pathSnapshot.count - 1) {
            let p1 = pathSnapshot[i]
            let p2 = pathSnapshot[i + 1]

            // 从 i+2 开始，避免检查相邻线段
            let start = i + 2
            let end = pathSnapshot.count - 1
            if start >= end { continue }

            for j in start..<end {
                // 跳过首尾线段的比较（它们在闭环时会相连）
                if i == 0 && j == pathSnapshot.count - 2 { continue }

                let p3 = pathSnapshot[j]
                let p4 = pathSnapshot[j + 1]

                if segmentsIntersect(p1, p2, p3, p4) {
                    appLog(.error, category: "自相交", message: "线段[\(i)-\(i+1)]与[\(j)-\(j+1)]交叉")
                    appLog(.debug, category: "自相交", message: "P1(\(String(format: "%.6f", p1.coordinate.latitude)),\(String(format: "%.6f", p1.coordinate.longitude)))")
                    appLog(.debug, category: "自相交", message: "P2(\(String(format: "%.6f", p2.coordinate.latitude)),\(String(format: "%.6f", p2.coordinate.longitude)))")
                    appLog(.debug, category: "自相交", message: "P3(\(String(format: "%.6f", p3.coordinate.latitude)),\(String(format: "%.6f", p3.coordinate.longitude)))")
                    appLog(.debug, category: "自相交", message: "P4(\(String(format: "%.6f", p4.coordinate.latitude)),\(String(format: "%.6f", p4.coordinate.longitude)))")
                    return true
                }
            }
        }
        return false
    }

    /// 检测两条线段是否相交（CCW 算法）
    private func segmentsIntersect(_ p1: CLLocation, _ p2: CLLocation,
                                   _ p3: CLLocation, _ p4: CLLocation) -> Bool {
        // CCW (Counter-Clockwise) 辅助函数
        func ccw(_ A: CLLocation, _ B: CLLocation, _ C: CLLocation) -> Bool {
            let ax = A.coordinate.longitude
            let ay = A.coordinate.latitude
            let bx = B.coordinate.longitude
            let by = B.coordinate.latitude
            let cx = C.coordinate.longitude
            let cy = C.coordinate.latitude

            return (cy - ay) * (bx - ax) > (by - ay) * (cx - ax)
        }

        // 两线段相交：两端点分别在对方两侧
        return ccw(p1, p3, p4) != ccw(p2, p3, p4) &&
               ccw(p1, p2, p3) != ccw(p1, p2, p4)
    }

    /// 计算当前位置到起点的距离
    func distanceToStart() -> Double {
        guard let firstPoint = trackingPath.first,
              let currentLoc = currentLocation else {
            return 0
        }
        return currentLoc.distance(from: firstPoint)
    }

    /// 获取路径坐标数组（用于地图渲染）
    var pathCoordinates: [CLLocationCoordinate2D] {
        return trackingPath.map { $0.coordinate }
    }

    // MARK: - 工具方法

    /// 计算两点之间的距离 (米)
    func distance(from location1: CLLocation, to location2: CLLocation) -> CLLocationDistance {
        return location1.distance(from: location2)
    }

    /// 验证位置精度是否满足要求
    func isLocationAccuracyAcceptable(_ location: CLLocation, minimumAccuracy: CLLocationAccuracy = 100) -> Bool {
        return location.horizontalAccuracy <= minimumAccuracy && location.horizontalAccuracy > 0
    }

    /// 获取位置的地理编码信息 (地址)
    /// 注意：iOS 26.0已弃用CLGeocoder，建议使用MapKit的MKReverseGeocodingRequest
    /// 保留此方法以保持兼容性
    @available(iOS, deprecated: 26.0, message: "Use MapKit's MKReverseGeocodingRequest instead")
    func reverseGeocode(_ location: CLLocation) async throws -> CLPlacemark {
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.reverseGeocodeLocation(location)

        guard let placemark = placemarks.first else {
            throw LocationError.locationUnavailable
        }

        return placemark
    }

    /// 打印定位状态调试信息
    func printLocationStatus() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📍 定位管理器状态")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("权限状态: \(authorizationStatus.description)")
        print("定位状态: \(locationState)")
        print("位置服务: \(isLocationServiceEnabled ? "✅" : "❌")")
        print("当前位置: \(currentLocation?.description ?? "无")")
        print("最后更新: \(lastLocationUpdate?.formatted() ?? "无")")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📊 数据采集状态")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("采集状态: \(isCollecting ? "✅ 进行中" : "❌ 未启动")")
        print("采集间隔: \(collectionInterval)秒")
        print("上传间隔: \(uploadInterval)秒")
        print("已采集: \(totalCollectedCount) 条")
        print("已上传: \(totalUploadedCount) 条")
        print("待上传: \(pendingPositions.count) 条")
        print("上传状态: \(uploadStatus.icon) \(uploadStatus.description)")
        print("最后上传: \(lastUploadTime?.formatted() ?? "无")")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    // MARK: - 私有方法

    /// 设置定位管理器
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = desiredAccuracy
        locationManager.distanceFilter = distanceFilter

        // 获取当前权限状态
        authorizationStatus = locationManager.authorizationStatus
        print("📍 [LocationManager] 当前权限状态: \(authorizationStatus.description)")
    }

    /// 设置位置数据仓储
    private func setupPositionRepository() {
        positionRepository = PositionRepository()
        print("📍 [LocationManager] PositionRepository已初始化")
    }

    /// 处理位置更新
    private func handleLocationUpdate(_ location: CLLocation) {
        print("📍 [LocationManager] 位置更新: \(location.coordinate)")

        // 验证位置精度
        guard isLocationAccuracyAcceptable(location) else {
            print("⚠️ [LocationManager] 位置精度不够: \(location.horizontalAccuracy)m")
            return
        }

        // 更新位置信息
        currentLocation = location
        lastLocationUpdate = Date()

        // 如果是单次定位请求，返回结果
        if let continuation = locationContinuation {
            locationContinuation = nil
            continuation.resume(returning: location)
        }

        // 🔥 关键：如果正在追踪路径，实时记录点
        if isTracking {
            recordPathPointFromLocation(location)
        }

        print("✅ [LocationManager] 位置更新成功")
    }

    /// 从 GPS 更新直接记录路径点（实时轨迹的关键）
    private func recordPathPointFromLocation(_ location: CLLocation) {
        // 验证精度
        guard isLocationAccuracyAcceptable(location, minimumAccuracy: 50) else {
            print("⚠️ [路径追踪] GPS精度不够，跳过: \(location.horizontalAccuracy)m")
            return
        }

        if trackingPath.isEmpty {
            // 第一个点，必须记录
            trackingPath.append(location)
            pathUpdateVersion += 1
            lightFeedback.impactOccurred()
            print("📍 [路径追踪] 起点已记录: v\(pathUpdateVersion)")
        } else {
            guard let lastPoint = trackingPath.last else { return }

            let distanceFromLast = location.distance(from: lastPoint)

            // 移动超过 3 米就记录（更灵敏的实时轨迹）
            if distanceFromLast >= 3 {
                trackingPath.append(location)
                pathUpdateVersion += 1

                // 每5个点轻震动一次，避免太频繁
                if trackingPath.count % 5 == 0 {
                    lightFeedback.impactOccurred()
                }

                print("📍 [路径追踪] 新点: 距离=\(Int(distanceFromLast))m, 总点数=\(trackingPath.count), v\(pathUpdateVersion)")

                // 检查闭环
                checkPathClosure()
            }
        }
    }

    /// 处理位置错误
    private func handleLocationError(_ error: Error) {
        print("❌ [LocationManager] 位置错误: \(error.localizedDescription)")

        let locationError: LocationError
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                locationError = .permissionDenied
            case .locationUnknown:
                locationError = .locationUnavailable
            case .network:
                locationError = .locationUnavailable
            default:
                locationError = .unknownError(clError.localizedDescription)
            }
        } else {
            locationError = .unknownError(error.localizedDescription)
        }

        locationState = .failed(locationError)

        // 如果是单次定位请求，返回错误
        if let continuation = locationContinuation {
            locationContinuation = nil
            continuation.resume(throwing: locationError)
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        handleLocationUpdate(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        handleLocationError(error)
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("📍 [LocationManager] 权限状态变更: \(status.description)")

        Task { @MainActor in
            self.authorizationStatus = status

            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.locationState = .idle
                print("✅ [LocationManager] 位置权限已获得")
            case .denied, .restricted:
                self.locationState = .denied
                print("❌ [LocationManager] 位置权限被拒绝")
            case .notDetermined:
                self.locationState = .idle
            @unknown default:
                self.locationState = .failed(.unknownError("未知权限状态"))
            }
        }
    }
}

// MARK: - 扩展支持

extension CLAuthorizationStatus {
    var description: String {
        switch self {
        case .notDetermined: return "未确定"
        case .restricted: return "受限制"
        case .denied: return "被拒绝"
        case .authorizedAlways: return "始终允许"
        case .authorizedWhenInUse: return "使用时允许"
        @unknown default: return "未知状态"
        }
    }
}

extension LocationState: CustomStringConvertible {
    var description: String {
        switch self {
        case .idle: return "空闲"
        case .requesting: return "请求权限中"
        case .updating: return "位置更新中"
        case .failed(let error): return "失败: \(error.localizedDescription)"
        case .denied: return "权限被拒绝"
        }
    }
}
