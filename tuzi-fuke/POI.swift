//
//  POI.swift
//  tuzi-fuke
//
//  POI 数据模型 - 兴趣点
//  参考源项目 EarthLord
//

import Foundation
import CoreLocation
import MapKit

// MARK: - POI 类型

enum POIType: String, CaseIterable, Codable, Sendable {
    case hospital = "hospital"          // 医院
    case supermarket = "supermarket"    // 超市
    case factory = "factory"            // 工厂
    case restaurant = "restaurant"      // 餐厅
    case gasStation = "gas_station"     // 加油站
    case school = "school"              // 学校
    case park = "park"                  // 公园
    case other = "other"                // 其他

    /// 显示名称
    var displayName: String {
        switch self {
        case .hospital: return "医院"
        case .supermarket: return "超市"
        case .factory: return "工厂"
        case .restaurant: return "餐厅"
        case .gasStation: return "加油站"
        case .school: return "学校"
        case .park: return "公园"
        case .other: return "其他"
        }
    }

    /// 图标名称
    var iconName: String {
        switch self {
        case .hospital: return "cross.case.fill"
        case .supermarket: return "cart.fill"
        case .factory: return "building.2.fill"
        case .restaurant: return "fork.knife"
        case .gasStation: return "fuelpump.fill"
        case .school: return "graduationcap.fill"
        case .park: return "leaf.fill"
        case .other: return "mappin.circle.fill"
        }
    }

    /// 颜色
    var color: String {
        switch self {
        case .hospital: return "#FF4444"      // 红色
        case .supermarket: return "#44AA44"   // 绿色
        case .factory: return "#888888"       // 灰色
        case .restaurant: return "#FF8800"    // 橙色
        case .gasStation: return "#4444FF"    // 蓝色
        case .school: return "#AA44AA"        // 紫色
        case .park: return "#44AAAA"          // 青色
        case .other: return "#666666"         // 深灰
        }
    }

    /// 从字符串创建（处理下划线格式）
    init(from string: String) {
        switch string.lowercased() {
        case "hospital": self = .hospital
        case "supermarket": self = .supermarket
        case "factory": self = .factory
        case "restaurant": self = .restaurant
        case "gas_station", "gasstation": self = .gasStation
        case "school": self = .school
        case "park": self = .park
        default: self = .other
        }
    }
}

// MARK: - POI 数据模型

struct POI: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let type: POIType
    let description: String?
    let latitude: Double
    let longitude: Double
    let totalItems: Int
    let remainingItems: Int
    let createdAt: Date
    let updatedAt: Date

    /// 坐标
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// 位置
    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    /// 是否还有资源
    var hasResources: Bool {
        remainingItems > 0
    }

    /// 资源百分比
    var resourcePercentage: Double {
        guard totalItems > 0 else { return 0 }
        return Double(remainingItems) / Double(totalItems)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case description
        case latitude
        case longitude
        case totalItems = "total_items"
        case remainingItems = "remaining_items"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // ID 可能是字符串或 UUID
        if let idString = try? container.decode(String.self, forKey: .id) {
            self.id = UUID(uuidString: idString) ?? UUID()
        } else {
            self.id = try container.decode(UUID.self, forKey: .id)
        }

        self.name = try container.decode(String.self, forKey: .name)

        // type 是字符串
        let typeString = try container.decode(String.self, forKey: .type)
        self.type = POIType(from: typeString)

        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.latitude = try container.decode(Double.self, forKey: .latitude)
        self.longitude = try container.decode(Double.self, forKey: .longitude)
        self.totalItems = try container.decode(Int.self, forKey: .totalItems)
        self.remainingItems = try container.decode(Int.self, forKey: .remainingItems)

        // 日期解析
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let createdAtString = try? container.decode(String.self, forKey: .createdAt) {
            self.createdAt = dateFormatter.date(from: createdAtString) ?? Date()
        } else {
            self.createdAt = Date()
        }

        if let updatedAtString = try? container.decode(String.self, forKey: .updatedAt) {
            self.updatedAt = dateFormatter.date(from: updatedAtString) ?? Date()
        } else {
            self.updatedAt = Date()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type.rawValue, forKey: .type)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(totalItems, forKey: .totalItems)
        try container.encode(remainingItems, forKey: .remainingItems)

        let dateFormatter = ISO8601DateFormatter()
        try container.encode(dateFormatter.string(from: createdAt), forKey: .createdAt)
        try container.encode(dateFormatter.string(from: updatedAt), forKey: .updatedAt)
    }

    // MARK: - 便捷初始化

    init(id: UUID, name: String, type: POIType, description: String?, latitude: Double, longitude: Double, totalItems: Int, remainingItems: Int, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.type = type
        self.description = description
        self.latitude = latitude
        self.longitude = longitude
        self.totalItems = totalItems
        self.remainingItems = remainingItems
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - POI 发现记录

struct POIDiscovery: Identifiable, Codable, Sendable {
    let id: UUID
    let userId: UUID
    let poiId: UUID
    let discoveredAt: Date
    let itemsCollected: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case poiId = "poi_id"
        case discoveredAt = "discovered_at"
        case itemsCollected = "items_collected"
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
