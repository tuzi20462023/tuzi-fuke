//
//  GeocodingService.swift
//  tuzi-fuke (地球新主复刻版)
//
//  地理编码服务 - 使用 iOS CLGeocoder
//  Created by AI Assistant on 2025/12/05.
//

import Foundation
import SwiftUI
import Combine
import CoreLocation

// MARK: - 地理编码服务

@MainActor
class GeocodingService: ObservableObject {
    static let shared = GeocodingService()

    private let geocoder = CLGeocoder()

    @Published var isLoading = false
    @Published var error: String?

    private init() {}

    // MARK: - 反向地理编码

    /// 获取位置的地址信息
    func reverseGeocode(location: CLLocation) async -> LocationInfo? {
        isLoading = true
        error = nil

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)

            guard let placemark = placemarks.first else {
                self.error = "未找到地址信息"
                self.isLoading = false
                return nil
            }

            let info = LocationInfo(from: placemark)

            self.isLoading = false
            print("✅ [GeocodingService] 地址解析成功: \(info.displayName)")
            return info

        } catch {
            print("❌ [GeocodingService] 地址解析失败: \(error.localizedDescription)")
            self.error = error.localizedDescription
            self.isLoading = false
            return nil
        }
    }

    /// 获取坐标的地址信息
    func reverseGeocode(latitude: Double, longitude: Double) async -> LocationInfo? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        return await reverseGeocode(location: location)
    }

    // MARK: - 正向地理编码

    /// 根据地址获取坐标
    func geocode(address: String) async -> CLLocation? {
        isLoading = true
        error = nil

        do {
            let placemarks = try await geocoder.geocodeAddressString(address)

            guard let placemark = placemarks.first,
                  let location = placemark.location else {
                self.error = "未找到对应位置"
                self.isLoading = false
                return nil
            }

            self.isLoading = false
            return location

        } catch {
            print("❌ [GeocodingService] 地址编码失败: \(error.localizedDescription)")
            self.error = error.localizedDescription
            self.isLoading = false
            return nil
        }
    }
}

// MARK: - 位置信息模型

struct LocationInfo {
    let country: String?          // 国家
    let administrativeArea: String?  // 省/州
    let locality: String?         // 城市
    let subLocality: String?      // 区/县
    let thoroughfare: String?     // 街道
    let subThoroughfare: String?  // 门牌号
    let name: String?             // 地点名称
    let postalCode: String?       // 邮编

    init(from placemark: CLPlacemark) {
        self.country = placemark.country
        self.administrativeArea = placemark.administrativeArea
        self.locality = placemark.locality
        self.subLocality = placemark.subLocality
        self.thoroughfare = placemark.thoroughfare
        self.subThoroughfare = placemark.subThoroughfare
        self.name = placemark.name
        self.postalCode = placemark.postalCode
    }

    init(
        country: String? = nil,
        administrativeArea: String? = nil,
        locality: String? = nil,
        subLocality: String? = nil,
        thoroughfare: String? = nil,
        subThoroughfare: String? = nil,
        name: String? = nil,
        postalCode: String? = nil
    ) {
        self.country = country
        self.administrativeArea = administrativeArea
        self.locality = locality
        self.subLocality = subLocality
        self.thoroughfare = thoroughfare
        self.subThoroughfare = subThoroughfare
        self.name = name
        self.postalCode = postalCode
    }

    /// 显示名称（用于UI）
    var displayName: String {
        // 优先使用地点名称
        if let name = name, !name.isEmpty {
            return name
        }

        // 其次使用街道地址
        var parts: [String] = []

        if let subLocality = subLocality {
            parts.append(subLocality)
        }
        if let thoroughfare = thoroughfare {
            parts.append(thoroughfare)
        }
        if let subThoroughfare = subThoroughfare {
            parts.append(subThoroughfare)
        }

        if !parts.isEmpty {
            return parts.joined(separator: "")
        }

        // 最后使用城市
        if let locality = locality {
            return locality
        }

        return "未知位置"
    }

    /// 完整地址
    var fullAddress: String {
        var parts: [String] = []

        if let country = country {
            parts.append(country)
        }
        if let administrativeArea = administrativeArea {
            parts.append(administrativeArea)
        }
        if let locality = locality {
            parts.append(locality)
        }
        if let subLocality = subLocality {
            parts.append(subLocality)
        }
        if let thoroughfare = thoroughfare {
            parts.append(thoroughfare)
        }
        if let subThoroughfare = subThoroughfare {
            parts.append(subThoroughfare)
        }

        return parts.joined(separator: "")
    }

    /// 简短地址（用于打卡显示）
    var shortAddress: String {
        var parts: [String] = []

        if let locality = locality {
            parts.append(locality)
        }
        if let subLocality = subLocality {
            parts.append(subLocality)
        }

        if parts.isEmpty {
            return displayName
        }

        return parts.joined(separator: " · ")
    }

    /// 末世风格的位置描述（用于AI提示词）
    var apocalypticDescription: String {
        let cityName = locality ?? administrativeArea ?? "废墟城市"
        let areaName = subLocality ?? thoroughfare ?? "荒废区域"

        return "\(cityName)的\(areaName)废墟"
    }
}

// MARK: - 预览支持

extension GeocodingService {
    /// 创建预览用的位置信息
    static func previewLocationInfo() -> LocationInfo {
        return LocationInfo(
            country: "中国",
            administrativeArea: "上海市",
            locality: "上海市",
            subLocality: "浦东新区",
            thoroughfare: "世纪大道",
            subThoroughfare: "100号",
            name: "东方明珠"
        )
    }
}
