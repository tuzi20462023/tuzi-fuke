//
//  BuildingQuickViewSheet.swift
//  tuzi-fuke
//
//  主地图点击建筑时的轻量查看弹窗（参考原项目 BuildingDetailSheet）
//  只显示建筑信息，不含拆除/升级等重操作
//  Created by AI Assistant on 2025/12/05.
//

import SwiftUI

/// 建筑快速查看弹窗 - 轻量级，只读预览
struct BuildingQuickViewSheet: View {
    let building: PlayerBuilding
    let template: BuildingTemplate?
    let onManageBuilding: (() -> Void)?  // 跳转到领地建筑管理页

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 建筑图标和名称
                    headerSection

                    // 基础信息
                    basicInfoSection

                    // 状态信息
                    statusSection

                    // 效果预览
                    if let template = template, !template.effects.isEmpty {
                        effectsSection
                    }

                    // 管理按钮
                    if onManageBuilding != nil {
                        manageButton
                    }
                }
                .padding()
            }
            .navigationTitle(building.buildingName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - 头部区域

    private var headerSection: some View {
        VStack(spacing: 12) {
            // 图标
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: template?.icon ?? "building.2.fill")
                    .font(.system(size: 36))
                    .foregroundColor(statusColor)
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

            // 描述
            if let desc = template?.description {
                Text(desc)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
    }

    // MARK: - 基础信息

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("基础信息")
                .font(.headline)

            InfoRow(label: "等级", value: "Lv.\(building.level)")

            if let template = template {
                InfoRow(label: "类型", value: template.category.displayName)
                InfoRow(label: "最大等级", value: "Lv.\(template.maxLevel)")
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - 状态信息

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("状态")
                .font(.headline)

            HStack {
                Text("当前状态")
                    .foregroundColor(.secondary)
                Spacer()
                statusBadge
            }

            // 耐久度
            HStack {
                Text("耐久度")
                    .foregroundColor(.secondary)
                Spacer()
                ProgressView(value: Double(building.durability), total: Double(building.durabilityMax))
                    .frame(width: 80)
                Text("\(building.durability)/\(building.durabilityMax)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 建造进度（如果正在建造）
            if building.status == .constructing {
                HStack {
                    Text("建造进度")
                        .foregroundColor(.secondary)
                    Spacer()
                    ProgressView(value: building.buildProgress())
                        .frame(width: 80)
                    Text(building.formattedRemainingTime)
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var statusBadge: some View {
        Text(statusText)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.2))
            .foregroundColor(statusColor)
            .cornerRadius(8)
    }

    // MARK: - 效果预览

    private var effectsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("建筑效果")
                .font(.headline)

            if let template = template {
                ForEach(Array(template.effects.keys.sorted()), id: \.self) { key in
                    if let effect = template.effects[key] {
                        HStack {
                            Image(systemName: effectIcon(for: key))
                                .foregroundColor(.green)
                                .frame(width: 20)
                            Text(effectName(for: key))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("+\(effect.displayString)")
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - 管理按钮

    private var manageButton: some View {
        Button {
            dismiss()
            // 延迟一下再触发，避免弹窗冲突
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onManageBuilding?()
            }
        } label: {
            HStack {
                Image(systemName: "gearshape.fill")
                Text("管理建筑")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .padding(.top, 8)
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

    private var statusText: String {
        switch building.status {
        case .constructing: return "建造中"
        case .active: return "运行中"
        case .damaged: return "需要维修"
        case .inactive: return "已停用"
        }
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

// MARK: - 信息行组件

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Preview

#Preview {
    BuildingQuickViewSheet(
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
        ),
        template: nil,
        onManageBuilding: nil
    )
}
