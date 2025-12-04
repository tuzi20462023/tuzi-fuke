//
//  AILootDescriptionGenerator.swift
//  tuzi-fuke
//
//  AI 物资描述生成器 - 根据探索数据生成末世风格的物资发现叙述
//

import Foundation
import Combine

// MARK: - 探索物资结果

struct ExplorationLoot: Codable {
    let narrative: String           // AI生成的叙述文本
    let items: [LootItem]           // 发现的物资列表
    let mood: String                // 氛围：tense/hopeful/dangerous
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
    /// - Returns: 探索物资结果
    func generateLootDescription(
        distance: Double,
        area: Double,
        duration: TimeInterval
    ) async -> ExplorationLoot {

        isGenerating = true
        lastError = nil

        // 1. 先本地计算物资（基于探索数据）
        let items = calculateLocalLoot(distance: distance, area: area, duration: duration)

        // 2. 尝试调用 AI 生成叙述
        let narrative: String
        let mood: String

        do {
            let aiResult = try await callAIAPI(distance: distance, area: area, duration: duration, items: items)
            narrative = aiResult.narrative
            mood = aiResult.mood
        } catch {
            // AI 调用失败，使用本地模板
            print("⚠️ [AI] 调用失败，使用本地模板: \(error.localizedDescription)")
            lastError = error.localizedDescription
            let localResult = generateLocalNarrative(distance: distance, area: area, duration: duration, items: items)
            narrative = localResult.narrative
            mood = localResult.mood
        }

        isGenerating = false

        return ExplorationLoot(
            narrative: narrative,
            items: items,
            mood: mood
        )
    }

    // MARK: - 本地物资计算

    /// 根据探索数据计算物资掉落
    private func calculateLocalLoot(distance: Double, area: Double, duration: TimeInterval) -> [LootItem] {
        var items: [LootItem] = []

        // 基础掉落池
        let lootPool: [(name: String, icon: String, baseChance: Double)] = [
            ("矿泉水", "drop.fill", 0.8),
            ("罐头食品", "takeoutbag.and.cup.and.straw.fill", 0.6),
            ("废金属", "gearshape.fill", 0.7),
            ("布料", "tshirt.fill", 0.5),
            ("木材", "leaf.fill", 0.6),
            ("绳索", "link", 0.4),
            ("医疗包", "cross.case.fill", 0.2),
            ("电池", "battery.100", 0.3),
            ("工具零件", "wrench.fill", 0.35),
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
            items.append(LootItem(name: "矿泉水", quantity: Int.random(in: 2...5), icon: "drop.fill"))
            items.append(LootItem(name: "废金属", quantity: Int.random(in: 3...8), icon: "gearshape.fill"))
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
        items: [LootItem]
    ) async throws -> (narrative: String, mood: String) {

        // 构建物资列表文本
        let itemsText = items.map { "\($0.name) x \($0.quantity)" }.joined(separator: "、")

        // 构建提示词
        let prompt = """
        你是一个末世生存游戏的叙事助手。玩家刚完成一次探索，数据如下：
        - 行走距离：\(String(format: "%.1f", distance / 1000)) 公里
        - 探索面积：\(String(format: "%.0f", area)) 平方米
        - 探索时长：\(Int(duration / 60)) 分钟
        - 发现物资：\(itemsText)

        请生成一段 60-100 字的第一人称叙述，描述玩家如何在废墟中发现这些物资。
        要求：末世求生风格、紧张刺激、有画面感。

        只返回叙述文本，不要其他内容。
        """

        // TODO: 替换为实际的 AI API 调用
        // 这里先用模拟延迟 + 本地模板
        // 实际使用时替换为 Claude API 或 OpenAI API

        // 检查是否配置了 API Key
        guard let apiKey = getAIAPIKey(), !apiKey.isEmpty else {
            throw AIError.noAPIKey
        }

        // 调用 Claude API
        return try await callClaudeAPI(prompt: prompt, apiKey: apiKey)
    }

    /// 调用 Claude API
    private func callClaudeAPI(prompt: String, apiKey: String) async throws -> (narrative: String, mood: String) {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-3-haiku-20240307",
            "max_tokens": 300,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AIError.apiError("API 响应错误")
        }

        // 解析响应
        struct ClaudeResponse: Codable {
            struct Content: Codable {
                let text: String
            }
            let content: [Content]
        }

        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        let narrative = claudeResponse.content.first?.text ?? ""

        // 根据内容判断氛围
        let mood: String
        if narrative.contains("危险") || narrative.contains("紧张") || narrative.contains("小心") {
            mood = "dangerous"
        } else if narrative.contains("幸运") || narrative.contains("惊喜") || narrative.contains("收获") {
            mood = "hopeful"
        } else {
            mood = "tense"
        }

        return (narrative, mood)
    }

    /// 获取 AI API Key（从配置或环境变量）
    private func getAIAPIKey() -> String? {
        // 优先从 UserDefaults 读取
        if let key = UserDefaults.standard.string(forKey: "AI_API_KEY"), !key.isEmpty {
            return key
        }

        // 其次从环境变量读取
        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty {
            return key
        }

        return nil
    }

    // MARK: - 本地叙述生成（备用）

    /// 本地生成叙述（AI 不可用时的备用方案）
    private func generateLocalNarrative(
        distance: Double,
        area: Double,
        duration: TimeInterval,
        items: [LootItem]
    ) -> (narrative: String, mood: String) {

        let distanceKm = distance / 1000
        let durationMin = Int(duration / 60)

        // 叙述模板池
        let templates = [
            "穿过一片废墟，我在倒塌的建筑里搜寻了\(durationMin)分钟。破碎的窗户外传来不明的声响，我加快了脚步。还好，背包里多了些补给。",
            "这次探索走了将近\(String(format: "%.1f", distanceKm))公里。在一家废弃的商店里，我找到了一些有用的东西。外面的世界越来越危险，但活下去的希望也在。",
            "阳光透过残破的天花板照进来。我翻遍了每一个角落，\(durationMin)分钟后，终于有了收获。这些物资能让我再撑一段时间。",
            "废墟中弥漫着灰尘的味道。我小心翼翼地前进，生怕惊动什么。\(String(format: "%.1f", distanceKm))公里的路程，换来了背包里沉甸甸的重量。值了。",
            "又是一次冒险的探索。穿过狭窄的巷道，避开可疑的阴影，我在这片区域搜刮了\(durationMin)分钟。收获不错，但我知道，明天还要继续。"
        ]

        let narrative = templates.randomElement() ?? templates[0]

        // 随机氛围
        let moods = ["tense", "hopeful", "dangerous"]
        let mood = moods.randomElement() ?? "tense"

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

    /// 设置 AI API Key
    static func setAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "AI_API_KEY")
    }

    /// 检查是否已配置 API Key
    static var hasAPIKey: Bool {
        if let key = UserDefaults.standard.string(forKey: "AI_API_KEY"), !key.isEmpty {
            return true
        }
        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty {
            return true
        }
        return false
    }
}
