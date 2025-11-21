//
//  DataManager.swift
//  tuzi-fuke (地球新主复刻版)
//
//  Supabase数据管理器 - 支持可变体架构设计
//  Created by AI Assistant on 2025/11/21.
//

import Foundation
import SwiftUI
import Combine

// MARK: - 数据管理协议 (支持变体扩展)

/// 数据管理器协议 - 支持不同游戏的数据需求
protocol DataManagerProtocol: ObservableObject {
    var isConnected: Bool { get }
    var connectionState: DataConnectionState { get }

    func initialize() async throws
    func testConnection() async throws
    func syncData() async throws
}

// MARK: - 数据连接状态

enum DataConnectionState {
    case disconnected
    case connecting
    case connected
    case failed(DataError)
    case syncing

    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}

// MARK: - 数据错误类型

enum DataError: Error, LocalizedError {
    case configurationMissing
    case connectionFailed
    case authenticationRequired
    case networkUnavailable
    case syncFailed(String)
    case unknownError(String)

    var errorDescription: String? {
        switch self {
        case .configurationMissing:
            return "数据库配置缺失，请检查SupabaseConfig"
        case .connectionFailed:
            return "数据库连接失败，请检查网络连接"
        case .authenticationRequired:
            return "需要用户认证才能访问数据"
        case .networkUnavailable:
            return "网络连接不可用"
        case .syncFailed(let reason):
            return "数据同步失败: \(reason)"
        case .unknownError(let message):
            return "未知数据错误: \(message)"
        }
    }
}

// MARK: - Repository 基础协议

/// 通用仓储协议 - 支持不同数据模型
protocol RepositoryProtocol {
    associatedtype Entity: Codable

    func create(_ entity: Entity) async throws -> Entity
    func findById(_ id: UUID) async throws -> Entity?
    func findAll() async throws -> [Entity]
    func update(_ entity: Entity) async throws -> Entity
    func delete(_ id: UUID) async throws
}

// MARK: - DataManager 主实现

/// 数据管理器 - 支持多种游戏的数据存储需求
@MainActor
class DataManager: DataManagerProtocol {

    // MARK: - 单例
    static let shared = DataManager()

    // MARK: - Published 属性
    @Published private(set) var connectionState: DataConnectionState = .disconnected
    @Published private(set) var lastSyncTime: Date?
    @Published private(set) var pendingOperations: Int = 0

    // MARK: - 计算属性
    var isConnected: Bool {
        connectionState.isConnected
    }

    // MARK: - 私有属性
    private var isInitialized = false

    // MARK: - Repository 实例 (支持变体扩展)
    private var repositories: [String: Any] = [:]

    // MARK: - 初始化
    private init() {
        print("💾 [DataManager] 初始化数据管理器")
    }

    // MARK: - 公共方法

    /// 初始化数据管理器
    func initialize() async throws {
        guard !isInitialized else {
            print("💾 [DataManager] 已经初始化，跳过")
            return
        }

        print("💾 [DataManager] 开始初始化...")
        connectionState = .connecting

        do {
            // 验证配置
            guard SupabaseConfig.validateConfig() else {
                throw DataError.configurationMissing
            }

            // 模拟连接过程
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1秒

            // 初始化仓储
            setupRepositories()

            // 标记为已初始化
            isInitialized = true
            connectionState = .connected
            lastSyncTime = Date()

            print("✅ [DataManager] 初始化完成")

        } catch {
            connectionState = .failed(.connectionFailed)
            print("❌ [DataManager] 初始化失败: \(error.localizedDescription)")
            throw error
        }
    }

    /// 测试连接
    func testConnection() async throws {
        print("💾 [DataManager] 测试数据库连接...")

        guard SupabaseConfig.validateConfig() else {
            throw DataError.configurationMissing
        }

        // 模拟连接测试
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒

        print("✅ [DataManager] 连接测试成功")
    }

    /// 同步数据
    func syncData() async throws {
        guard isConnected else {
            throw DataError.connectionFailed
        }

        print("💾 [DataManager] 开始数据同步...")
        connectionState = .syncing
        pendingOperations += 1

        defer {
            pendingOperations = max(0, pendingOperations - 1)
            if pendingOperations == 0 {
                connectionState = .connected
            }
        }

        do {
            // 模拟数据同步过程
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2秒

            lastSyncTime = Date()
            print("✅ [DataManager] 数据同步完成")

        } catch {
            connectionState = .failed(.syncFailed(error.localizedDescription))
            print("❌ [DataManager] 数据同步失败: \(error.localizedDescription)")
            throw DataError.syncFailed(error.localizedDescription)
        }
    }

    // MARK: - Repository 管理方法

    /// 获取指定类型的仓储实例
    func getRepository<T: RepositoryProtocol>(_ type: T.Type) -> T? {
        let key = String(describing: type)
        return repositories[key] as? T
    }

    /// 注册仓储实例 (支持变体自定义)
    func registerRepository<T: RepositoryProtocol>(_ repository: T) {
        let key = String(describing: T.self)
        repositories[key] = repository
        print("💾 [DataManager] 注册仓储: \(key)")
    }

    // MARK: - 便利方法

    /// 执行数据库操作的通用方法
    func performOperation<T>(
        _ operation: @escaping () async throws -> T,
        retryCount: Int = 3
    ) async throws -> T {
        guard isConnected else {
            throw DataError.connectionFailed
        }

        pendingOperations += 1
        defer { pendingOperations = max(0, pendingOperations - 1) }

        var lastError: Error?

        for attempt in 1...retryCount {
            do {
                let result = try await operation()
                return result

            } catch {
                lastError = error
                print("⚠️ [DataManager] 操作失败 (尝试 \(attempt)/\(retryCount)): \(error.localizedDescription)")

                if attempt < retryCount {
                    // 等待后重试
                    try await Task.sleep(nanoseconds: UInt64(attempt * 500_000_000)) // 0.5s, 1s, 1.5s
                }
            }
        }

        throw lastError ?? DataError.unknownError("操作失败")
    }

    /// 批量操作
    func performBatchOperation<T>(
        _ operations: [() async throws -> T]
    ) async throws -> [T] {
        guard isConnected else {
            throw DataError.connectionFailed
        }

        var results: [T] = []
        results.reserveCapacity(operations.count)

        for operation in operations {
            let result = try await operation()
            results.append(result)
        }

        return results
    }

    /// 打印数据管理器状态
    func printDataStatus() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("💾 数据管理器状态")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("连接状态: \(connectionState)")
        print("初始化状态: \(isInitialized ? "✅" : "❌")")
        print("配置状态: \(SupabaseConfig.validateConfig() ? "✅" : "❌")")
        print("最后同步: \(lastSyncTime?.formatted() ?? "无")")
        print("待处理操作: \(pendingOperations)")
        print("已注册仓储: \(repositories.keys.joined(separator: ", "))")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    // MARK: - 私有方法

    /// 设置基础仓储
    private func setupRepositories() {
        // 这里可以注册默认的仓储实例
        // 具体的仓储实现会在创建数据模型时添加

        print("💾 [DataManager] 设置基础仓储...")

        // 示例: registerRepository(UserRepository())
        // 示例: registerRepository(TerritoryRepository())
        // 示例: registerRepository(BuildingRepository())

        print("💾 [DataManager] 基础仓储设置完成")
    }
}

// MARK: - 基础仓储实现

/// 通用仓储基类 - 提供基础的CRUD操作
class BaseRepository<Entity: Codable & Identifiable>: RepositoryProtocol where Entity.ID == UUID {

    let tableName: String

    init(tableName: String) {
        self.tableName = tableName
        print("💾 [BaseRepository] 初始化 \(tableName) 仓储")
    }

    // MARK: - CRUD 操作 (模拟实现)

    func create(_ entity: Entity) async throws -> Entity {
        print("💾 [BaseRepository] 创建 \(tableName) 记录: \(entity.id)")

        // 模拟数据库插入操作
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2秒

        // 这里应该是实际的Supabase插入操作
        // 暂时返回原实体 (假设插入成功)

        print("✅ [BaseRepository] \(tableName) 记录创建成功")
        return entity
    }

    func findById(_ id: UUID) async throws -> Entity? {
        print("💾 [BaseRepository] 查找 \(tableName) 记录: \(id)")

        // 模拟数据库查询操作
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒

        // 这里应该是实际的Supabase查询操作
        // 暂时返回nil (假设未找到)

        print("⚠️ [BaseRepository] \(tableName) 记录未找到")
        return nil
    }

    func findAll() async throws -> [Entity] {
        print("💾 [BaseRepository] 查找所有 \(tableName) 记录")

        // 模拟数据库查询操作
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3秒

        // 这里应该是实际的Supabase查询操作
        // 暂时返回空数组

        print("✅ [BaseRepository] \(tableName) 查询完成 (0 条记录)")
        return []
    }

    func update(_ entity: Entity) async throws -> Entity {
        print("💾 [BaseRepository] 更新 \(tableName) 记录: \(entity.id)")

        // 模拟数据库更新操作
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2秒

        // 这里应该是实际的Supabase更新操作
        // 暂时返回原实体 (假设更新成功)

        print("✅ [BaseRepository] \(tableName) 记录更新成功")
        return entity
    }

    func delete(_ id: UUID) async throws {
        print("💾 [BaseRepository] 删除 \(tableName) 记录: \(id)")

        // 模拟数据库删除操作
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2秒

        // 这里应该是实际的Supabase删除操作

        print("✅ [BaseRepository] \(tableName) 记录删除成功")
    }
}

// MARK: - 扩展支持

extension DataConnectionState: CustomStringConvertible {
    var description: String {
        switch self {
        case .disconnected: return "未连接"
        case .connecting: return "连接中"
        case .connected: return "已连接"
        case .failed(let error): return "连接失败: \(error.localizedDescription)"
        case .syncing: return "同步中"
        }
    }
}