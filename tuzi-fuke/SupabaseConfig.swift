//
//  SupabaseConfig.swift
//  tuzi-fuke
//
//  Created by AI Assistant on 2025/11/21.
//  地球新主复刻版 - Supabase配置文件 (临时版本)
//

import Foundation
import Supabase

/// Supabase 配置管理 (临时版本 - 不依赖Supabase SDK)
struct SupabaseConfig {

    // MARK: - Supabase 连接配置

    /// Supabase 项目URL
    static let supabaseURL = URL(string: "https://urslgwtgnjcxlzzcwhfw.supabase.co")!

    /// Supabase 匿名密钥 (anon key)
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVyc2xnd3RnbmpjeGx6emN3aGZ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM3MjIxMTEsImV4cCI6MjA3OTI5ODExMX0.PO7zwp68QYP4NCg1L1IasRA8GR9b48ZblzV1lODx9Bg"

    /// 配置状态
    static var isConfigured: Bool {
        return validateConfig()
    }
    // MARK: - 配置验证

    /// 验证配置是否有效
    static func validateConfig() -> Bool {
        // 检查URL是否有效
        let urlString = supabaseURL.absoluteString
        guard !urlString.contains("your-project") else {
            print("❌ [SupabaseConfig] 请配置正确的Supabase URL")
            return false
        }

        // 检查密钥是否有效
        guard !supabaseAnonKey.contains("your-anon-key") else {
            print("❌ [SupabaseConfig] 请配置正确的Supabase anon key")
            return false
        }

        print("✅ [SupabaseConfig] 配置验证通过")
        return true
    }

    // MARK: - 调试信息

    /// 打印配置信息（用于调试）
    static func printDebugInfo() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔧 Supabase 配置信息 (临时版本)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("URL: \(supabaseURL.absoluteString)")
        print("Key: \(String(supabaseAnonKey.prefix(20)))...")
        print("状态: \(validateConfig() ? "✅ 有效" : "❌ 需要配置")")
        print("SDK状态: ✅ Supabase SDK v2.5.1已集成")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}

/// Supabase客户端单例管理器
class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.supabaseURL,
            supabaseKey: SupabaseConfig.supabaseAnonKey
        )
        print("✅ [SupabaseManager] Supabase客户端初始化完成")
        print("🌐 [SupabaseManager] 连接到: \(SupabaseConfig.supabaseURL.absoluteString)")
    }

    /// 获取当前用户ID
    func getCurrentUserId() async -> UUID? {
        do {
            let session = try await client.auth.session
            return session.user.id
        } catch {
            return nil
        }
    }
}

// MARK: - 使用说明
/*
 ## 🔧 Supabase 配置步骤

 1. 登录 Supabase 控制台: https://supabase.com/dashboard
 2. 创建新项目或选择现有项目
 3. 在项目设置中找到:
    - Project URL (类似: https://xxxxx.supabase.co)
    - anon/public key (以 eyJ 开头的长字符串)
 4. 替换上方的 supabaseURL 和 supabaseAnonKey
 5. 运行 SupabaseConfig.validateConfig() 验证配置

 ## 📱 在SwiftUI中使用

 ```swift
 // 在App启动时初始化
 let supabase = SupabaseConfig.shared

 // 验证配置
 if !SupabaseConfig.validateConfig() {
     // 处理配置错误
 }
 ```
 */