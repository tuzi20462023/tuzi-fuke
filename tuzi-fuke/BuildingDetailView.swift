//
//  BuildingDetailView.swift
//  tuzi-fuke
//
//  DAY8: 建筑详情页 - 查看建筑信息、升级、维修
//  Created by AI Assistant on 2025/12/03.
//

import SwiftUI
import Combine

struct BuildingDetailView: View {
    let building: PlayerBuilding
    @StateObject private var buildingManager = BuildingManager.shared
    @Environment(\.dismiss) private var dismiss

    // 用于刷新倒计时
    @State private var currentTime = Date()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 建筑头部
                    buildingHeader

                    // 状态卡片
                    statusCard

                    // 建造进度（如果正在建造）
                    if building.status == .constructing {
                        constructionProgressCard
                    }

                    // 耐久度（如果已激活）
                    if building.status == .active {
                        durabilityCard
                    }

                    // 建筑效果
                    if let template = buildingManager.getTemplate(for: building.buildingTemplateKey),
                       !template.effects.isEmpty {
                        effectsCard(template: template)
                    }

                    // 操作按钮
                    actionButtons
                }
                .padding()
            }
            .navigationTitle("建筑详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .onReceive(timer) { _ in
                if building.status == .constructing {
                    currentTime = Date()
                }
            }
        }
    }

    // MARK: - 建筑头部

    private var buildingHeader: some View {
        VStack(spacing: 12) {
            // 图标
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 80, height: 80)

                if let template = buildingManager.getTemplate(for: building.buildingTemplateKey) {
                    Image(systemName: template.icon)
                        .font(.system(size: 36))
                        .foregroundColor(statusColor)
                } else {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 36))
                        .foregroundColor(statusColor)
                }
            }

            // 名称和等级
            VStack(spacing: 4) {
                Text(building.buildingName)
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Lv.\(building.level)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    // MARK: - 状态卡片

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("状态")
                .font(.headline)

            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(statusDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(statusColor.opacity(0.1))
            .cornerRadius(12)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }

    // MARK: - 建造进度卡片

    private var constructionProgressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("建造进度")
                .font(.headline)

            VStack(spacing: 8) {
                // 进度条
                ProgressView(value: building.buildProgress())
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))

                HStack {
                    Text("剩余时间")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(building.formattedRemainingTime)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }

                // 预计完成时间
                if let completedAt = building.buildCompletedAt {
                    HStack {
                        Text("预计完成")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(formatDate(completedAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }

    // MARK: - 耐久度卡片

    private var durabilityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("耐久度")
                .font(.headline)

            VStack(spacing: 8) {
                // 耐久度条
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 12)
                            .cornerRadius(6)

                        Rectangle()
                            .fill(durabilityColor)
                            .frame(width: geometry.size.width * durabilityPercentage, height: 12)
                            .cornerRadius(6)
                    }
                }
                .frame(height: 12)

                HStack {
                    Text("\(building.durability) / \(building.durabilityMax)")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    Text("\(Int(durabilityPercentage * 100))%")
                        .font(.subheadline)
                        .foregroundColor(durabilityColor)
                }
            }
            .padding()
            .background(durabilityColor.opacity(0.1))
            .cornerRadius(12)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }

    // MARK: - 效果卡片

    private func effectsCard(template: BuildingTemplate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("建筑效果")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(Array(template.effects.keys.sorted()), id: \.self) { key in
                    if let effect = template.effects[key] {
                        HStack {
                            Image(systemName: effectIcon(for: key))
                                .foregroundColor(.green)
                            Text(effectName(for: key))
                                .font(.subheadline)
                            Spacer()
                            Text("+\(effect.displayString)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }

    // MARK: - 操作按钮

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // 升级按钮（仅激活状态可用）
            if building.status == .active {
                Button {
                    // TODO: 实现升级逻辑
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("升级建筑")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }

                // 维修按钮（耐久度低于50%时显示）
                if durabilityPercentage < 0.5 {
                    Button {
                        // TODO: 实现维修逻辑
                    } label: {
                        HStack {
                            Image(systemName: "wrench.fill")
                            Text("维修建筑")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
            }

            // 拆除按钮
            Button {
                // TODO: 实现拆除逻辑
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                    Text("拆除建筑")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
                .cornerRadius(12)
            }
        }
        .padding()
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch building.status {
        case .constructing: return .blue
        case .active: return .green
        case .damaged: return .orange
        case .inactive: return .gray
        }
    }

    private var statusIcon: String {
        switch building.status {
        case .constructing: return "hammer.fill"
        case .active: return "checkmark.circle.fill"
        case .damaged: return "exclamationmark.triangle.fill"
        case .inactive: return "pause.circle.fill"
        }
    }

    private var statusText: String {
        switch building.status {
        case .constructing: return "建造中"
        case .active: return "运行中"
        case .damaged: return "需要维修"
        case .inactive: return "已停用"
        }
    }

    private var statusDescription: String {
        switch building.status {
        case .constructing: return "建筑正在建造，完成后将自动激活"
        case .active: return "建筑正常运行，提供各种加成效果"
        case .damaged: return "建筑受损，部分功能无法使用"
        case .inactive: return "建筑已停用，不提供任何效果"
        }
    }

    private var durabilityPercentage: Double {
        guard building.durabilityMax > 0 else { return 0 }
        return Double(building.durability) / Double(building.durabilityMax)
    }

    private var durabilityColor: Color {
        if durabilityPercentage > 0.6 {
            return .green
        } else if durabilityPercentage > 0.3 {
            return .orange
        } else {
            return .red
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func effectIcon(for key: String) -> String {
        switch key {
        case "storage": return "archivebox.fill"
        case "defense": return "shield.fill"
        case "production": return "hammer.fill"
        case "comfort": return "heart.fill"
        default: return "star.fill"
        }
    }

    private func effectName(for key: String) -> String {
        switch key {
        case "storage": return "存储容量"
        case "defense": return "防御力"
        case "production": return "生产效率"
        case "comfort": return "舒适度"
        default: return key
        }
    }
}

// MARK: - Preview

#Preview {
    BuildingDetailView(
        building: PlayerBuilding(
            id: UUID(),
            userId: UUID(),
            territoryId: UUID(),
            buildingTemplateId: UUID(),
            buildingName: "小型仓库",
            buildingTemplateKey: "storage_small",
            location: nil,
            status: .active,
            buildStartedAt: Date().addingTimeInterval(-3600),
            buildCompletedAt: Date(),
            buildTimeHours: 1.0,
            level: 1,
            durability: 80,
            durabilityMax: 100,
            createdAt: Date(),
            updatedAt: Date()
        )
    )
}
