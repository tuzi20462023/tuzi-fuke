//
//  InventoryItem.swift
//  tuzi-fuke (地球新主复刻版)
//
//  背包物品数据模型 - 对应 player_inventory 和 inventory_logs 表
//  Created by AI Assistant on 2025/12/06.
//

import Foundation

// MARK: - 背包物品（对应 player_inventory 表）

struct InventoryItem: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let itemId: String
    var quantity: Int
    let icon: String?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case itemId = "item_id"
        case quantity
        case icon
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// 物品分类（根据 itemId 推断）
    var category: ItemCategory {
        switch itemId {
        case "wood", "植物", "树枝", "木材":
            return .wood
        case "stone", "石材", "石头":
            return .stone
        case "steel", "钢材", "金属", "铁", "玻璃":
            return .metal
        case "gold", "金币", "货币":
            return .currency
        default:
            return .other
        }
    }

    /// 显示名称（中文）
    var displayName: String {
        switch itemId {
        case "wood": return "木材"
        case "stone": return "石材"
        case "steel": return "钢材"
        case "gold": return "金币"
        default: return itemId
        }
    }

    /// 物品描述
    var description: String {
        switch itemId {
        case "wood", "木材":
            return "从树木上采集的原木，是建造木质建筑的基础材料。质地坚韧，用途广泛。"
        case "stone", "石材":
            return "从岩石中开采的石块，可用于建造坚固的石质建筑和防御工事。"
        case "steel", "钢材":
            return "经过冶炼的高强度金属，是建造高级建筑和制作工具的珍贵材料。"
        case "gold", "金币":
            return "通用货币，可用于交易、购买物品和升级建筑。探索和完成任务可获得。"
        case "玻璃":
            return "透明的玻璃材料，用于制作窗户和装饰性建筑。"
        case "蓝图":
            return "珍贵的建筑图纸，可用于解锁新的建筑类型。"
        case "装饰品":
            return "用于美化建筑和领地的装饰物品。"
        case "植物":
            return "可用于环境美化和花园建设的植物。"
        default:
            return "探索中发现的物品。"
        }
    }

    /// 默认图标
    var displayIcon: String {
        if let icon = icon, !icon.isEmpty {
            return icon
        }
        // 根据物品类型返回默认图标
        switch itemId {
        case "wood", "木材": return "tree.fill"
        case "stone", "石材": return "mountain.2.fill"
        case "steel", "钢材": return "wrench.and.screwdriver.fill"
        case "gold", "金币": return "dollarsign.circle.fill"
        case "玻璃": return "window.vertical.closed"
        case "蓝图": return "doc.plaintext.fill"
        case "装饰品": return "paintpalette.fill"
        case "植物": return "leaf.fill"
        default: return "shippingbox.fill"
        }
    }

    /// 物品分类枚举
    enum ItemCategory {
        case wood       // 木材/植物
        case stone      // 石材
        case metal      // 钢材/金属
        case currency   // 金币/货币
        case other      // 其他

        var color: String {
            switch self {
            case .wood: return "green"
            case .stone: return "gray"
            case .metal: return "blue"
            case .currency: return "yellow"
            case .other: return "purple"
            }
        }

        var displayName: String {
            switch self {
            case .wood: return "植物材料"
            case .stone: return "矿石材料"
            case .metal: return "金属材料"
            case .currency: return "货币"
            case .other: return "其他"
            }
        }
    }
}

// MARK: - 库存操作日志（对应 inventory_logs 表）

struct InventoryLog: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let operationType: String
    let itemId: String
    let quantityChange: Int
    let quantityBefore: Int
    let quantityAfter: Int
    let source: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case operationType = "operation_type"
        case itemId = "item_id"
        case quantityChange = "quantity_change"
        case quantityBefore = "quantity_before"
        case quantityAfter = "quantity_after"
        case source
        case createdAt = "created_at"
    }

    /// 操作类型枚举
    enum OperationType: String {
        case add = "add"         // 获得
        case remove = "remove"   // 移除
        case use = "use"         // 使用
        case trade = "trade"     // 交易

        var displayName: String {
            switch self {
            case .add: return "获得"
            case .remove: return "移除"
            case .use: return "使用"
            case .trade: return "交易"
            }
        }

        var icon: String {
            switch self {
            case .add: return "plus.circle.fill"
            case .remove: return "minus.circle.fill"
            case .use: return "hand.tap.fill"
            case .trade: return "arrow.left.arrow.right.circle.fill"
            }
        }
    }

    /// 获取操作类型枚举
    var operation: OperationType {
        return OperationType(rawValue: operationType) ?? .add
    }
}

// MARK: - LootItem 扩展（转换为背包数据）

extension LootItem {
    /// 转换为背包插入数据
    func toInventoryInsert(userId: UUID) -> [String: Any] {
        return [
            "user_id": userId.uuidString,
            "item_id": name,
            "quantity": quantity,
            "icon": icon
        ]
    }

    /// 转换为 InventoryItem（用于本地显示）
    func toInventoryItem(userId: UUID) -> InventoryItem {
        return InventoryItem(
            id: UUID(),
            userId: userId,
            itemId: name,
            quantity: quantity,
            icon: icon,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// MARK: - 插入辅助结构

/// 用于插入新物品的数据结构
struct InventoryInsert: Encodable {
    let userId: UUID
    let itemId: String
    let quantity: Int
    let icon: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case itemId = "item_id"
        case quantity
        case icon
    }
}

/// 用于插入日志的数据结构
struct InventoryLogInsert: Encodable {
    let userId: UUID
    let operationType: String
    let itemId: String
    let quantityChange: Int
    let quantityBefore: Int
    let quantityAfter: Int
    let source: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case operationType = "operation_type"
        case itemId = "item_id"
        case quantityChange = "quantity_change"
        case quantityBefore = "quantity_before"
        case quantityAfter = "quantity_after"
        case source
    }
}
