//
//  CommunicationDevice.swift
//  tuzi-fuke
//
//  通讯设备系统 - 数据模型
//

import Foundation

// MARK: - 设备类型枚举

/// 通讯设备类型
enum DeviceType: String, Codable, Sendable, CaseIterable {
    case radio = "radio"                    // 收音机 - 只能接收
    case walkieTalkie = "walkie_talkie"     // 对讲机 - 3km
    case campRadio = "camp_radio"           // 营地电台 - 30km
    case cellphone = "cellphone"            // 手机通讯 - 100km+

    /// 设备中文名称
    var displayName: String {
        switch self {
        case .radio: return "小收音机"
        case .walkieTalkie: return "对讲机"
        case .campRadio: return "营地电台"
        case .cellphone: return "手机通讯"
        }
    }

    /// 设备图标
    var icon: String {
        switch self {
        case .radio: return "radio"
        case .walkieTalkie: return "antenna.radiowaves.left.and.right"
        case .campRadio: return "antenna.radiowaves.left.and.right.circle"
        case .cellphone: return "iphone.radiowaves.left.and.right"
        }
    }

    /// 是否可以发送消息
    var canSend: Bool {
        switch self {
        case .radio: return false  // 收音机只能接收
        case .walkieTalkie, .campRadio, .cellphone: return true
        }
    }

    /// 是否可以接收消息
    var canReceive: Bool {
        return true  // 所有设备都可以接收
    }

    /// 默认通讯范围（公里）
    var defaultRangeKm: Double {
        switch self {
        case .radio: return Double.infinity  // 无限范围接收
        case .walkieTalkie: return 3.0
        case .campRadio: return 30.0
        case .cellphone: return 100.0
        }
    }

    /// 是否可升级
    var canUpgrade: Bool {
        switch self {
        case .cellphone: return true
        default: return false
        }
    }

    /// 设备描述
    var description: String {
        switch self {
        case .radio:
            return "基础通讯设备，可以接收所有广播消息，但无法发送。"
        case .walkieTalkie:
            return "短距离双向通讯设备，通讯范围3公里。"
        case .campRadio:
            return "中距离通讯设备，通讯范围30公里，需要在营地使用。"
        case .cellphone:
            return "远距离通讯设备，通讯范围100公里以上，可升级扩展范围。"
        }
    }
}

// MARK: - 通讯设备结构体

/// 玩家通讯设备
struct CommunicationDevice: Identifiable, Codable, Sendable {
    let id: UUID
    let userId: UUID
    let deviceType: DeviceType
    let deviceName: String?
    var batteryLevel: Double
    var signalStrength: Double
    var rangeKm: Double
    var deviceLevel: Int
    var isActive: Bool
    let metadata: [String: String]?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case deviceType = "device_type"
        case deviceName = "device_name"
        case batteryLevel = "battery_level"
        case signalStrength = "signal_strength"
        case rangeKm = "range_km"
        case deviceLevel = "device_level"
        case isActive = "is_active"
        case metadata
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // MARK: - 计算属性

    /// 显示名称
    var displayName: String {
        return deviceName ?? deviceType.displayName
    }

    /// 是否可以发送消息
    var canSend: Bool {
        return deviceType.canSend && batteryLevel > 0 && isActive
    }

    /// 是否可以接收消息
    var canReceive: Bool {
        return deviceType.canReceive && batteryLevel > 0 && isActive
    }

    /// 实际通讯范围（考虑等级加成）
    var effectiveRangeKm: Double {
        if deviceType == .cellphone {
            // 手机通讯：100km × 等级
            return 100.0 * Double(deviceLevel)
        }
        return rangeKm > 0 ? rangeKm : deviceType.defaultRangeKm
    }

    /// 电池状态描述
    var batteryStatus: String {
        switch batteryLevel {
        case 80...100: return "充足"
        case 50..<80: return "良好"
        case 20..<50: return "偏低"
        case 1..<20: return "警告"
        default: return "耗尽"
        }
    }

    /// 信号状态描述
    var signalStatus: String {
        switch signalStrength {
        case 80...100: return "极强"
        case 60..<80: return "良好"
        case 40..<60: return "一般"
        case 20..<40: return "较弱"
        default: return "无信号"
        }
    }

    // MARK: - 方法

    /// 检查是否可以与目标距离通讯
    func canCommunicate(atDistanceKm distance: Double) -> Bool {
        guard canSend else { return false }
        return distance <= effectiveRangeKm
    }

    /// 计算与目标距离的信号衰减
    func signalAttenuation(atDistanceKm distance: Double) -> Double {
        let maxRange = effectiveRangeKm
        if maxRange == .infinity { return 1.0 }
        if distance >= maxRange { return 0.0 }
        // 线性衰减
        return 1.0 - (distance / maxRange)
    }
}

// MARK: - 设备创建便捷方法

extension CommunicationDevice {
    /// 创建默认收音机
    static func defaultRadio(for userId: UUID) -> CommunicationDevice {
        return CommunicationDevice(
            id: UUID(),
            userId: userId,
            deviceType: .radio,
            deviceName: "小收音机",
            batteryLevel: 100.0,
            signalStrength: 100.0,
            rangeKm: 0,
            deviceLevel: 1,
            isActive: true,
            metadata: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
