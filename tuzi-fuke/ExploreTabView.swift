//
//  ExploreTabView.swift
//  tuzi-fuke
//
//  探索Tab - 已发现POI历史 + 探索模式入口
//  "已发现"展示用户历史上发现过的所有POI（从 user_poi_discoveries 表加载）
//  "探索模式"用于开始新的探索任务
//  Created by AI Assistant on 2025/12/05.
//

import SwiftUI
import CoreLocation
import MapKit
import Supabase

/// 已发现POI记录（用于展示历史）
struct DiscoveredPOIRecord: Identifiable, Decodable {
    let id: UUID
    let poi_id: UUID?
    let poi_name: String?
    let poi_type: String?
    let latitude: Double?
    let longitude: Double?
    let discovered_at: Date?
    let resources_collected: Int?

    /// 获取POI类型枚举
    var poiType: POIType {
        guard let typeStr = poi_type else { return .other }
        return POIType(rawValue: typeStr) ?? .other
    }
}

/// 探索Tab - 已发现历史 + 探索模式
struct ExploreTabView: View {
    @ObservedObject private var explorationManager = ExplorationManager.shared
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var authManager = AuthManager.shared

    @State private var isLoading = false
    @State private var discoveredPOIs: [DiscoveredPOIRecord] = []
    @State private var selectedSegment = 0  // 0: 已发现, 1: 探索模式
    @State private var selectedType: POIType? = nil  // 筛选类型

    var body: some View {
        NavigationView {
            ZStack {
                // 背景色
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // 顶部分段控制器
                    Picker("", selection: $selectedSegment) {
                        Text("已发现").tag(0)
                        Text("探索模式").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    // 内容区域
                    if selectedSegment == 0 {
                        discoveredListContent
                    } else {
                        explorationContent
                    }
                }
            }
            .navigationTitle("探索")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            loadDiscoveredPOIs()
        }
    }

    // MARK: - 已发现列表内容

    private var discoveredListContent: some View {
        Group {
            if isLoading {
                loadingView
            } else if discoveredPOIs.isEmpty {
                emptyDiscoveredView
            } else {
                discoveredListView
            }
        }
    }

    // MARK: - 加载中视图

    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("加载中...")
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: - 空状态视图

    private var emptyDiscoveredView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "figure.walk.motion")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("还没有发现任何地点")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("开始探索，走近附近的咖啡馆、书店、公园等地点\n即可将它们添加到已发现列表")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: {
                selectedSegment = 1  // 切换到探索模式
            }) {
                HStack {
                    Image(systemName: "figure.walk")
                    Text("开始探索")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding()
    }

    // MARK: - 已发现列表视图

    private var discoveredListView: some View {
        VStack(spacing: 0) {
            // 统计头部
            discoveredStatsHeader
                .padding()

            // 类型筛选
            discoveredTypeFilter
                .padding(.horizontal)

            // 列表
            List {
                ForEach(filteredDiscoveredPOIs) { record in
                    DiscoveredPOICard(record: record)
                }
            }
            .listStyle(.plain)
            .refreshable {
                loadDiscoveredPOIs()
            }
        }
    }

    /// 根据筛选类型过滤
    private var filteredDiscoveredPOIs: [DiscoveredPOIRecord] {
        guard let selectedType = selectedType else {
            return discoveredPOIs
        }
        return discoveredPOIs.filter { $0.poiType == selectedType }
    }

    // MARK: - 统计头部

    private var discoveredStatsHeader: some View {
        HStack(spacing: 16) {
            // 已发现总数
            VStack(spacing: 4) {
                Text("\(discoveredPOIs.count)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
                Text("已发现地点")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)

            // 收集资源总数
            VStack(spacing: 4) {
                Text("\(totalResourcesCollected)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
                Text("收集资源")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
    }

    private var totalResourcesCollected: Int {
        discoveredPOIs.compactMap { $0.resources_collected }.reduce(0, +)
    }

    // MARK: - 类型筛选

    private var discoveredTypeFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // 全部按钮
                Button(action: { selectedType = nil }) {
                    Text("全部(\(discoveredPOIs.count))")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedType == nil ? Color.blue : Color(.systemGray5))
                        .foregroundColor(selectedType == nil ? .white : .primary)
                        .cornerRadius(16)
                }

                // 各类型按钮
                ForEach(POIType.allCases, id: \.self) { type in
                    let count = discoveredPOIs.filter { $0.poiType == type }.count
                    if count > 0 {
                        Button(action: { selectedType = type }) {
                            HStack(spacing: 4) {
                                Image(systemName: type.iconName)
                                    .font(.caption)
                                Text("\(type.displayName)(\(count))")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedType == type ? Color(hex: type.color) : Color(.systemGray5))
                            .foregroundColor(selectedType == type ? .white : .primary)
                            .cornerRadius(16)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - 探索模式内容

    private var explorationContent: some View {
        ExplorationView(
            explorationManager: explorationManager,
            locationManager: locationManager,
            authManager: authManager
        )
    }

    // MARK: - 加载已发现POI历史

    private func loadDiscoveredPOIs() {
        guard let userId = authManager.currentUser?.id else {
            appLog(.warning, category: "探索Tab", message: "未登录，无法加载已发现POI")
            return
        }

        isLoading = true

        Task {
            do {
                let supabase = SupabaseManager.shared.client

                // 从 user_poi_discoveries 表加载已发现的POI历史
                let response = try await supabase.database
                    .from("user_poi_discoveries")
                    .select("*")
                    .eq("user_id", value: userId.uuidString)
                    .order("discovered_at", ascending: false)  // 最新发现的排在前面
                    .execute()

                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                let records = try decoder.decode([DiscoveredPOIRecord].self, from: response.data)

                await MainActor.run {
                    self.discoveredPOIs = records
                    self.isLoading = false
                    appLog(.success, category: "探索Tab", message: "✅ 已加载 \(records.count) 个已发现POI历史")
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    appLog(.error, category: "探索Tab", message: "❌ 加载已发现POI失败: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - 已发现POI卡片

struct DiscoveredPOICard: View {
    let record: DiscoveredPOIRecord

    var body: some View {
        HStack(spacing: 12) {
            // 图标
            ZStack {
                Circle()
                    .fill(Color(hex: record.poiType.color).opacity(0.15))
                    .frame(width: 50, height: 50)

                Image(systemName: record.poiType.iconName)
                    .font(.system(size: 24))
                    .foregroundColor(Color(hex: record.poiType.color))
            }

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(record.poi_name ?? "未知地点")
                        .font(.headline)

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }

                HStack(spacing: 12) {
                    Label(record.poiType.displayName, systemImage: record.poiType.iconName)

                    if let collected = record.resources_collected, collected > 0 {
                        Label("收集: \(collected)", systemImage: "cube.box.fill")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)

                // 发现时间
                if let discoveredAt = record.discovered_at {
                    Text("发现于 \(discoveredAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview {
    ExploreTabView()
}
