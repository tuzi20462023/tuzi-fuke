//
//  AILootDescriptionGenerator.swift
//  tuzi-fuke
//
//  AI 物资描述生成器 - 根据探索数据生成旅行风格的探索日记
//  使用通义千问 (Qwen) API
//

import Foundation
import Combine

// MARK: - 探索物资结果

struct ExplorationLoot: Codable {
    let narrative: String           // AI生成的探索日记
    let items: [LootItem]           // 发现的物资列表
    let mood: String                // 氛围：relaxed/excited/peaceful/adventurous
}

struct LootItem: Codable, Identifiable {
    let id: String
    let name: String
    let quantity: Int
    let icon: String                // SF Symbol 图标名

    init(id: String = UUID().uuidString, name: String, quantity: Int, icon: String) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.icon = icon
    }
}

// MARK: - AI 生成器

@MainActor
class AILootDescriptionGenerator: ObservableObject {

    static let shared = AILootDescriptionGenerator()

    @Published var isGenerating: Bool = false
    @Published var lastError: String?

    private init() {}

    // MARK: - 主要方法

    /// 根据探索数据生成 AI 物资描述
    /// - Parameters:
    ///   - distance: 行走距离（米）
    ///   - area: 探索面积（平方米）
    ///   - duration: 探索时长（秒）
    ///   - discoveredPOIs: 本次探索发现的POI列表
    /// - Returns: 探索物资结果
    func generateLootDescription(
        distance: Double,
        area: Double,
        duration: TimeInterval,
        discoveredPOIs: [DiscoveredPOIInfo] = []
    ) async -> ExplorationLoot {

        isGenerating = true
        lastError = nil

        // 1. 先本地计算物资（基于探索数据）
        let items = calculateLocalLoot(distance: distance, area: area, duration: duration)

        // 2. 尝试调用 AI 生成叙述
        let narrative: String
        let mood: String

        do {
            appLog(.info, category: "AI", message: "开始调用通义千问 API...")
            appLog(.info, category: "AI", message: "探索数据: 距离=\(String(format: "%.1f", distance))米, 面积=\(String(format: "%.0f", area))m², 时长=\(Int(duration))秒")
            appLog(.info, category: "AI", message: "物资数量: \(items.count)种, POI数量: \(discoveredPOIs.count)个")

            let aiResult = try await callAIAPI(distance: distance, area: area, duration: duration, items: items, discoveredPOIs: discoveredPOIs)
            narrative = aiResult.narrative
            mood = aiResult.mood

            appLog(.success, category: "AI", message: "通义千问生成成功! 氛围: \(mood)")
            appLog(.info, category: "AI", message: "叙述: \(String(narrative.prefix(50)))...")
        } catch {
            // AI 调用失败，使用本地模板
            appLog(.warning, category: "AI", message: "调用失败: \(error.localizedDescription)")
            lastError = error.localizedDescription
            let localResult = generateLocalNarrative(distance: distance, area: area, duration: duration, items: items, discoveredPOIs: discoveredPOIs)
            narrative = localResult.narrative
            mood = localResult.mood
            appLog(.info, category: "AI", message: "使用本地模板")
        }

        isGenerating = false

        return ExplorationLoot(
            narrative: narrative,
            items: items,
            mood: mood
        )
    }

    // MARK: - 本地物资计算

    /// 根据探索数据计算物资掉落（旅行版建造材料）
    private func calculateLocalLoot(distance: Double, area: Double, duration: TimeInterval) -> [LootItem] {
        var items: [LootItem] = []

        // 旅行版物资掉落池（建造材料）
        let lootPool: [(name: String, icon: String, baseChance: Double)] = [
            ("木材", "tree.fill", 0.8),           // 基础建筑材料
            ("石材", "mountain.2.fill", 0.7),     // 基础建筑材料
            ("钢材", "wrench.and.screwdriver.fill", 0.4),  // 高级建筑
            ("玻璃", "window.vertical.closed", 0.5),       // 装饰建筑
            ("金币", "dollarsign.circle.fill", 0.6),      // 通用货币
            ("蓝图", "doc.plaintext.fill", 0.25),  // 解锁建筑
            ("装饰品", "paintpalette.fill", 0.45), // 美化建筑
            ("植物", "leaf.fill", 0.55),           // 环境美化
        ]

        // 距离系数：每500米增加一次掉落机会
        let distanceFactor = max(1, Int(distance / 500))

        // 面积系数：每2500平方米（50x50网格）增加掉落
        let areaFactor = max(1, Int(area / 2500))

        // 时长系数：每10分钟增加掉落
        let durationFactor = max(1, Int(duration / 600))

        // 综合掉落次数
        let dropOpportunities = min(distanceFactor + areaFactor + durationFactor, 15)

        print("🎲 [Loot] 计算掉落: 距离系数=\(distanceFactor), 面积系数=\(areaFactor), 时长系数=\(durationFactor)")
        print("🎲 [Loot] 掉落机会: \(dropOpportunities)次")

        // 为每种物品计算掉落
        for (name, icon, baseChance) in lootPool {
            // 根据掉落机会调整概率
            let adjustedChance = min(baseChance * Double(dropOpportunities) / 5.0, 0.95)

            if Double.random(in: 0...1) < adjustedChance {
                // 数量基于探索规模
                let baseQuantity = Int.random(in: 1...5)
                let bonusQuantity = Int(Double(dropOpportunities) * Double.random(in: 0.5...1.5))
                let quantity = baseQuantity + bonusQuantity

                items.append(LootItem(name: name, quantity: quantity, icon: icon))
            }
        }

        // 确保至少有2个物品
        if items.count < 2 {
            items.append(LootItem(name: "木材", quantity: Int.random(in: 3...8), icon: "tree.fill"))
            items.append(LootItem(name: "石材", quantity: Int.random(in: 2...6), icon: "mountain.2.fill"))
        }

        print("🎲 [Loot] 最终掉落: \(items.count)种物品")
        return items
    }

    // MARK: - AI API 调用

    /// 调用 AI API 生成叙述
    private func callAIAPI(
        distance: Double,
        area: Double,
        duration: TimeInterval,
        items: [LootItem],
        discoveredPOIs: [DiscoveredPOIInfo]
    ) async throws -> (narrative: String, mood: String) {

        // 构建物资列表文本
        let itemsText = items.map { "\($0.name) x \($0.quantity)" }.joined(separator: "、")

        // 构建发现的POI列表文本
        let poiText: String
        if discoveredPOIs.isEmpty {
            poiText = "无"
        } else {
            poiText = discoveredPOIs.map { "\($0.name)（\($0.type)）" }.joined(separator: "、")
        }

        // 构建提示词（旅行风格，包含POI信息）
        let prompt = """
        你是一个旅行探索 App 的叙事助手。用户刚完成一次城市漫步，数据如下：
        - 行走距离：\(String(format: "%.1f", distance / 1000)) 公里
        - 探索面积：\(String(format: "%.0f", area)) 平方米
        - 探索时长：\(Int(duration / 60)) 分钟
        - 途经地点：\(poiText)
        - 收集物资：\(itemsText)

        请生成一段 60-100 字的探索日记，要求：
        - 第一人称视角
        - 温暖治愈的文风，描述城市漫步的美好
        - 如果有途经地点，请自然地融入叙述中（如"路过了XX"、"在XX附近停留"等）
        - 有画面感，描述阳光、微风、街道等细节

        只返回日记文本，不要其他内容。
        """

        // 检查是否配置了 API Key
        guard let apiKey = getAIAPIKey(), !apiKey.isEmpty else {
            throw AIError.noAPIKey
        }

        // 调用通义千问 API
        return try await callQwenAPI(prompt: prompt, apiKey: apiKey)
    }

    /// 调用通义千问 (Qwen) API
    private func callQwenAPI(prompt: String, apiKey: String) async throws -> (narrative: String, mood: String) {
        let url = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "qwen-turbo",
            "max_tokens": 300,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AIError.apiError("API 响应错误 (状态码: \(statusCode))")
        }

        // 解析响应（OpenAI 兼容格式）
        struct QwenResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let qwenResponse = try JSONDecoder().decode(QwenResponse.self, from: data)
        let narrative = qwenResponse.choices.first?.message.content ?? ""

        // 根据内容判断氛围（旅行风格）
        let mood: String
        if narrative.contains("惊喜") || narrative.contains("发现") || narrative.contains("兴奋") {
            mood = "excited"
        } else if narrative.contains("宁静") || narrative.contains("安静") || narrative.contains("静谧") {
            mood = "peaceful"
        } else if narrative.contains("冒险") || narrative.contains("探索") || narrative.contains("未知") {
            mood = "adventurous"
        } else {
            mood = "relaxed"
        }

        return (narrative, mood)
    }

    /// 获取 AI API Key（从配置或环境变量）
    private func getAIAPIKey() -> String? {
        // 优先从 UserDefaults 读取
        if let key = UserDefaults.standard.string(forKey: "QWEN_API_KEY"), !key.isEmpty {
            return key
        }

        // 其次从环境变量读取
        if let key = ProcessInfo.processInfo.environment["QWEN_API_KEY"], !key.isEmpty {
            return key
        }

        return nil
    }

    // MARK: - 本地叙述生成（备用）

    /// 本地生成叙述（AI 不可用时的备用方案）- 旅行风格
    private func generateLocalNarrative(
        distance: Double,
        area: Double,
        duration: TimeInterval,
        items: [LootItem],
        discoveredPOIs: [DiscoveredPOIInfo]
    ) -> (narrative: String, mood: String) {

        let distanceKm = distance / 1000
        let durationMin = Int(duration / 60)

        // 如果有发现POI，生成包含POI的叙述
        if !discoveredPOIs.isEmpty {
            let poiNames = discoveredPOIs.prefix(2).map { $0.name }.joined(separator: "、")
            let templates = [
                "阳光正好，我沿着街道漫步了\(durationMin)分钟。途经\(poiNames)，感受到城市的烟火气。背包里装满了今天的收获，心情格外愉快。",
                "这次漫步走了\(String(format: "%.1f", distanceKm))公里。路过\(poiNames)，在熟悉的街角发现了新的风景。城市的角落总有温暖的惊喜。",
                "微风拂面，我在这片街区探索了\(durationMin)分钟。在\(poiNames)附近停留，感受这座城市的脉搏。收获满满的一天。"
            ]
            let narrative = templates.randomElement() ?? templates[0]
            let moods = ["relaxed", "excited", "peaceful", "adventurous"]
            let mood = moods.randomElement() ?? "relaxed"
            return (narrative, mood)
        }

        // 没有POI时使用通用模板
        let templates = [
            "阳光正好，我沿着街道漫步了\(durationMin)分钟。路过一家咖啡店，香气扑鼻而来。背包里装满了今天的收获，心情格外愉快。",
            "这次漫步走了\(String(format: "%.1f", distanceKm))公里。穿过公园的林荫道，看见老人在下棋，孩子在嬉戏。城市的角落总有温暖的风景。",
            "微风拂面，我在这片街区探索了\(durationMin)分钟。发现了一家藏在巷子里的小书店，翻了几页喜欢的书。收获满满的一天。",
            "走过\(String(format: "%.1f", distanceKm))公里的路程，脚步轻快。街角的花店、转角的面包房，每一处都是城市的小确幸。今天的漫步很值得。",
            "又是一次愉快的城市探索。\(durationMin)分钟的漫步，遇见了熟悉又陌生的街景。阳光洒在肩上，背包里是今天的战利品。"
        ]

        let narrative = templates.randomElement() ?? templates[0]

        // 旅行风格随机氛围
        let moods = ["relaxed", "excited", "peaceful", "adventurous"]
        let mood = moods.randomElement() ?? "relaxed"

        return (narrative, mood)
    }
}

// MARK: - 错误类型

enum AIError: Error, LocalizedError {
    case noAPIKey
    case apiError(String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "未配置 AI API Key"
        case .apiError(let msg):
            return "AI 服务错误: \(msg)"
        case .parseError:
            return "AI 响应解析失败"
        }
    }
}

// MARK: - 设置 API Key 的辅助方法

extension AILootDescriptionGenerator {

    /// 设置通义千问 API Key
    static func setAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "QWEN_API_KEY")
    }

    /// 检查是否已配置 API Key
    static var hasAPIKey: Bool {
        if let key = UserDefaults.standard.string(forKey: "QWEN_API_KEY"), !key.isEmpty {
            return true
        }
        if let key = ProcessInfo.processInfo.environment["QWEN_API_KEY"], !key.isEmpty {
            return true
        }
        return false
    }
}
