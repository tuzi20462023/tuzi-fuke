//
//  POI.swift
//  tuzi-fuke
//
//  POI 数据模型
//

import Foundation
import CoreLocation
import MapKit

// MARK: - POI 类型

enum POIType: String, CaseIterable, Codable {
    // 旅行风格类型
    case cafe = "cafe"
    case bookstore = "bookstore"
    case park = "park"
    case restaurant = "restaurant"
    case attraction = "attraction"
    case mall = "mall"
    case convenienceStore = "convenience_store"
    case gym = "gym"
    case other = "other"

    /// 显示名称
    var displayName: String {
        switch self {
        case .cafe: return "咖啡店"
        case .bookstore: return "书店"
        case .park: return "公园"
        case .restaurant: return "餐厅"
        case .attraction: return "景点"
        case .mall: return "商场"
        case .convenienceStore: return "便利店"
        case .gym: return "健身房"
        case .other: return "其他"
        }
    }

    /// 图标名称
    var iconName: String {
        switch self {
        case .cafe: return "cup.and.saucer.fill"
        case .bookstore: return "book.fill"
        case .park: return "leaf.fill"
        case .restaurant: return "fork.knife"
        case .attraction: return "building.columns.fill"
        case .mall: return "bag.fill"
        case .convenienceStore: return "storefront.fill"
        case .gym: return "figure.run"
        case .other: return "mappin.circle.fill"
        }
    }

    /// 颜色（十六进制）- 旅行风格温暖色调
    var color: String {
        switch self {
        case .cafe: return "#8B4513"        // 咖啡棕
        case .bookstore: return "#4A90D9"   // 书香蓝
        case .park: return "#2ECC71"        // 自然绿
        case .restaurant: return "#E74C3C"  // 美食红
        case .attraction: return "#9B59B6"  // 文化紫
        case .mall: return "#F39C12"        // 购物橙
        case .convenienceStore: return "#1ABC9C" // 便利青
        case .gym: return "#3498DB"         // 活力蓝
        case .other: return "#95A5A6"       // 温柔灰
        }
    }

    /// 收集品数量范围（旅行纪念品）
    var resourceRange: ClosedRange<Int> {
        switch self {
        case .cafe: return 20...40          // 咖啡豆、明信片等
        case .bookstore: return 30...50     // 书签、便签等
        case .park: return 40...70          // 落叶、照片等
        case .restaurant: return 25...45    // 美食照片、特色调料等
        case .attraction: return 50...80    // 纪念章、门票等
        case .mall: return 35...60          // 购物袋、小样等
        case .convenienceStore: return 15...30  // 零食、收据等
        case .gym: return 20...35           // 运动记录等
        case .other: return 15...25
        }
    }

    /// MapKit 搜索关键词（旅行风格）
    var searchKeywords: [String] {
        switch self {
        case .cafe: return ["咖啡", "咖啡店", "咖啡馆", "星巴克", "瑞幸", "Manner"]
        case .bookstore: return ["书店", "书城", "书屋", "西西弗", "新华书店", "诚品"]
        case .park: return ["公园", "广场", "花园", "绿地", "湿地公园"]
        case .restaurant: return ["餐厅", "美食", "特色菜", "网红店", "老字号"]
        case .attraction: return ["景点", "博物馆", "纪念馆", "古迹", "展览馆", "美术馆"]
        case .mall: return ["商场", "购物中心", "百货", "万象城", "万达"]
        case .convenienceStore: return ["便利店", "美宜佳", "7-11", "全家", "罗森"]
        case .gym: return ["健身房", "健身中心", "游泳馆", "运动中心", "瑜伽"]
        case .other: return ["商店", "店铺"]
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

// MARK: - MKMapItem 扩展

extension MKMapItem {
    /// 推断 POI 类型（旅行风格）
    func inferPOIType() -> POIType {
        let name = self.name?.lowercased() ?? ""
        let category = self.pointOfInterestCategory

        // 根据 MapKit 类别判断
        if let cat = category {
            switch cat {
            case .cafe:
                return .cafe
            case .park, .nationalPark:
                return .park
            case .restaurant, .bakery, .foodMarket:
                return .restaurant
            case .museum:
                return .attraction
            case .store:
                return .mall
            case .fitnessCenter:
                return .gym
            default:
                break
            }
        }

        // 根据名称判断（旅行风格）
        // 咖啡店
        if name.contains("咖啡") || name.contains("coffee") || name.contains("星巴克") ||
           name.contains("starbucks") || name.contains("瑞幸") || name.contains("manner") {
            return .cafe
        }
        // 书店
        if name.contains("书店") || name.contains("书城") || name.contains("书屋") ||
           name.contains("西西弗") || name.contains("新华书店") || name.contains("诚品") {
            return .bookstore
        }
        // 公园
        if name.contains("公园") || name.contains("广场") || name.contains("花园") ||
           name.contains("绿地") {
            return .park
        }
        // 景点
        if name.contains("博物馆") || name.contains("纪念馆") || name.contains("美术馆") ||
           name.contains("展览") || name.contains("古迹") || name.contains("遗址") {
            return .attraction
        }
        // 商场
        if name.contains("商场") || name.contains("购物") || name.contains("百货") ||
           name.contains("万象城") || name.contains("万达") || name.contains("天河城") {
            return .mall
        }
        // 便利店
        if name.contains("便利店") || name.contains("美宜佳") || name.contains("7-11") ||
           name.contains("全家") || name.contains("罗森") {
            return .convenienceStore
        }
        // 健身房
        if name.contains("健身") || name.contains("游泳") || name.contains("瑜伽") ||
           name.contains("运动") || name.contains("体育馆") {
            return .gym
        }
        // 餐厅
        if name.contains("餐") || name.contains("饭店") || name.contains("美食") ||
           name.contains("小吃") || name.contains("面馆") || name.contains("火锅") {
            return .restaurant
        }

        return .other
    }
}

// MARK: - POI 地图标注

class POIAnnotation: NSObject, MKAnnotation {
    let poi: POI

    var coordinate: CLLocationCoordinate2D {
        poi.coordinate
    }

    var title: String? {
        poi.name
    }

    var subtitle: String? {
        "\(poi.type.displayName) · 资源: \(poi.remainingItems)/\(poi.totalItems)"
    }

    init(poi: POI) {
        self.poi = poi
        super.init()
    }
}
