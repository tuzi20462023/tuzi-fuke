//
//  InventoryManager.swift
//  tuzi-fuke (地球新主复刻版)
//
//  背包管理器 - 管理玩家物品的增删改查
//  Created by AI Assistant on 2025/12/06.
//

import Foundation
import Combine
import Supabase

// MARK: - 数据传输结构体

struct InventoryInsertData: Encodable, Sendable {
    let user_id: String
    let item_id: String
    let quantity: Int
    let icon: String?

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(user_id, forKey: .user_id)
        try container.encode(item_id, forKey: .item_id)
        try container.encode(quantity, forKey: .quantity)
        try container.encodeIfPresent(icon, forKey: .icon)
    }

    private enum CodingKeys: String, CodingKey {
        case user_id, item_id, quantity, icon
    }
}

struct InventoryUpdateData: Encodable, Sendable {
    let quantity: Int
    let updated_at: String

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(updated_at, forKey: .updated_at)
    }

    private enum CodingKeys: String, CodingKey {
        case quantity, updated_at
    }
}

struct InventoryLogInsertData: Encodable, Sendable {
    let user_id: String
    let operation_type: String
    let item_id: String
    let quantity_change: Int
    let quantity_before: Int
    let quantity_after: Int
    let source: String?

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(user_id, forKey: .user_id)
        try container.encode(operation_type, forKey: .operation_type)
        try container.encode(item_id, forKey: .item_id)
        try container.encode(quantity_change, forKey: .quantity_change)
        try container.encode(quantity_before, forKey: .quantity_before)
        try container.encode(quantity_after, forKey: .quantity_after)
        try container.encodeIfPresent(source, forKey: .source)
    }

    private enum CodingKeys: String, CodingKey {
        case user_id, operation_type, item_id, quantity_change, quantity_before, quantity_after, source
    }
}

// MARK: - 背包管理器

@MainActor
class InventoryManager: ObservableObject {

    // MARK: - 单例
    static let shared = InventoryManager()

    // MARK: - Published Properties
    @Published var items: [InventoryItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Private
    private let supabase = SupabaseManager.shared
    private var hasLoaded = false

    // MARK: - 初始化
    private init() {
        print("📦 [InventoryManager] 初始化完成")
    }

    // MARK: - 加载背包

    /// 从数据库加载当前用户的背包
    func fetchInventory() async {
        guard let userId = await supabase.getCurrentUserId() else {
            print("❌ [InventoryManager] 用户未登录")
            errorMessage = "用户未登录"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await supabase.client.database
                .from("player_inventory")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("item_id")
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)

                // 尝试多种日期格式
                let formatters: [ISO8601DateFormatter] = {
                    let formatter1 = ISO8601DateFormatter()
                    formatter1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                    let formatter2 = ISO8601DateFormatter()
                    formatter2.formatOptions = [.withInternetDateTime]

                    return [formatter1, formatter2]
                }()

                for formatter in formatters {
                    if let date = formatter.date(from: dateString) {
                        return date
                    }
                }

                // 尝试自定义格式
                let customFormatter = DateFormatter()
                customFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZZZZZ"
                customFormatter.locale = Locale(identifier: "en_US_POSIX")
                if let date = customFormatter.date(from: dateString) {
                    return date
                }

                customFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS+00"
                if let date = customFormatter.date(from: dateString) {
                    return date
                }

                throw DecodingError.dataCorruptedError(in: container, debugDescription: "无法解析日期: \(dateString)")
            }

            items = try decoder.decode([InventoryItem].self, from: response.data)
            hasLoaded = true

            print("📦 [InventoryManager] 加载了 \(items.count) 种物品")
            for item in items {
                print("   - \(item.displayName): x\(item.quantity)")
            }

        } catch {
            print("❌ [InventoryManager] 加载失败: \(error)")
            errorMessage = "加载背包失败: \(error.localizedDescription)"
        }
    }

    /// 刷新背包（强制重新加载）
    func refresh() async {
        hasLoaded = false
        await fetchInventory()
    }

    // MARK: - 查询方法

    /// 获取某物品的数量
    func getQuantity(itemId: String) -> Int {
        items.first { $0.itemId == itemId }?.quantity ?? 0
    }

    /// 检查是否拥有足够的单个物品
    func hasEnough(itemId: String, quantity: Int) -> Bool {
        getQuantity(itemId: itemId) >= quantity
    }

    /// 检查多种资源是否足够（用于建造检查）
    /// - Parameter resources: 所需资源字典 [itemId: quantity]
    /// - Returns: (是否足够, 缺少的资源)
    func hasEnough(resources: [String: Int]) -> (enough: Bool, missing: [String: Int]) {
        var missing: [String: Int] = [:]

        for (itemId, required) in resources {
            let current = getQuantity(itemId: itemId)
            if current < required {
                missing[itemId] = required - current
            }
        }

        return (missing.isEmpty, missing)
    }

    /// 获取背包字典（用于建造检查）
    func getInventoryDict() -> [String: Int] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.itemId, $0.quantity) })
    }

    /// 物品总数量
    var totalQuantity: Int {
        items.reduce(0) { $0 + $1.quantity }
    }

    /// 物品种类数
    var itemCount: Int {
        items.count
    }

    // MARK: - 添加物品

    /// 添加物品到背包（如果已存在则增加数量）
    /// - Parameters:
    ///   - itemId: 物品ID
    ///   - quantity: 数量
    ///   - icon: 图标
    ///   - source: 来源说明
    /// - Returns: 是否成功
    @discardableResult
    func addItem(itemId: String, quantity: Int, icon: String? = nil, source: String? = nil) async -> Bool {
        guard let userId = await supabase.getCurrentUserId() else {
            print("❌ [InventoryManager] 用户未登录")
            return false
        }

        let quantityBefore = getQuantity(itemId: itemId)
        let quantityAfter = quantityBefore + quantity

        do {
            // 使用 upsert 操作（如果存在则更新，不存在则插入）
            if quantityBefore > 0 {
                // 物品已存在，更新数量
                let updateData = InventoryUpdateData(
                    quantity: quantityAfter,
                    updated_at: ISO8601DateFormatter().string(from: Date())
                )

                try await supabase.client.database
                    .from("player_inventory")
                    .update(updateData)
                    .eq("user_id", value: userId.uuidString)
                    .eq("item_id", value: itemId)
                    .execute()

                print("📦 [InventoryManager] 更新物品: \(itemId) \(quantityBefore) -> \(quantityAfter)")
            } else {
                // 物品不存在，插入新记录
                let insertData = InventoryInsertData(
                    user_id: userId.uuidString,
                    item_id: itemId,
                    quantity: quantity,
                    icon: icon
                )

                try await supabase.client.database
                    .from("player_inventory")
                    .insert(insertData)
                    .execute()

                print("📦 [InventoryManager] 添加物品: \(itemId) x\(quantity)")
            }

            // 记录操作日志
            await logOperation(
                userId: userId,
                operationType: "add",
                itemId: itemId,
                quantityChange: quantity,
                quantityBefore: quantityBefore,
                quantityAfter: quantityAfter,
                source: source
            )

            // 刷新本地数据
            await fetchInventory()

            return true

        } catch {
            print("❌ [InventoryManager] 添加物品失败: \(error)")
            errorMessage = "添加物品失败"
            return false
        }
    }

    /// 批量添加物品（从探索掉落）- 使用 upsert 优化
    /// - Parameters:
    ///   - lootItems: 掉落物品列表
    ///   - source: 来源说明
    /// - Returns: 是否成功
    @discardableResult
    func addItems(_ lootItems: [LootItem], source: String = "exploration") async -> Bool {
        guard let userId = await supabase.getCurrentUserId() else {
            print("❌ [InventoryManager] 用户未登录")
            return false
        }

        print("📦 [InventoryManager] 添加 \(lootItems.count) 种物品")

        do {
            for item in lootItems {
                let currentQty = getQuantity(itemId: item.name)
                let newQty = currentQty + item.quantity

                // Upsert: 存在则更新，不存在则插入
                let upsertData = InventoryInsertData(
                    user_id: userId.uuidString,
                    item_id: item.name,
                    quantity: newQty,
                    icon: item.icon
                )

                try await supabase.client.database
                    .from("player_inventory")
                    .upsert(upsertData, onConflict: "user_id,item_id")
                    .execute()

                // 记录日志
                await logOperation(
                    userId: userId,
                    operationType: "add",
                    itemId: item.name,
                    quantityChange: item.quantity,
                    quantityBefore: currentQty,
                    quantityAfter: newQty,
                    source: source
                )

                print("  ✅ \(item.name) +\(item.quantity) → \(newQty)")
            }

            // 刷新本地数据
            await fetchInventory()
            return true

        } catch {
            print("❌ [InventoryManager] 添加物品失败: \(error)")
            errorMessage = "添加物品失败"
            return false
        }
    }

    /// 批量添加物品（兼容旧接口）
    /// - Parameters:
    ///   - lootItems: 掉落物品列表
    ///   - source: 来源说明
    /// - Returns: 成功添加的物品数量
    @available(*, deprecated, renamed: "addItems(_:source:)")
    func addLootItems(_ lootItems: [LootItem], source: String = "exploration") async -> Int {
        let success = await addItems(lootItems, source: source)
        return success ? lootItems.count : 0
    }

    // MARK: - 移除物品

    /// 移除物品（扣除数量）
    /// - Parameters:
    ///   - itemId: 物品ID
    ///   - quantity: 数量
    ///   - source: 来源说明
    /// - Returns: 是否成功
    @discardableResult
    func removeItem(itemId: String, quantity: Int, source: String? = nil) async -> Bool {
        guard let userId = await supabase.getCurrentUserId() else {
            print("❌ [InventoryManager] 用户未登录")
            return false
        }

        let quantityBefore = getQuantity(itemId: itemId)

        guard quantityBefore >= quantity else {
            print("❌ [InventoryManager] 物品不足: \(itemId) 需要 \(quantity)，实际 \(quantityBefore)")
            errorMessage = "物品数量不足"
            return false
        }

        let quantityAfter = quantityBefore - quantity

        do {
            if quantityAfter > 0 {
                // 更新数量
                let updateData = InventoryUpdateData(
                    quantity: quantityAfter,
                    updated_at: ISO8601DateFormatter().string(from: Date())
                )

                try await supabase.client.database
                    .from("player_inventory")
                    .update(updateData)
                    .eq("user_id", value: userId.uuidString)
                    .eq("item_id", value: itemId)
                    .execute()

                print("📦 [InventoryManager] 移除物品: \(itemId) \(quantityBefore) -> \(quantityAfter)")
            } else {
                // 数量为0，删除记录
                try await supabase.client.database
                    .from("player_inventory")
                    .delete()
                    .eq("user_id", value: userId.uuidString)
                    .eq("item_id", value: itemId)
                    .execute()

                print("📦 [InventoryManager] 删除物品: \(itemId)")
            }

            // 记录操作日志
            await logOperation(
                userId: userId,
                operationType: "remove",
                itemId: itemId,
                quantityChange: -quantity,
                quantityBefore: quantityBefore,
                quantityAfter: quantityAfter,
                source: source
            )

            // 刷新本地数据
            await fetchInventory()

            return true

        } catch {
            print("❌ [InventoryManager] 移除物品失败: \(error)")
            errorMessage = "移除物品失败"
            return false
        }
    }

    /// 使用物品
    /// - Parameters:
    ///   - itemId: 物品ID
    ///   - quantity: 数量
    /// - Returns: 是否成功
    @discardableResult
    func useItem(itemId: String, quantity: Int = 1) async -> Bool {
        guard let userId = await supabase.getCurrentUserId() else {
            return false
        }

        let quantityBefore = getQuantity(itemId: itemId)
        guard quantityBefore >= quantity else {
            errorMessage = "物品数量不足"
            return false
        }

        let success = await removeItem(itemId: itemId, quantity: quantity, source: "use")

        if success {
            // 更新日志的操作类型为 use
            // 注意：removeItem 已经记录了日志，这里只是更新类型
            // 实际上我们可以直接在 removeItem 中传入 operationType
            print("📦 [InventoryManager] 使用物品: \(itemId) x\(quantity)")
        }

        return success
    }

    /// 消耗资源（建造时调用）- 优化版本
    /// - Parameters:
    ///   - resources: 资源字典 [itemId: quantity]
    ///   - source: 来源说明（如 "building_小木屋"）
    /// - Returns: 是否成功
    func consumeResources(_ resources: [String: Int], source: String = "building") async -> Bool {
        // 先检查是否足够
        let (enough, missing) = hasEnough(resources: resources)
        if !enough {
            let missingText = missing.map { "\($0.key)差\($0.value)" }.joined(separator: ", ")
            errorMessage = "资源不足: \(missingText)"
            print("❌ [InventoryManager] 资源不足: \(missing)")
            return false
        }

        guard let userId = await supabase.getCurrentUserId() else {
            print("❌ [InventoryManager] 用户未登录")
            return false
        }

        print("📦 [InventoryManager] 消耗资源: \(resources)")

        do {
            for (itemId, amount) in resources {
                let currentQty = getQuantity(itemId: itemId)
                let newQty = currentQty - amount

                if newQty > 0 {
                    // 更新数量
                    let updateData = InventoryUpdateData(
                        quantity: newQty,
                        updated_at: ISO8601DateFormatter().string(from: Date())
                    )

                    try await supabase.client.database
                        .from("player_inventory")
                        .update(updateData)
                        .eq("user_id", value: userId.uuidString)
                        .eq("item_id", value: itemId)
                        .execute()
                } else {
                    // 数量为0，删除记录
                    try await supabase.client.database
                        .from("player_inventory")
                        .delete()
                        .eq("user_id", value: userId.uuidString)
                        .eq("item_id", value: itemId)
                        .execute()
                }

                // 记录日志
                await logOperation(
                    userId: userId,
                    operationType: "use",
                    itemId: itemId,
                    quantityChange: -amount,
                    quantityBefore: currentQty,
                    quantityAfter: newQty,
                    source: source
                )

                print("  📦 \(itemId) -\(amount) → \(newQty)")
            }

            await fetchInventory()
            print("📦 [InventoryManager] 资源消耗完成")
            return true

        } catch {
            print("❌ [InventoryManager] 消耗资源失败: \(error)")
            errorMessage = "消耗资源失败"
            return false
        }
    }

    // MARK: - 操作日志

    /// 记录操作日志
    private func logOperation(
        userId: UUID,
        operationType: String,
        itemId: String,
        quantityChange: Int,
        quantityBefore: Int,
        quantityAfter: Int,
        source: String?
    ) async {
        let logData = InventoryLogInsertData(
            user_id: userId.uuidString,
            operation_type: operationType,
            item_id: itemId,
            quantity_change: quantityChange,
            quantity_before: quantityBefore,
            quantity_after: quantityAfter,
            source: source
        )

        do {
            try await supabase.client.database
                .from("inventory_logs")
                .insert(logData)
                .execute()

            print("📝 [InventoryManager] 记录日志: \(operationType) \(itemId) \(quantityChange > 0 ? "+" : "")\(quantityChange)")
        } catch {
            print("⚠️ [InventoryManager] 记录日志失败: \(error)")
            // 日志失败不影响主流程
        }
    }

    // MARK: - 获取操作日志

    /// 获取操作日志
    /// - Parameter limit: 数量限制
    /// - Returns: 日志列表
    func fetchLogs(limit: Int = 50) async -> [InventoryLog] {
        guard let userId = await supabase.getCurrentUserId() else {
            return []
        }

        do {
            let response = try await supabase.client.database
                .from("inventory_logs")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)

                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: dateString) {
                    return date
                }

                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: dateString) {
                    return date
                }

                throw DecodingError.dataCorruptedError(in: container, debugDescription: "无法解析日期")
            }

            let logs = try decoder.decode([InventoryLog].self, from: response.data)
            print("📝 [InventoryManager] 加载了 \(logs.count) 条日志")
            return logs

        } catch {
            print("❌ [InventoryManager] 加载日志失败: \(error)")
            return []
        }
    }
}
