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
        return CLLocationManager.locationServicesEnabled()
    }

    var hasLocationPermission: Bool {
        return authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    // MARK: - 私有属性
    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var isUpdatingLocation = false

    // MARK: - 配置属性
    var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    var distanceFilter: CLLocationDistance = 10.0  // 10米
    var locationTimeout: TimeInterval = 30.0       // 30秒

    // MARK: - 初始化
    override init() {
        super.init()
        print("📍 [LocationManager] 初始化定位管理器")
        setupLocationManager()
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

        print("✅ [LocationManager] 位置更新成功")
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

        authorizationStatus = status

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationState = .idle
            print("✅ [LocationManager] 位置权限已获得")
        case .denied, .restricted:
            locationState = .denied
            print("❌ [LocationManager] 位置权限被拒绝")
        case .notDetermined:
            locationState = .idle
        @unknown default:
            locationState = .failed(.unknownError("未知权限状态"))
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