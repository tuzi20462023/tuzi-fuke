//
//  GeminiService.swift
//  tuzi-fuke (地球新主复刻版)
//
//  Gemini AI 图像生成服务
//  通过 Supabase Edge Function 调用
//  Created by AI Assistant on 2025/12/05.
//

import Foundation
import UIKit
import CoreLocation

// MARK: - Gemini API 服务

actor GeminiService {
    static let shared = GeminiService()

    // MARK: - 配置

    /// Supabase Edge Function URL
    private var edgeFunctionURL: URL {
        SupabaseConfig.supabaseURL.appendingPathComponent("functions/v1/generate-checkin-image")
    }

    /// Supabase Anon Key
    private var anonKey: String {
        SupabaseConfig.supabaseAnonKey
    }

    // MARK: - 生成打卡图片（明信片风格）

    /// 生成打卡图片
    /// - Parameters:
    ///   - location: 当前位置（经纬度）
    ///   - avatarImage: 用户头像图片（可选）
    /// - Returns: 生成的图片
    func generateCheckinImage(
        location: CLLocation,
        avatarImage: UIImage? = nil
    ) async throws -> UIImage {
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude

        print("🎨 [GeminiService] 生成明信片风格打卡图")
        print("📍 [GeminiService] 位置: \(latitude), \(longitude)")

        // 通过 Edge Function 生成图片
        return try await callEdgeFunction(
            latitude: latitude,
            longitude: longitude,
            avatarImage: avatarImage
        )
    }

    // MARK: - 调用 Edge Function

    private func callEdgeFunction(
        latitude: Double,
        longitude: Double,
        avatarImage: UIImage?
    ) async throws -> UIImage {
        print("🌐 [GeminiService] 调用 Edge Function: \(edgeFunctionURL)")

        var request = URLRequest(url: edgeFunctionURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 添加 Supabase 认证头
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")

        // 设置超时时间（图片生成可能需要较长时间）
        request.timeoutInterval = 120

        // 构建请求体
        var requestBody: [String: Any] = [
            "latitude": latitude,
            "longitude": longitude
        ]

        // 如果有头像，添加 base64 数据
        if let avatar = avatarImage,
           let imageData = avatar.jpegData(compressionQuality: 0.8) {
            let base64Image = imageData.base64EncodedString()
            requestBody["avatarBase64"] = base64Image
            print("📷 [GeminiService] 附加头像图片 (\(imageData.count) bytes)")
        }

        // 添加用户 ID（用于文件路径）
        if let userId = await SupabaseManager.shared.getCurrentUserId() {
            requestBody["userId"] = userId.uuidString.lowercased()
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        print("📤 [GeminiService] 发送请求...")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        print("📥 [GeminiService] 收到响应: HTTP \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ [GeminiService] Edge Function 错误: \(errorMessage)")
            throw GeminiError.apiError(httpResponse.statusCode, errorMessage)
        }

        // 解析响应
        return try await parseEdgeFunctionResponse(data)
    }

    // MARK: - 解析 Edge Function 响应

    private func parseEdgeFunctionResponse(_ data: Data) async throws -> UIImage {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("❌ [GeminiService] 无法解析 JSON 响应")
            throw GeminiError.parseError
        }

        // 检查是否成功
        guard let success = json["success"] as? Bool, success else {
            let errorMessage = json["error"] as? String ?? "未知错误"
            print("❌ [GeminiService] Edge Function 返回错误: \(errorMessage)")
            throw GeminiError.apiError(0, errorMessage)
        }

        // 获取图片 URL
        guard let imageURLString = json["image_url"] as? String,
              let imageURL = URL(string: imageURLString) else {
            print("❌ [GeminiService] 响应中没有图片 URL")
            throw GeminiError.noImageGenerated
        }

        print("✅ [GeminiService] 获取图片 URL: \(imageURLString)")

        // 下载图片
        let (imageData, _) = try await URLSession.shared.data(from: imageURL)

        guard let image = UIImage(data: imageData) else {
            print("❌ [GeminiService] 无法解析图片数据")
            throw GeminiError.invalidImage
        }

        print("✅ [GeminiService] 图片下载成功")
        return image
    }
}

// MARK: - 错误类型

enum GeminiError: Error, LocalizedError {
    case invalidResponse
    case invalidImage
    case apiError(Int, String)
    case parseError
    case noImageGenerated
    case quotaExceeded
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "无效的API响应"
        case .invalidImage:
            return "无效的图片数据"
        case .apiError(let code, let message):
            if code == 0 {
                return message
            }
            return "API错误 (\(code)): \(message)"
        case .parseError:
            return "解析响应失败"
        case .noImageGenerated:
            return "未能生成图片"
        case .quotaExceeded:
            return "API配额已用完"
        case .networkError(let message):
            return "网络错误: \(message)"
        }
    }
}

// MARK: - 预览支持

extension GeminiService {
    /// 生成测试图片（用于预览和测试）
    func generateTestImage() async throws -> UIImage {
        // 创建一个简单的测试图片
        let size = CGSize(width: 512, height: 512)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }

        // 背景渐变
        let context = UIGraphicsGetCurrentContext()!
        let colors = [
            UIColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1.0).cgColor,
            UIColor(red: 0.8, green: 0.4, blue: 0.3, alpha: 1.0).cgColor
        ]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors as CFArray,
                                  locations: [0, 1])!
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: 0),
                                   end: CGPoint(x: 0, y: size.height),
                                   options: [])

        // 添加文字
        let text = "明信片测试图片"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 32),
            .foregroundColor: UIColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)

        guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
            throw GeminiError.invalidImage
        }

        return image
    }
}
