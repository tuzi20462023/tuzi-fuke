//
//  BackpackView.swift
//  tuzi-fuke (地球新主复刻版)
//
//  背包视图 - 显示玩家收集的物品
//  Created by AI Assistant on 2025/12/06.
//

import SwiftUI

// MARK: - 背包视图

struct BackpackView: View {
    // 使用真实数据
    @ObservedObject private var inventoryManager = InventoryManager.shared

    @State private var selectedItem: InventoryItem?

    var body: some View {
        NavigationStack {
            Group {
                if inventoryManager.isLoading && inventoryManager.items.isEmpty {
                    // 首次加载中
                    loadingView
                } else if inventoryManager.items.isEmpty {
                    // 空状态
                    emptyView
                } else {
                    // 有物品
                    VStack(spacing: 0) {
                        // 统计栏
                        statsBar

                        // 物品列表
                        itemList
                    }
                }
            }
            .navigationTitle("背包")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        #if DEBUG
                        // 调试菜单
                        Menu {
                            Button {
                                Task {
                                    let testItems = [
                                        LootItem(name: "wood", quantity: 50, icon: "tree.fill"),
                                        LootItem(name: "stone", quantity: 30, icon: "mountain.2.fill"),
                                        LootItem(name: "steel", quantity: 10, icon: "wrench.and.screwdriver.fill"),
                                        LootItem(name: "gold", quantity: 100, icon: "dollarsign.circle.fill")
                                    ]
                                    let success = await InventoryManager.shared.addItems(testItems)
                                    if success {
                                        print("✅ [Debug] 测试物品已添加")
                                    }
                                }
                            } label: {
                                Label("添加测试物品", systemImage: "plus.circle")
                            }

                            Button {
                                Task {
                                    let logs = await InventoryManager.shared.fetchLogs(limit: 10)
                                    print("📋 [Debug] 最近操作日志 (\(logs.count) 条):")
                                    for log in logs {
                                        print("  - \(log.operation.displayName) \(log.itemId) x\(log.quantityChange)")
                                    }
                                }
                            } label: {
                                Label("打印操作日志", systemImage: "doc.text")
                            }

                            Divider()

                            Button(role: .destructive) {
                                Task {
                                    // 清空背包（测试用）
                                    for item in InventoryManager.shared.items {
                                        _ = await InventoryManager.shared.removeItem(
                                            itemId: item.itemId,
                                            quantity: item.quantity,
                                            source: "debug_clear"
                                        )
                                    }
                                    print("🗑️ [Debug] 背包已清空")
                                }
                            } label: {
                                Label("清空背包", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ladybug")
                                .foregroundColor(.orange)
                        }
                        #endif

                        // 刷新按钮
                        Button {
                            Task {
                                await inventoryManager.refresh()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .rotationEffect(.degrees(inventoryManager.isLoading ? 360 : 0))
                                .animation(inventoryManager.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: inventoryManager.isLoading)
                        }
                        .disabled(inventoryManager.isLoading)
                    }
                }
            }
            .sheet(item: $selectedItem) { item in
                InventoryItemDetailSheet(item: item)
            }
            .onAppear {
                Task {
                    await inventoryManager.fetchInventory()
                }
            }
            .refreshable {
                await inventoryManager.fetchInventory()
            }
        }
    }

    // MARK: - 加载中视图

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("加载中...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 统计栏

    private var statsBar: some View {
        HStack(spacing: 24) {
            // 物品种类
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .foregroundColor(.secondary)
                Text("物品种类:")
                    .foregroundColor(.secondary)
                Text("\(inventoryManager.itemCount)")
                    .fontWeight(.semibold)
            }

            // 总数量
            HStack(spacing: 6) {
                Image(systemName: "number")
                    .foregroundColor(.secondary)
                Text("总数量:")
                    .foregroundColor(.secondary)
                Text("\(inventoryManager.totalQuantity)")
                    .fontWeight(.semibold)
            }

            Spacer()
        }
        .font(.subheadline)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
    }

    // MARK: - 物品列表

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(inventoryManager.items) { item in
                    InventoryItemRow(item: item)
                        .onTapGesture {
                            selectedItem = item
                        }

                    if item.id != inventoryManager.items.last?.id {
                        Divider()
                            .padding(.leading, 76)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - 空状态视图

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bag")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("背包空空如也")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("去探索发现物资吧！")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button {
                Task {
                    await inventoryManager.fetchInventory()
                }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
        .padding()
    }
}

// MARK: - 物品行（使用 InventoryItem）

struct InventoryItemRow: View {
    let item: InventoryItem

    /// 获取分类颜色
    private var categoryColor: Color {
        switch item.category {
        case .wood: return .green
        case .stone: return .gray
        case .metal: return .blue
        case .currency: return .yellow
        case .other: return .purple
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            // 左侧：圆形背景 + 图标
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 50, height: 50)

                Image(systemName: item.displayIcon)
                    .font(.system(size: 22))
                    .foregroundColor(categoryColor)
            }

            // 中间：物品名称
            Text(item.displayName)
                .font(.body)
                .fontWeight(.medium)

            Spacer()

            // 右侧：数量显示
            Text("x\(item.quantity)")
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.systemGray6))
                .cornerRadius(8)

            // 箭头提示可点击
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - 物品详情 Sheet（使用 InventoryItem）

struct InventoryItemDetailSheet: View {
    let item: InventoryItem
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var inventoryManager = InventoryManager.shared

    @State private var showingDiscardAlert = false

    /// 获取分类颜色
    private var categoryColor: Color {
        switch item.category {
        case .wood: return .green
        case .stone: return .gray
        case .metal: return .blue
        case .currency: return .yellow
        case .other: return .purple
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 大图标
                    ZStack {
                        Circle()
                            .fill(categoryColor.opacity(0.15))
                            .frame(width: 120, height: 120)

                        Image(systemName: item.displayIcon)
                            .font(.system(size: 50))
                            .foregroundColor(categoryColor)
                    }
                    .padding(.top, 20)

                    // 物品名称和分类
                    VStack(spacing: 8) {
                        Text(item.displayName)
                            .font(.title)
                            .fontWeight(.bold)

                        Text(item.category.displayName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(categoryColor.opacity(0.15))
                            .cornerRadius(8)
                    }

                    // 数量显示
                    HStack {
                        Text("当前数量")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("x\(item.quantity)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(categoryColor)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // 物品描述
                    VStack(alignment: .leading, spacing: 12) {
                        Text("物品描述")
                            .font(.headline)

                        Text(item.description)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // 操作按钮
                    VStack(spacing: 12) {
                        Button {
                            Task {
                                let success = await inventoryManager.useItem(itemId: item.itemId, quantity: 1)
                                if success {
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "hand.tap.fill")
                                Text("使用")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(categoryColor)
                            .cornerRadius(12)
                        }

                        Button {
                            showingDiscardAlert = true
                        } label: {
                            HStack {
                                Image(systemName: "trash.fill")
                                Text("丢弃")
                            }
                            .font(.headline)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("物品详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .alert("确认丢弃", isPresented: $showingDiscardAlert) {
                Button("取消", role: .cancel) {}
                Button("丢弃", role: .destructive) {
                    Task {
                        let success = await inventoryManager.removeItem(
                            itemId: item.itemId,
                            quantity: item.quantity,
                            source: "discard"
                        )
                        if success {
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("确定要丢弃全部 \(item.quantity) 个 \(item.displayName) 吗？此操作无法撤销。")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - 预览

#Preview("背包") {
    BackpackView()
}
