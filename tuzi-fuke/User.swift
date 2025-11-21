//
//  User.swift
//  tuzi-fuke (地球新主复刻版)
//
//  用户数据模型 - 支持可变体架构
//  Created by AI Assistant on 2025/11/21.
//

import Foundation

// MARK: - 用户数据模型

/// 用户信息模型 - 支持多种游戏变体的用户数据
struct User: Codable, Identifiable, Equatable {

    // MARK: - 基础属性
    let id: UUID
    let username: String
    let email: String?
    let avatarURL: String?

    // MARK: - 时间戳
    let createdAt: Date
    let lastActiveAt: Date

    // MARK: - 用户类型
    let isAnonymous: Bool

    // MARK: - 游戏资料
    let gameProfile: GameProfile

    // MARK: - CodingKeys (Supabase兼容)
    enum CodingKeys: String, CodingKey {
        case id = "id"
        case username = "username"
        case email = "email"
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
        case lastActiveAt = "last_active_at"
        case isAnonymous = "is_anonymous"
        case gameProfile = "game_profile"
    }
}

// MARK: - 游戏资料模型

/// 用户游戏资料 - 可根据不同变体扩展
struct GameProfile: Codable, Equatable {

    // MARK: - 基础游戏数据
    let level: Int
    let experience: Int

    // MARK: - 游戏统计
    let territoriesCount: Int
    let buildingsCount: Int

    // MARK: - 扩展数据 (支持变体自定义)
    var customData: [String: String]?

    // MARK: - 初始化
    init(
        level: Int,
        experience: Int,
        territoriesCount: Int,
        buildingsCount: Int,
        customData: [String: String]? = nil
    ) {
        self.level = level
        self.experience = experience
        self.territoriesCount = territoriesCount
        self.buildingsCount = buildingsCount
        self.customData = customData
    }

    // MARK: - CodingKeys
    enum CodingKeys: String, CodingKey {
        case level = "level"
        case experience = "experience"
        case territoriesCount = "territories_count"
        case buildingsCount = "buildings_count"
        case customData = "custom_data"
    }
}

// MARK: - User 扩展方法

extension User {

    /// 创建匿名用户的便利方法
    static func createAnonymous(username: String? = nil) -> User {
        let userId = UUID()
        let defaultUsername = username ?? "玩家\(String(userId.uuidString.prefix(6)).uppercased())"
        let now = Date()

        return User(
            id: userId,
            username: defaultUsername,
            email: nil,
            avatarURL: nil,
            createdAt: now,
            lastActiveAt: now,
            isAnonymous: true,
            gameProfile: GameProfile(
                level: 1,
                experience: 0,
                territoriesCount: 0,
                buildingsCount: 0
            )
        )
    }

    /// 更新最后活跃时间
    func updatedLastActiveTime() -> User {
        return User(
            id: self.id,
            username: self.username,
            email: self.email,
            avatarURL: self.avatarURL,
            createdAt: self.createdAt,
            lastActiveAt: Date(),
            isAnonymous: self.isAnonymous,
            gameProfile: self.gameProfile
        )
    }

    /// 更新游戏资料
    func updatedGameProfile(_ newProfile: GameProfile) -> User {
        return User(
            id: self.id,
            username: self.username,
            email: self.email,
            avatarURL: self.avatarURL,
            createdAt: self.createdAt,
            lastActiveAt: Date(),
            isAnonymous: self.isAnonymous,
            gameProfile: newProfile
        )
    }

    /// 获取显示名称
    var displayName: String {
        return username.isEmpty ? "用户\(String(id.uuidString.prefix(4)))" : username
    }

    /// 是否为新用户 (24小时内创建)
    var isNewUser: Bool {
        return Date().timeIntervalSince(createdAt) < 24 * 60 * 60
    }
}

// MARK: - GameProfile 扩展方法

extension GameProfile {

    /// 计算等级进度百分比 (0-100)
    var levelProgress: Double {
        let expForCurrentLevel = experienceForLevel(level)
        let expForNextLevel = experienceForLevel(level + 1)
        let currentLevelExp = experience - expForCurrentLevel

        guard expForNextLevel > expForCurrentLevel else { return 0 }

        return Double(currentLevelExp) / Double(expForNextLevel - expForCurrentLevel) * 100
    }

    /// 升级所需经验值
    var experienceNeededForNextLevel: Int {
        let expForNextLevel = experienceForLevel(level + 1)
        return max(0, expForNextLevel - experience)
    }

    /// 总游戏资产数量
    var totalAssets: Int {
        return territoriesCount + buildingsCount
    }

    /// 添加经验值并返回新的GameProfile
    func addingExperience(_ amount: Int) -> GameProfile {
        let newExperience = experience + amount
        let newLevel = calculateLevelFromExperience(newExperience)

        return GameProfile(
            level: newLevel,
            experience: newExperience,
            territoriesCount: territoriesCount,
            buildingsCount: buildingsCount,
            customData: customData
        )
    }

    /// 更新领土数量
    func updatingTerritories(_ count: Int) -> GameProfile {
        return GameProfile(
            level: level,
            experience: experience,
            territoriesCount: count,
            buildingsCount: buildingsCount,
            customData: customData
        )
    }

    /// 更新建筑数量
    func updatingBuildings(_ count: Int) -> GameProfile {
        return GameProfile(
            level: level,
            experience: experience,
            territoriesCount: territoriesCount,
            buildingsCount: count,
            customData: customData
        )
    }

    // MARK: - 私有计算方法

    /// 计算指定等级所需的经验值
    private func experienceForLevel(_ level: Int) -> Int {
        guard level > 1 else { return 0 }
        // 简单的经验值计算公式: level^2 * 100
        return (level - 1) * (level - 1) * 100
    }

    /// 根据经验值计算等级
    private func calculateLevelFromExperience(_ exp: Int) -> Int {
        var level = 1
        while experienceForLevel(level + 1) <= exp {
            level += 1
        }
        return level
    }
}

// MARK: - 调试支持

extension User: CustomStringConvertible {
    var description: String {
        return "User(id: \(id), username: '\(username)', level: \(gameProfile.level), anonymous: \(isAnonymous))"
    }
}

extension GameProfile: CustomStringConvertible {
    var description: String {
        return "GameProfile(level: \(level), exp: \(experience), territories: \(territoriesCount), buildings: \(buildingsCount))"
    }
}