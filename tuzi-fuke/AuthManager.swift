//
//  AuthManager.swift
//  tuzi-fuke (地球新主复刻版)
//
//  用户认证管理器 - 支持可变体架构设计
//  Created by AI Assistant on 2025/11/21.
//

import Foundation
import SwiftUI
import Combine

// MARK: - 认证协议 (支持变体扩展)

/// 认证管理器协议 - 支持不同认证方式的变体实现
protocol AuthManagerProtocol: ObservableObject {
    var isAuthenticated: Bool { get }
    var currentUser: User? { get }
    var authState: AuthState { get }

    func signInAnonymously() async throws
    func signOut() async
    func refreshUserSession() async throws

}

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

/// 认证管理器 - 支持匿名登录和多种认证方式扩展
@MainActor
class AuthManager: AuthManagerProtocol {

    // MARK: - 单例
    static let shared = AuthManager()

    // MARK: - Published 属性
    @Published private(set) var authState: AuthState = .idle
    @Published private(set) var currentUser: User?

    // MARK: - 计算属性
    var isAuthenticated: Bool {
        authState.isAuthenticated
    }

    // MARK: - 私有属性
    private let userDefaults = UserDefaults.standard
    private let userStorageKey = "tuzi_fuke_current_user"

    // MARK: - 初始化
    private init() {
        print("🔐 [AuthManager] 初始化认证管理器")
        loadStoredUser()
    }

    // MARK: - 公共方法

    /// 匿名登录 (MVP版本主要认证方式)
    func signInAnonymously() async throws {
        print("🔐 [AuthManager] 开始匿名登录...")

        // 更新状态为认证中
        authState = .authenticating

        do {
            // 模拟网络请求延迟
            try await Task.sleep(nanoseconds: 1_000_000_000)

            // 生成匿名用户
            let anonymousUser = createAnonymousUser()

            // 保存用户数据
            try saveUserToStorage(anonymousUser)

            // 更新状态
            currentUser = anonymousUser
            authState = .authenticated(anonymousUser)

            print("✅ [AuthManager] 匿名登录成功: \(anonymousUser.username)")

        } catch {
            let authError = AuthError.anonymousSignInFailed
            authState = .failed(authError)
            print("❌ [AuthManager] 匿名登录失败: \(error.localizedDescription)")
            throw authError
        }
    }

    /// 登出
    func signOut() async {
        print("🔐 [AuthManager] 用户登出")

        // 清除存储的用户数据
        userDefaults.removeObject(forKey: userStorageKey)

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

        print("🔐 [AuthManager] 刷新用户会话: \(user.username)")

        // 这里可以添加会话验证逻辑
        // 对于匿名用户，暂时直接成功
        print("✅ [AuthManager] 会话刷新成功")
    }

    // MARK: - 预留扩展方法 (支持变体)

    /// 苹果登录 (预留接口)
    func signInWithApple() async throws {
        print("🔐 [AuthManager] Apple登录功能待实现")
        throw AuthError.unknownError("Apple登录功能尚未实现")
    }

    /// Google登录 (预留接口)
    func signInWithGoogle() async throws {
        print("🔐 [AuthManager] Google登录功能待实现")
        throw AuthError.unknownError("Google登录功能尚未实现")
    }

    // MARK: - 私有方法

    /// 创建匿名用户
    private func createAnonymousUser() -> User {
        let userId = UUID()
        let username = "玩家\(String(userId.uuidString.prefix(6)).uppercased())"
        let createdAt = Date()

        return User(
            id: userId,
            username: username,
            email: nil,
            avatarURL: nil,
            createdAt: createdAt,
            lastActiveAt: createdAt,
            isAnonymous: true,
            gameProfile: GameProfile(
                level: 1,
                experience: 0,
                territoriesCount: 0,
                buildingsCount: 0
            )
        )
    }

    /// 从本地存储加载用户
    private func loadStoredUser() {
        guard let userData = userDefaults.data(forKey: userStorageKey) else {
            print("📱 [AuthManager] 没有找到存储的用户数据")
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let user = try decoder.decode(User.self, from: userData)

            currentUser = user
            authState = .authenticated(user)
            print("✅ [AuthManager] 已加载存储用户: \(user.username)")

        } catch {
            print("❌ [AuthManager] 用户数据解码失败: \(error)")
            userDefaults.removeObject(forKey: userStorageKey)
            authState = .failed(.userDataCorrupted)
        }
    }

    /// 保存用户到本地存储
    private func saveUserToStorage(_ user: User) throws {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let userData = try encoder.encode(user)
            userDefaults.set(userData, forKey: userStorageKey)
            print("✅ [AuthManager] 用户数据已保存到本地")

        } catch {
            print("❌ [AuthManager] 用户数据保存失败: \(error)")
            throw AuthError.userDataCorrupted
        }
    }
}

// MARK: - 便利方法扩展

extension AuthManager {

    /// 获取当前用户ID
    var currentUserId: UUID? {
        return currentUser?.id
    }

    /// 检查是否为匿名用户
    var isAnonymousUser: Bool {
        return currentUser?.isAnonymous == true
    }

    /// 获取用户显示名称
    var userDisplayName: String {
        return currentUser?.username ?? "未登录"
    }

    /// 打印认证状态调试信息
    func printAuthStatus() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔐 认证管理器状态")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("认证状态: \(authState)")
        print("用户ID: \(currentUserId?.uuidString ?? "无")")
        print("用户名: \(userDisplayName)")
        print("匿名用户: \(isAnonymousUser)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}