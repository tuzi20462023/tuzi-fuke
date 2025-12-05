//
//  TerritoryTabView.swift
//  tuzi-fuke
//
//  领地Tab - 领地列表和建筑管理入口
//  从非MapKit页面打开建筑相关弹窗，避免白屏
//  Created by AI Assistant on 2025/12/05.
//

import SwiftUI

/// 领地Tab - 显示我的领地列表，点击进入建筑管理
struct TerritoryTabView: View {
    @ObservedObject private var territoryManager = TerritoryManager.shared
    @ObservedObject private var authManager = AuthManager.shared
    @ObservedObject private var buildingManager = BuildingManager.shared

    @State private var isLoading = false
    @State private var selectedTerritory: Territory?

    var body: some View {
        NavigationView {
            ZStack {
                // 背景色
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // 顶部统计
                    statsHeader
                        .padding()

                    // 领地列表
                    if isLoading {
                        Spacer()
                        ProgressView("加载中...")
                        Spacer()
                    } else if territoryManager.territories.isEmpty {
                        Spacer()
                        emptyView
                        Spacer()
                    } else {
                        territoryList
                    }
                }
            }
            .navigationTitle("我的领地")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            loadTerritories()
        }
        // ✅ 从领地Tab（无MapKit）弹出 sheet，不会白屏
        .sheet(item: $selectedTerritory) { territory in
            TerritoryBuildingsView(territory: territory)
        }
    }

    // MARK: - 统计头部

    private var statsHeader: some View {
        HStack(spacing: 20) {
            // 领地总数
            VStack(spacing: 4) {
                Text("\(territoryManager.territories.count)")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
                Text("领地总数")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)

            // 总面积
            VStack(spacing: 4) {
                Text(formattedTotalArea)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                Text("总面积")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - 空状态

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "map")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("还没有领地")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("在地图标签中圈占一块领地吧！")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 领地列表

    private var territoryList: some View {
        List {
            ForEach(territoryManager.territories) { territory in
                TerritoryCard(
                    territory: territory,
                    buildingCount: buildingManager.playerBuildings.filter { $0.territoryId == territory.id }.count
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedTerritory = territory
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await refreshTerritories()
        }
    }

    // MARK: - Helpers

    private var formattedTotalArea: String {
        let total = territoryManager.territories.reduce(0.0) { $0 + $1.area }
        if total >= 1_000_000 {
            return String(format: "%.1f km²", total / 1_000_000)
        } else {
            return String(format: "%.0f m²", total)
        }
    }

    private func loadTerritories() {
        guard !isLoading else { return }
        isLoading = true

        Task {
            // ✅ 无论有没有位置，都要加载"我的领地"
            await territoryManager.refreshTerritories(at: LocationManager.shared.currentLocation)
            await buildingManager.fetchAllPlayerBuildings()
            isLoading = false
        }
    }

    private func refreshTerritories() async {
        // ✅ 无论有没有位置，都要加载"我的领地"
        await territoryManager.refreshTerritories(at: LocationManager.shared.currentLocation)
        await buildingManager.fetchAllPlayerBuildings()
    }
}

// MARK: - 领地卡片

struct TerritoryCard: View {
    let territory: Territory
    let buildingCount: Int

    var body: some View {
        HStack(spacing: 12) {
            // 图标
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 50, height: 50)

                Image(systemName: "map.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green)
            }

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(territory.name ?? "领地 #\(territory.id.uuidString.prefix(4))")
                    .font(.headline)

                HStack(spacing: 12) {
                    Label(formattedArea, systemImage: "square.dashed")
                    Label("\(buildingCount) 建筑", systemImage: "building.2")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var formattedArea: String {
        let area = territory.area
        if area >= 10000 {
            return String(format: "%.2f 公顷", area / 10000)
        } else {
            return String(format: "%.0f m²", area)
        }
    }
}

// MARK: - Preview

#Preview {
    TerritoryTabView()
}
