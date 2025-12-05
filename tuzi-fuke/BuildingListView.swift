//
//  BuildingListView.swift
//  tuzi-fuke
//
//  DAY8: 建筑列表界面 - 显示所有可建造的建筑模板
//  Created by AI Assistant on 2025/12/02.
//

import SwiftUI

struct BuildingListView: View {
    let territoryId: UUID
    let onSelectBuilding: (BuildingTemplate) -> Void

    // ✅ 使用 @ObservedObject 而不是 @StateObject，因为 BuildingManager.shared 是单例
    @ObservedObject private var buildingManager = BuildingManager.shared
    @State private var selectedCategory: NewBuildingCategory?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 分类选择器
                categoryPicker

                // 建筑列表（模板从Bundle加载，无需loading）
                if buildingManager.buildingTemplates.isEmpty {
                    emptyView
                } else {
                    buildingList
                }
            }
            .navigationTitle("建造建筑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
        // ✅ 移除 .task，模板已在 BuildingManager.init() 同步加载
        // 如果为空才异步获取（回退到网络）
        .onAppear {
            if buildingManager.buildingTemplates.isEmpty {
                Task {
                    await buildingManager.fetchBuildingTemplates()
                }
            }
        }
    }

    // MARK: - 分类选择器

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // 全部
                CategoryButton(
                    title: "全部",
                    icon: "square.grid.2x2.fill",
                    isSelected: selectedCategory == nil,
                    color: .gray
                ) {
                    selectedCategory = nil
                }

                // 各分类
                ForEach(NewBuildingCategory.allCases, id: \.self) { category in
                    CategoryButton(
                        title: category.displayName,
                        icon: category.icon,
                        isSelected: selectedCategory == category,
                        color: categoryColor(category)
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - 建筑列表

    private var buildingList: some View {
        List {
            ForEach(filteredTemplates) { template in
                BuildingTemplateRow(template: template) {
                    onSelectBuilding(template)
                    dismiss()
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - 空视图

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2.crop.circle")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            Text("暂无可用建筑")
                .font(.headline)
                .foregroundColor(.secondary)
            Button("刷新") {
                Task {
                    await buildingManager.fetchBuildingTemplates()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var filteredTemplates: [BuildingTemplate] {
        if let category = selectedCategory {
            return buildingManager.templates(for: category)
        }
        return buildingManager.buildingTemplates
    }

    private func categoryColor(_ category: NewBuildingCategory) -> Color {
        switch category.color {
        case "blue": return .blue
        case "brown": return .brown
        case "green": return .green
        case "yellow": return .orange
        case "red": return .red
        default: return .gray
        }
    }
}

// MARK: - 分类按钮

struct CategoryButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption)
            }
            .foregroundColor(isSelected ? .white : color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? color : color.opacity(0.15))
            )
        }
    }
}

// MARK: - 建筑模板行

struct BuildingTemplateRow: View {
    let template: BuildingTemplate
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 图标
                ZStack {
                    Circle()
                        .fill(categoryColor.opacity(0.15))
                        .frame(width: 50, height: 50)
                    Image(systemName: template.icon)
                        .font(.system(size: 24))
                        .foregroundColor(categoryColor)
                }

                // 信息
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(template.name)
                            .font(.headline)
                            .foregroundColor(.primary)

                        // Tier 标签
                        Text("T\(template.tier)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(tierColor)
                            .clipShape(Capsule())
                    }

                    if let desc = template.description {
                        Text(desc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    // 建造信息
                    HStack(spacing: 12) {
                        Label(template.formattedBuildTime, systemImage: "clock")
                        Label("Lv.\(template.requiredLevel)", systemImage: "star")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private var categoryColor: Color {
        switch template.category.color {
        case "blue": return .blue
        case "brown": return .brown
        case "green": return .green
        case "yellow": return .orange
        case "red": return .red
        default: return .gray
        }
    }

    private var tierColor: Color {
        switch template.tier {
        case 1: return .green
        case 2: return .orange
        case 3: return .purple
        default: return .gray
        }
    }
}

// MARK: - Preview

#Preview {
    BuildingListView(territoryId: UUID()) { template in
        print("Selected: \(template.name)")
    }
}
