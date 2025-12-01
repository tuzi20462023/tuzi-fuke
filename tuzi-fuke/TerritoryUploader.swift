//
//  TerritoryUploader.swift
//  tuzi-fuke
//
//  独立的领地上传模块 - 解决 Swift 6 并发问题
//  使用 REST API 直接上传，绕过 Supabase SDK 的 Sendable 限制
//

import Foundation

// MARK: - 路径点数据

/// 路径点结构（Sendable）
struct PathPointData: Encodable, Sendable {
    let lat: Double
    let lon: Double
    let timestamp: Double?
}

// MARK: - 上传数据结构

/// 上传到 Supabase 的领地数据结构
struct TerritoryUploadData: Encodable, Sendable {
    let id: String
    let user_id: String
    let type: String
    let center_latitude: Double
    let center_longitude: Double
    let radius: Double
    let is_active: Bool
    let name: String?
    let path: [PathPointData]?
    let polygon: String?
    let bbox_min_lat: Double?
    let bbox_max_lat: Double?
    let bbox_min_lon: Double?
    let bbox_max_lon: Double?
    let area: Double?
    let perimeter: Double?
    let point_count: Int?
    let started_at: String?
    let completed_at: String?
}

// MARK: - 上传错误

enum TerritoryRESTUploadError: Error, LocalizedError {
    case encodingFailed
    case networkError(Error)
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "数据编码失败"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "服务器错误 (\(code)): \(message)"
        }
    }
}

// MARK: - 上传器

/// 领地上传器 - 使用原生 URLSession 直接调用 REST API
/// 绕过 Supabase SDK 的 Sendable 限制
actor TerritoryUploader {

    /// 上传领地数据到 Supabase REST API
    func upload(_ data: sending TerritoryUploadData, supabaseUrl: String, anonKey: String, accessToken: String?) async throws {
        // 构建 URL
        let urlString = "\(supabaseUrl)/rest/v1/territories"
        guard let url = URL(string: urlString) else {
            throw TerritoryRESTUploadError.encodingFailed
        }

        // 编码数据
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(data)

        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        // 如果有访问令牌，添加 Authorization header
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        }

        // 发送请求
        let (responseData, response) = try await URLSession.shared.data(for: request)

        // 检查响应
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TerritoryRESTUploadError.networkError(NSError(domain: "Invalid response", code: -1))
        }

        // 成功状态码：200, 201, 204
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw TerritoryRESTUploadError.serverError(httpResponse.statusCode, errorMessage)
        }
    }
}

// MARK: - 全局单例

/// 全局上传器实例
let territoryUploader = TerritoryUploader()
