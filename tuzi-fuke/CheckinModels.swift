//
//  CheckinModels.swift
//  tuzi-fuke (地球新主复刻版)
//
//  打卡功能数据模型
//  Created by AI Assistant on 2025/12/05.
//

import Foundation
import CoreLocation

// MARK: - 打卡照片模型

/// 打卡照片
struct CheckinPhoto: Identifiable, Codable, Sendable {
    let id: UUID
    let userId: UUID
    let buildingId: UUID?

    // 位置信息
    let locationName: String?
    let latitude: Double?
    let longitude: Double?

    // 环境信息
    let weather: String?
    let temperature: String?
    let timeOfDay: String?

    // 生成信息
    let mode: CheckinMode
    let prompt: String?

    // 图片URL
    let imageUrl: String
    let thumbnailUrl: String?

    // 状态
    let isPublic: Bool
    let isDeleted: Bool

    // 时间戳
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case buildingId = "building_id"
        case locationName = "location_name"
        case latitude
        case longitude
        case weather
        case temperature
        case timeOfDay = "time_of_day"
        case mode
        case prompt
        case imageUrl = "image_url"
        case thumbnailUrl = "thumbnail_url"
        case isPublic = "is_public"
        case isDeleted = "is_deleted"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// 获取坐标
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// 格式化创建时间
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: createdAt)
    }
}

// MARK: - 打卡模式

enum CheckinMode: String, Codable, CaseIterable, Sendable {
    case postcard = "postcard"   // 明信片模式（默认）
    case selfie = "selfie"       // 自拍模式（使用用户头像）
    case cartoon = "cartoon"     // 卡通模式
    case landscape = "landscape" // 风景模式

    var displayName: String {
        switch self {
        case .postcard: return "明信片"
        case .selfie: return "自拍"
        case .cartoon: return "卡通"
        case .landscape: return "风景"
        }
    }

    var icon: String {
        switch self {
        case .postcard: return "photo.artframe"
        case .selfie: return "person.fill"
        case .cartoon: return "paintbrush.fill"
        case .landscape: return "photo.fill"
        }
    }

    var description: String {
        switch self {
        case .postcard: return "根据真实地点生成精美明信片"
        case .selfie: return "使用你的照片生成AI自拍"
        case .cartoon: return "生成卡通风格的打卡图"
        case .landscape: return "生成末世风景照片"
        }
    }

    /// 是否需要用户头像
    var requiresAvatar: Bool {
        return self == .selfie
    }
}

// MARK: - 用户头像照片

struct UserAvatarPhoto: Identifiable, Codable, Sendable {
    let id: UUID
    let userId: UUID
    let photoUrl: String
    let thumbnailUrl: String?
    let displayOrder: Int
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case photoUrl = "photo_url"
        case thumbnailUrl = "thumbnail_url"
        case displayOrder = "display_order"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - 每日打卡限制

struct DailyCheckinLimit: Codable, Sendable {
    let id: UUID
    let userId: UUID
    let date: String  // YYYY-MM-DD
    var checkinCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case checkinCount = "checkin_count"
    }

    /// 最大每日打卡次数
    static let maxDailyCheckins = 3

    /// 是否还能打卡
    var canCheckin: Bool {
        return checkinCount < Self.maxDailyCheckins
    }

    /// 剩余打卡次数
    var remainingCheckins: Int {
        return max(0, Self.maxDailyCheckins - checkinCount)
    }
}

// MARK: - 打卡请求

struct CheckinRequest {
    let buildingId: UUID
    let mode: CheckinMode
    let avatarPhotoId: UUID?  // selfie模式需要

    // 位置信息
    let latitude: Double
    let longitude: Double
    let locationName: String?

    // 环境信息
    let weather: String?
    let temperature: String?
    let timeOfDay: String?
}

// MARK: - 打卡结果

struct CheckinResult {
    let success: Bool
    let photo: CheckinPhoto?
    let error: CheckinError?
    let message: String
}

enum CheckinError: Error, LocalizedError {
    case dailyLimitReached
    case noAvatarPhoto
    case buildingNotFound
    case aiGenerationFailed(String)
    case uploadFailed(String)
    case networkError(Error)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .dailyLimitReached:
            return "今日打卡次数已用完，明天再来吧！"
        case .noAvatarPhoto:
            return "自拍模式需要先上传头像照片"
        case .buildingNotFound:
            return "建筑不存在"
        case .aiGenerationFailed(let msg):
            return "AI生成失败: \(msg)"
        case .uploadFailed(let msg):
            return "上传失败: \(msg)"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .unknown(let msg):
            return msg
        }
    }
}

// MARK: - 天气信息

struct WeatherInfo {
    let condition: WeatherCondition
    let temperature: Double  // 摄氏度
    let humidity: Double     // 百分比
    let windSpeed: Double    // 米/秒
    let description: String

    /// 格式化温度
    var formattedTemperature: String {
        return "\(Int(temperature))°C"
    }

    /// 用于AI提示词的描述
    var aiDescription: String {
        return "\(condition.displayName)，气温\(formattedTemperature)，\(description)"
    }
}

enum WeatherCondition: String {
    case clear = "clear"
    case cloudy = "cloudy"
    case rain = "rain"
    case snow = "snow"
    case fog = "fog"
    case storm = "storm"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .clear: return "晴天"
        case .cloudy: return "多云"
        case .rain: return "雨天"
        case .snow: return "雪天"
        case .fog: return "雾天"
        case .storm: return "暴风雨"
        case .unknown: return "未知"
        }
    }

    var icon: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .cloudy: return "cloud.fill"
        case .rain: return "cloud.rain.fill"
        case .snow: return "cloud.snow.fill"
        case .fog: return "cloud.fog.fill"
        case .storm: return "cloud.bolt.rain.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    /// 末世风格的天气描述
    var apocalypticDescription: String {
        switch self {
        case .clear: return "阳光刺眼，辐射云层稀薄"
        case .cloudy: return "灰暗的云层笼罩大地"
        case .rain: return "酸雨淅沥，腐蚀着残垣断壁"
        case .snow: return "核冬天的灰烬覆盖一切"
        case .fog: return "浓雾弥漫，能见度极低"
        case .storm: return "末日风暴来袭"
        case .unknown: return "天气异常"
        }
    }
}

// MARK: - 时间段

enum TimeOfDay: String {
    case dawn = "dawn"       // 黎明 5-7
    case morning = "morning" // 早晨 7-12
    case noon = "noon"       // 中午 12-14
    case afternoon = "afternoon" // 下午 14-18
    case dusk = "dusk"       // 黄昏 18-20
    case night = "night"     // 夜晚 20-5

    var displayName: String {
        switch self {
        case .dawn: return "黎明"
        case .morning: return "早晨"
        case .noon: return "正午"
        case .afternoon: return "下午"
        case .dusk: return "黄昏"
        case .night: return "夜晚"
        }
    }

    /// 末世风格的时间描述
    var apocalypticDescription: String {
        switch self {
        case .dawn: return "微弱的曙光穿透灰暗的天际"
        case .morning: return "灰蒙蒙的早晨"
        case .noon: return "刺眼的阳光照射着废墟"
        case .afternoon: return "阴沉的下午"
        case .dusk: return "血色黄昏降临"
        case .night: return "漫长的黑夜笼罩末世"
        }
    }

    /// 根据当前时间获取时间段
    static func current() -> TimeOfDay {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<7: return .dawn
        case 7..<12: return .morning
        case 12..<14: return .noon
        case 14..<18: return .afternoon
        case 18..<20: return .dusk
        default: return .night
        }
    }
}

// MARK: - 插入用数据结构

struct CheckinPhotoInsert: Encodable, Sendable {
    let userId: UUID
    let buildingId: UUID?
    let locationName: String?
    let latitude: Double?
    let longitude: Double?
    let weather: String?
    let temperature: String?
    let timeOfDay: String?
    let mode: String
    let prompt: String?
    let imageUrl: String
    let thumbnailUrl: String?
    let isPublic: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case buildingId = "building_id"
        case locationName = "location_name"
        case latitude
        case longitude
        case weather
        case temperature
        case timeOfDay = "time_of_day"
        case mode
        case prompt
        case imageUrl = "image_url"
        case thumbnailUrl = "thumbnail_url"
        case isPublic = "is_public"
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encodeIfPresent(buildingId, forKey: .buildingId)
        try container.encodeIfPresent(locationName, forKey: .locationName)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(weather, forKey: .weather)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(timeOfDay, forKey: .timeOfDay)
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(prompt, forKey: .prompt)
        try container.encode(imageUrl, forKey: .imageUrl)
        try container.encodeIfPresent(thumbnailUrl, forKey: .thumbnailUrl)
        try container.encode(isPublic, forKey: .isPublic)
    }
}

struct UserAvatarPhotoInsert: Encodable, Sendable {
    let userId: UUID
    let photoUrl: String
    let thumbnailUrl: String?
    let displayOrder: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case photoUrl = "photo_url"
        case thumbnailUrl = "thumbnail_url"
        case displayOrder = "display_order"
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(photoUrl, forKey: .photoUrl)
        try container.encodeIfPresent(thumbnailUrl, forKey: .thumbnailUrl)
        try container.encode(displayOrder, forKey: .displayOrder)
    }
}

struct DailyCheckinLimitUpsert: Encodable, Sendable {
    let userId: String
    let date: String
    let checkinCount: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case date
        case checkinCount = "checkin_count"
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(date, forKey: .date)
        try container.encode(checkinCount, forKey: .checkinCount)
    }
}
