//
//  POI.swift
//  tuzi-fuke
//
//  POI 数据模型
//

import Foundation
import CoreLocation

// MARK: - POI 类型

enum POIType: String, CaseIterable, Codable {
    case supermarket = "supermarket"
    case restaurant = "restaurant"
    case hospital = "hospital"
    case school = "school"
    case park = "park"
    case gasStation = "gas_station"
    case factory = "factory"
    case convenienceStore = "convenience_store"
    case bank = "bank"
    case pharmacy = "pharmacy"
    case other = "other"

    /// 显示名称
    var displayName: String {
        switch self {
        case .supermarket: return "超市"
        case .restaurant: return "餐厅"
        case .hospital: return "医院"
        case .school: return "学校"
        case .park: return "公园"
        case .gasStation: return "加油站"
        case .factory: return "工厂"
        case .convenienceStore: return "便利店"
        case .bank: return "银行"
        case .pharmacy: return "药店"
        case .other: return "其他"
        }
    }

    /// 图标名称
    var iconName: String {
        switch self {
        case .supermarket: return "cart.fill"
        case .restaurant: return "fork.knife"
        case .hospital: return "cross.fill"
        case .school: return "book.fill"
        case .park: return "leaf.fill"
        case .gasStation: return "fuelpump.fill"
        case .factory: return "building.2.fill"
        case .convenienceStore: return "storefront.fill"
        case .bank: return "banknote.fill"
        case .pharmacy: return "pills.fill"
        case .other: return "mappin.circle.fill"
        }
    }

    /// 资源数量范围
    var resourceRange: ClosedRange<Int> {
        switch self {
        case .supermarket: return 150...250
        case .restaurant: return 30...60
        case .hospital: return 80...150
        case .school: return 50...100
        case .park: return 40...80
        case .gasStation: return 60...120
        case .factory: return 100...200
        case .convenienceStore: return 40...80
        case .bank: return 80...150
        case .pharmacy: return 50...100
        case .other: return 20...50
        }
    }

    /// MapKit 搜索关键词
    var searchKeywords: [String] {
        switch self {
        case .supermarket: return ["超市", "商场", "购物中心", "华润万家", "沃尔玛", "永辉"]
        case .restaurant: return ["餐厅", "饭店", "美食"]
        case .hospital: return ["医院", "诊所", "卫生院"]
        case .school: return ["学校", "大学", "中学", "小学"]
        case .park: return ["公园", "广场", "绿地"]
        case .gasStation: return ["加油站", "中石油", "中石化"]
        case .factory: return ["工厂", "工业园", "产业园"]
        case .convenienceStore: return ["便利店", "美宜佳", "7-11", "全家"]
        case .bank: return ["银行", "ATM"]
        case .pharmacy: return ["药店", "药房", "大药房"]
        case .other: return ["商店"]
        }
    }
}

// MARK: - POI 模型

struct POI: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let type: POIType
    let latitude: Double
    let longitude: Double
    let totalItems: Int
    var remainingItems: Int
    let createdAt: Date?

    /// 是否还有资源
    var hasResources: Bool {
        remainingItems > 0
    }

    /// 获取坐标
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// 计算到指定位置的距离（米）
    func distance(to location: CLLocation) -> Double {
        let poiLocation = CLLocation(latitude: latitude, longitude: longitude)
        return location.distance(from: poiLocation)
    }

    /// 从 MapKit 搜索结果创建 POI
    static func fromMapItem(
        _ mapItem: Any, // MKMapItem
        type: POIType,
        existingId: UUID? = nil
    ) -> POI? {
        guard let item = mapItem as? MKMapItem else { return nil }

        let resourceCount = Int.random(in: type.resourceRange)

        return POI(
            id: existingId ?? UUID(),
            name: item.name ?? "未知地点",
            type: type,
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude,
            totalItems: resourceCount,
            remainingItems: resourceCount,
            createdAt: Date()
        )
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case latitude
        case longitude
        case totalItems = "total_items"
        case remainingItems = "remaining_items"
        case createdAt = "created_at"
    }
}

import MapKit

// MARK: - MKMapItem 扩展

extension MKMapItem {
    /// 推断 POI 类型
    func inferPOIType() -> POIType {
        let name = self.name?.lowercased() ?? ""
        let category = self.pointOfInterestCategory

        // 根据 MapKit 类别判断
        if let cat = category {
            switch cat {
            case .hospital, .pharmacy:
                if name.contains("药") { return .pharmacy }
                return .hospital
            case .school, .university:
                return .school
            case .park, .nationalPark:
                return .park
            case .gasStation:
                return .gasStation
            case .restaurant, .cafe, .bakery, .foodMarket:
                return .restaurant
            case .bank, .atm:
                return .bank
            default:
                break
            }
        }

        // 根据名称判断
        if name.contains("超市") || name.contains("商场") || name.contains("购物") ||
           name.contains("华润") || name.contains("沃尔玛") || name.contains("永辉") {
            return .supermarket
        }
        if name.contains("便利店") || name.contains("美宜佳") || name.contains("7-11") ||
           name.contains("全家") || name.contains("罗森") {
            return .convenienceStore
        }
        if name.contains("医院") || name.contains("诊所") || name.contains("卫生") {
            return .hospital
        }
        if name.contains("药店") || name.contains("药房") || name.contains("大药房") {
            return .pharmacy
        }
        if name.contains("学校") || name.contains("大学") || name.contains("中学") || name.contains("小学") {
            return .school
        }
        if name.contains("公园") || name.contains("广场") {
            return .park
        }
        if name.contains("加油站") || name.contains("中石油") || name.contains("中石化") {
            return .gasStation
        }
        if name.contains("餐") || name.contains("饭店") || name.contains("美食") ||
           name.contains("小吃") || name.contains("面馆") {
            return .restaurant
        }
        if name.contains("工厂") || name.contains("工业") || name.contains("产业园") {
            return .factory
        }
        if name.contains("银行") || name.contains("ATM") {
            return .bank
        }

        return .other
    }
}
