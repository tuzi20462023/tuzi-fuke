//
//  ExplorationUploader.swift
//  tuzi-fuke
//
//  探索会话上传模块 - 使用 REST API 直接上传
//  解决 Swift 6 并发问题，绕过 Supabase SDK 的 Sendable 限制
//

import Foundation

// MARK: - 路线点数据

struct RoutePointData: Encodable, Sendable {
    let lat: Double
    let lon: Double
    let timestamp: Double
}

// MARK: - 创建数据结构

struct ExplorationSessionCreateData: Encodable, Sendable {
    let id: String
    let user_id: String
    let status: String
    let started_at: String
    let start_latitude: Double?
    let start_longitude: Double?
    let total_distance: Double
    let total_area: Double
    let grid_count: Int
    let calories_burned: Double
}

// MARK: - 更新数据结构

struct ExplorationSessionUpdateData: Encodable, Sendable {
    let status: String
    let ended_at: String?
    let duration_seconds: Int?
    let end_latitude: Double?
    let end_longitude: Double?
    let total_distance: Double
    let total_area: Double
    let grid_count: Int
    let calories_burned: Double
    let route_points: [RoutePointData]?
    let updated_at: String
}

// MARK: - 上传错误

enum ExplorationUploadError: Error, LocalizedError {
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

actor ExplorationUploader {

    /// 创建探索会话
    func create(_ data: sending ExplorationSessionCreateData, supabaseUrl: String, anonKey: String, accessToken: String?) async throws {
        let urlString = "\(supabaseUrl)/rest/v1/exploration_sessions"
        guard let url = URL(string: urlString) else {
            throw ExplorationUploadError.encodingFailed
        }

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(data)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        }

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExplorationUploadError.networkError(NSError(domain: "Invalid response", code: -1))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw ExplorationUploadError.serverError(httpResponse.statusCode, errorMessage)
        }
    }

    /// 更新探索会话
    func update(sessionId: String, data: sending ExplorationSessionUpdateData, supabaseUrl: String, anonKey: String, accessToken: String?) async throws {
        let urlString = "\(supabaseUrl)/rest/v1/exploration_sessions?id=eq.\(sessionId)"
        guard let url = URL(string: urlString) else {
            throw ExplorationUploadError.encodingFailed
        }

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(data)

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        }

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExplorationUploadError.networkError(NSError(domain: "Invalid response", code: -1))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: responseData, encoding: .utf8) ?? "Unknown error"
            throw ExplorationUploadError.serverError(httpResponse.statusCode, errorMessage)
        }
    }
}

// MARK: - 全局单例

let explorationUploader = ExplorationUploader()
