//
//  DeviceManager.swift
//  tuzi-fuke
//
//  通讯设备管理器 - 管理玩家的通讯设备
//

import Foundation
import Combine
import Supabase

// MARK: - DeviceManager

@MainActor
class DeviceManager: ObservableObject {

    // MARK: - 单例
    static let shared = DeviceManager()

    // MARK: - Published 属性
    @Published var devices: [CommunicationDevice] = []
    @Published var activeDevice: CommunicationDevice?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - 私有属性
    private let supabase = SupabaseManager.shared.client

    // MARK: - 初始化
    private init() {
        print("📻 [DeviceManager] 初始化设备管理器")
    }

    // MARK: - 公开方法

    /// 加载当前用户的所有设备
    func loadDevices() async {
        guard let userId = await SupabaseManager.shared.getCurrentUserId() else {
            print("❌ [DeviceManager] 未登录，无法加载设备")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let loadedDevices = try await fetchDevicesViaREST(userId: userId)
            devices = loadedDevices

            // 设置默认激活设备（优先选择收音机以外的设备）
            if activeDevice == nil {
                activeDevice = devices.first(where: { $0.deviceType != .radio && $0.isActive })
                    ?? devices.first(where: { $0.isActive })
            }

            print("✅ [DeviceManager] 加载了 \(devices.count) 个设备")
            if let active = activeDevice {
                print("📻 [DeviceManager] 当前激活设备: \(active.displayName)")
            }
        } catch {
            errorMessage = "加载设备失败: \(error.localizedDescription)"
            print("❌ [DeviceManager] 加载设备失败: \(error)")
        }

        isLoading = false
    }

    /// 切换激活设备
    func setActiveDevice(_ device: CommunicationDevice) {
        activeDevice = device
        print("📻 [DeviceManager] 切换激活设备: \(device.displayName)")
    }

    /// 获取当前设备是否可以发送消息
    var canSendMessage: Bool {
        return activeDevice?.canSend ?? false
    }

    /// 获取当前设备的通讯范围
    var currentRangeKm: Double {
        return activeDevice?.effectiveRangeKm ?? 0
    }

    /// 获取不能发送的原因
    var cannotSendReason: String? {
        guard let device = activeDevice else {
            return "没有通讯设备"
        }

        if !device.isActive {
            return "设备未激活"
        }

        if device.batteryLevel <= 0 {
            return "设备电量耗尽"
        }

        if !device.deviceType.canSend {
            return "\(device.displayName)只能接收消息，无法发送"
        }

        return nil
    }

    /// 刷新设备列表
    func refresh() async {
        await loadDevices()
    }

    // MARK: - 私有方法

    /// 通过 REST API 获取设备
    private func fetchDevicesViaREST(userId: UUID) async throws -> [CommunicationDevice] {
        let url = SupabaseConfig.supabaseURL
            .appendingPathComponent("rest/v1/player_devices")
            .appending(queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "user_id", value: "eq.\(userId.uuidString)"),
                URLQueryItem(name: "order", value: "created_at.asc")
            ])

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")

        // 尝试使用用户 token
        if let accessToken = try? await supabase.auth.session.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(SupabaseConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw DeviceError.fetchFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            return Self.parseDate(dateString) ?? Date()
        }

        return try decoder.decode([CommunicationDevice].self, from: data)
    }

    /// 解析日期
    nonisolated private static func parseDate(_ dateString: String) -> Date? {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ss"
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: dateString)
    }

    // MARK: - 调试方法

    func printStatus() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📻 DeviceManager 状态")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("设备数量: \(devices.count)")
        print("激活设备: \(activeDevice?.displayName ?? "无")")
        print("可以发送: \(canSendMessage ? "✅" : "❌")")
        if let reason = cannotSendReason {
            print("不能发送原因: \(reason)")
        }
        print("通讯范围: \(currentRangeKm == .infinity ? "无限" : "\(currentRangeKm)km")")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}

// MARK: - 错误类型

enum DeviceError: LocalizedError {
    case fetchFailed
    case deviceNotFound
    case cannotSend(String)

    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "获取设备列表失败"
        case .deviceNotFound:
            return "设备不存在"
        case .cannotSend(let reason):
            return reason
        }
    }
}
