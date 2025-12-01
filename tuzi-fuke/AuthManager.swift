//
//  AuthManager.swift
//  tuzi-fuke (地球新主复刻版)
//
//  用户认证管理器 - ✅ Supabase版本
//  Created by AI Assistant on 2025/11/21.
//

import Foundation
import SwiftUI
import Combine
import Supabase
import UIKit

// MARK: - 认证状态枚举

enum AuthState {
    case idle
    case authenticating
    case authenticated(User)
    case failed(AuthError)

    var isAuthenticated: Bool {
        if case .authenticated = self {
            return true
        }
        return false
    }
}

// MARK: - 认证错误类型

enum AuthError: Error, LocalizedError {
    case anonymousSignInFailed
    case userDataCorrupted
    case sessionExpired
    case networkUnavailable
    case unknownError(String)

    var errorDescription: String? {
        switch self {
        case .anonymousSignInFailed:
            return "匿名登录失败，请重试"
        case .userDataCorrupted:
            return "用户数据损坏，请重新登录"
        case .sessionExpired:
            return "登录会话已过期"
        case .networkUnavailable:
            return "网络连接不可用"
        case .unknownError(let message):
            return "未知错误: \(message)"
        }
    }
}

// MARK: - AuthManager 主实现

/// 认证管理器 - ✅ 使用Supabase认证
@MainActor
class AuthManager: ObservableObject {

    // MARK: - 单例
    static let shared = AuthManager()

    // MARK: - Published 属性
    @Published private(set) var authState: AuthState = .idle
    @Published private(set) var currentUser: User?

    // MARK: - 计算属性
    var isAuthenticated: Bool {
        authState.isAuthenticated
    }

    /// 当前用户ID
    var currentUserId: UUID? {
        return currentUser?.id
    }

    /// 获取用户显示名称
    var userDisplayName: String {
        return currentUser?.username ?? "匿名用户"
    }

    // MARK: - 私有属性
    private let supabase: SupabaseClient

    // MARK: - 初始化
    private init() {
        print("🔐 [AuthManager] 初始化认证管理器（✅ Supabase主模块版本）")
        self.supabase = SupabaseManager.shared.client

        Task {
            await checkCurrentSession()
        }
    }

    // MARK: - 会话管理

    /// 检查当前会话状态
    func checkCurrentSession() async {
        do {
            let session = try await supabase.auth.session
            let supabaseUser = session.user

            // 转换为我们的User模型
            let ourUser = User(
                id: supabaseUser.id,
                username: "匿名用户\(supabaseUser.id.uuidString.prefix(6).uppercased())",
                email: supabaseUser.email,
                avatarURL: nil,
                createdAt: Date(),
                lastActiveAt: Date(),
                isAnonymous: true, // 2.5.1版本中手动设置
                gameProfile: GameProfile(
                    level: 1,
                    experience: 0,
                    territoriesCount: 0,
                    buildingsCount: 0
                )
            )

            self.currentUser = ourUser
            self.authState = .authenticated(ourUser)
            print("✅ [AuthManager] 已检测到现有Supabase会话，用户ID: \(supabaseUser.id)")
        } catch {
            // 没有活跃会话
            self.authState = .idle
            self.currentUser = nil
            print("📱 [AuthManager] 没有现有Supabase会话")
        }
    }

    // MARK: - 公共方法

    /// 测试账户登录 (使用真实email+password)
    func signInWithTestAccount() async throws {
        print("🔐 [AuthManager] 开始 ✅ Supabase真实账户登录...")

        // 更新状态为认证中
        authState = .authenticating

        do {
            // 使用预设的测试账户
            let testEmail = "test@tuzigame.com"
            let testPassword = "TuziGame2024!"

            print("🔄 [AuthManager] 使用测试账户登录: \(testEmail)")

            // 真正的email+password登录
            let session = try await supabase.auth.signIn(
                email: testEmail,
                password: testPassword
            )
            let supabaseUser = session.user

            // 转换为我们的User模型
            let ourUser = User(
                id: supabaseUser.id,
                username: "测试用户\(supabaseUser.id.uuidString.prefix(6).uppercased())",
                email: supabaseUser.email,
                avatarURL: nil,
                createdAt: Date(),
                lastActiveAt: Date(),
                isAnonymous: false, // 这是真实账户
                gameProfile: GameProfile(
                    level: 1,
                    experience: 0,
                    territoriesCount: 0,
                    buildingsCount: 0
                )
            )

            // 更新状态
            currentUser = ourUser
            authState = .authenticated(ourUser)

            print("🎉 [AuthManager] ✅ Supabase真实账户登录成功！")
            print("🆔 [AuthManager] 真实用户ID: \(supabaseUser.id)")
            print("📧 [AuthManager] 登录邮箱: \(testEmail)")
            print("🌐 [AuthManager] 连接到项目: https://urslgwtgnjcxlzzcwhfw.supabase.co")
            print("✅ [AuthManager] 真实账户状态: ✅ (email+password登录)")
            print("🎯 [AuthManager] Day2阶段1完成 - 真实Supabase认证已启用！")

        } catch {
            let authError = AuthError.anonymousSignInFailed
            authState = .failed(authError)
            print("❌ [AuthManager] Supabase账户登录失败: \(error.localizedDescription)")
            throw authError
        }
    }

    /// 自定义邮箱密码登录
    func signIn(email: String, password: String) async throws {
        print("🔐 [AuthManager] 开始邮箱密码登录: \(email)")

        authState = .authenticating

        do {
            let session = try await supabase.auth.signIn(
                email: email,
                password: password
            )
            let supabaseUser = session.user

            let ourUser = User(
                id: supabaseUser.id,
                username: supabaseUser.email?.components(separatedBy: "@").first?.capitalized ?? "用户",
                email: supabaseUser.email,
                avatarURL: nil,
                createdAt: Date(),
                lastActiveAt: Date(),
                isAnonymous: false,
                gameProfile: GameProfile(
                    level: 1,
                    experience: 0,
                    territoriesCount: 0,
                    buildingsCount: 0
                )
            )

            currentUser = ourUser
            authState = .authenticated(ourUser)

            print("🎉 [AuthManager] ✅ 自定义账户登录成功！")
            print("🆔 [AuthManager] 用户ID: \(supabaseUser.id)")
            print("📧 [AuthManager] 邮箱: \(email)")

        } catch {
            let authError = AuthError.anonymousSignInFailed
            authState = .failed(authError)
            print("❌ [AuthManager] 邮箱密码登录失败: \(error.localizedDescription)")
            throw authError
        }
    }

    /// 登出
    func signOut() async {
        print("🔐 [AuthManager] Supabase用户登出")

        do {
            try await supabase.auth.signOut()
            print("✅ [AuthManager] Supabase登出成功")
        } catch {
            print("❌ [AuthManager] Supabase登出失败: \(error.localizedDescription)")
        }

        // 重置状态
        currentUser = nil
        authState = .idle

        print("✅ [AuthManager] 登出完成")
    }

    /// 刷新用户会话
    func refreshUserSession() async throws {
        guard let user = currentUser else {
            throw AuthError.sessionExpired
        }

        print("🔐 [AuthManager] 刷新Supabase用户会话: \(user.username)")

        do {
            _ = try await supabase.auth.session
            print("✅ [AuthManager] Supabase会话刷新成功")
        } catch {
            print("❌ [AuthManager] Supabase会话刷新失败: \(error)")
            throw AuthError.sessionExpired
        }
    }

    /// 打印认证状态调试信息
    func printAuthStatus() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔐 认证管理器状态")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("认证状态: \(authState)")
        print("用户ID: \(currentUserId?.uuidString ?? "无")")
        print("用户名: \(userDisplayName)")
        print("账户类型: \(currentUser?.isAnonymous == true ? "匿名" : "真实")")
        if let email = currentUser?.email {
            print("用户邮箱: \(email)")
        }
        print("版本: ✅ Supabase真实版本已启用！")
        print("项目: https://urslgwtgnjcxlzzcwhfw.supabase.co")
        print("状态: 🎯 Day2阶段1完成 - 准备进入阶段2")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}