//
//  TerritoryBuildingsView.swift
//  tuzi-fuke
//
//  DAY8: 领地建筑列表 - 显示某个领地内所有已建造的建筑
//  Created by AI Assistant on 2025/12/02.
//

import SwiftUI
import CoreLocation
import Combine

struct TerritoryBuildingsView: View {
    let territory: Territory  // 完整的领地对象

    // ✅ 使用 @ObservedObject 引用单例
    @ObservedObject private var buildingManager = BuildingManager.shared

    // ✅ 使用 .sheet 方式，参考原项目架构，避免首次加载白屏
    @State private var showBuildingList = false
    @State private var selectedTemplateForPlacement: BuildingTemplate?

    @Environment(\.dismiss) private var dismiss

    // 当前领地的建筑
    private var territoryBuildings: [PlayerBuilding] {
        buildingManager.playerBuildings.filter { $0.territoryId == territory.id }
    }

    var body: some View {
        NavigationView {
            VStack {
                if territoryBuildings.isEmpty {
                    emptyView
                } else {
                    buildingsList
                }
            }
            .navigationTitle(territory.name ?? "我的领地")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showBuildingList = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .refreshable {
                await buildingManager.fetchPlayerBuildings(territoryId: territory.id)
            }
        }
        .task {
            await buildingManager.fetchPlayerBuildings(territoryId: territory.id)
        }
        // ✅ 使用 .sheet 打开建筑列表（参考原项目）
        .sheet(isPresented: $showBuildingList) {
            BuildingListView(territoryId: territory.id) { template in
                selectedTemplateForPlacement = template
                showBuildingList = false
            }
        }
        // ✅ 选择建筑后打开放置界面
        .sheet(item: $selectedTemplateForPlacement) { template in
            BuildingPlacementView(
                template: template,
                territory: territory
            )
        }
    }

    // MARK: - 空视图

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "building.2.crop.circle")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("这个领地还没有建筑")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("点击右上角 + 开始建造")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button {
                showBuildingList = true
            } label: {
                Label("开始建造", systemImage: "hammer.fill")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 建筑列表

    private var buildingsList: some View {
        List {
            // ✅ 只显示当前领地的建筑
            ForEach(territoryBuildings) { building in
                NavigationLink {
                    BuildingDetailView(building: building)
                } label: {
                    PlayerBuildingRow(building: building)
                }
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - 玩家建筑行

struct PlayerBuildingRow: View {
    let building: PlayerBuilding
    // ✅ 使用 @ObservedObject 引用单例
    @ObservedObject private var buildingManager = BuildingManager.shared

    // 用于刷新倒计时
    @State private var currentTime = Date()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            // 图标
            buildingIcon

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(building.buildingName)
                        .font(.headline)

                    Text("Lv.\(building.level)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // 状态
                statusView
            }

            Spacer()

            // 耐久度
            if building.status == .active {
                durabilityView
            }
        }
        .padding(.vertical, 8)
        .onReceive(timer) { _ in
            if building.status == .constructing {
                currentTime = Date()
            }
        }
    }

    // MARK: - 图标

    private var buildingIcon: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.15))
                .frame(width: 50, height: 50)

            if let template = buildingManager.getTemplate(for: building.buildingTemplateKey) {
                Image(systemName: template.icon)
                    .font(.system(size: 24))
                    .foregroundColor(statusColor)
            } else {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 24))
                    .foregroundColor(statusColor)
            }

            // 建造中动画
            if building.status == .constructing {
                Circle()
                    .stroke(statusColor, lineWidth: 3)
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(Double(currentTime.timeIntervalSince1970.truncatingRemainder(dividingBy: 360))))
                    .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: currentTime)
            }
        }
    }

    // MARK: - 状态视图

    @ViewBuilder
    private var statusView: some View {
        switch building.status {
        case .constructing:
            VStack(alignment: .leading, spacing: 2) {
                // 进度条
                ProgressView(value: building.buildProgress())
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))

                // 剩余时间
                Text("剩余: \(building.formattedRemainingTime)")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }

        case .active:
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("运行中")
                    .font(.caption)
                    .foregroundColor(.green)
            }

        case .damaged:
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("需要维修")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

        case .inactive:
            HStack {
                Image(systemName: "pause.circle.fill")
                    .foregroundColor(.gray)
                Text("已停用")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }

    // MARK: - 耐久度

    private var durabilityView: some View {
        VStack(spacing: 2) {
            Text("\(building.durability)/\(building.durabilityMax)")
                .font(.caption2)
                .foregroundColor(.secondary)

            // 耐久度条
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 4)
                        .cornerRadius(2)

                    Rectangle()
                        .fill(durabilityColor)
                        .frame(width: geometry.size.width * durabilityPercentage, height: 4)
                        .cornerRadius(2)
                }
            }
            .frame(width: 40, height: 4)
        }
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
}

// MARK: - Preview

#Preview {
    TerritoryBuildingsView(
        territory: Territory(
            id: UUID(),
            ownerId: UUID(),
            name: "我的领地",
            type: .circle,
            centerLatitude: 31.2304,
            centerLongitude: 121.4737,
            radius: 100
        )
    )
}
