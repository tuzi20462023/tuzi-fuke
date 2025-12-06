//
//  ExploreTabView.swift
//  tuzi-fuke
//
//  探索Tab - POI发现和探索模式入口
//  首次进入时触发 MapKit 搜索，避免启动白屏
//  Created by AI Assistant on 2025/12/05.
//

import SwiftUI
import CoreLocation
import MapKit
import Supabase

/// 探索Tab - POI 列表和探索模式
struct ExploreTabView: View {
    @ObservedObject private var poiManager = POIManager.shared
    @ObservedObject private var explorationManager = ExplorationManager.shared
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var authManager = AuthManager.shared

    @State private var isInitializing = false
    @State private var initializationStatus = ""
    @State private var hasInitialized = false
    @State private var showExplorationView = false
    @State private var selectedSegment = 0  // 0: POI列表, 1: 探索模式

    var body: some View {
        NavigationView {
            ZStack {
                // 背景色
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // 顶部分段控制器
                    Picker("", selection: $selectedSegment) {
                        Text("附近地点").tag(0)
                        Text("探索模式").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    // 内容区域
                    if selectedSegment == 0 {
                        poiListContent
                    } else {
                        explorationContent
                    }
                }
            }
            .navigationTitle("探索")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            initializePOIIfNeeded()
        }
    }

    // MARK: - POI 列表内容

    private var poiListContent: some View {
        Group {
            if isInitializing {
                // 初始化中
                initializingView
            } else if poiManager.cachedPOIs.isEmpty {
                // 没有 POI
                emptyPOIView
            } else {
                // POI 列表
                poiListView
            }
        }
    }

    // MARK: - 初始化中视图

    private var initializingView: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text(initializationStatus)
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Text("首次使用需要搜索附近地点\n请稍候...")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
    }

    // MARK: - 空状态视图

    private var emptyPOIView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "mappin.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("附近没有发现地点")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("尝试移动到其他位置后刷新")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button(action: {
                Task {
                    await refreshPOIs()
                }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("重新搜索")
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

    // MARK: - POI 列表视图

    private var poiListView: some View {
        VStack(spacing: 0) {
            // 统计头部
            poiStatsHeader
                .padding()

            // 类型筛选
            poiTypeFilter
                .padding(.horizontal)

            // POI 列表
            List {
                ForEach(poiManager.filteredPOIs) { poi in
                    POIListCard(poi: poi, isDiscovered: poiManager.discoveredPOIIds.contains(poi.id))
                }
            }
            .listStyle(.plain)
            .refreshable {
                await refreshPOIs()
            }
        }
    }

    // MARK: - POI 统计头部

    private var poiStatsHeader: some View {
        HStack(spacing: 16) {
            // POI 总数
            VStack(spacing: 4) {
                Text("\(poiManager.cachedPOIs.count)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                Text("附近地点")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)

            // 已发现数
            VStack(spacing: 4) {
                Text("\(poiManager.discoveredPOIIds.count)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
                Text("已发现")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - POI 类型筛选

    private var poiTypeFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(POIType.allCases, id: \.self) { type in
                    POITypeChip(
                        type: type,
                        count: poiManager.countByType(type),
                        isSelected: poiManager.selectedTypes.contains(type)
                    ) {
                        poiManager.toggleTypeFilter(type)
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

    // MARK: - 初始化 POI

    private func initializePOIIfNeeded() {
        // 如果已经初始化过，或者正在初始化，跳过
        guard !hasInitialized && !isInitializing else { return }

        // 如果已经有缓存的 POI，不需要重新初始化
        if !poiManager.cachedPOIs.isEmpty {
            hasInitialized = true
            return
        }

        Task {
            await initializePOI()
        }
    }

    private func initializePOI() async {
        guard let userId = authManager.currentUser?.id else {
            appLog(.warning, category: "探索Tab", message: "未登录，跳过 POI 初始化")
            return
        }

        isInitializing = true
        initializationStatus = "正在获取位置..."

        appLog(.info, category: "探索Tab", message: "开始 POI 初始化流程...")

        // 1. 确保有位置
        if locationManager.currentLocation == nil {
            locationManager.requestLocationPermission()
            try? await Task.sleep(nanoseconds: 500_000_000)
            try? await locationManager.startLocationUpdates()

            // 等待位置（最多 5 秒）
            for _ in 0..<10 {
                if locationManager.currentLocation != nil { break }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        guard let location = locationManager.currentLocation else {
            appLog(.error, category: "探索Tab", message: "无法获取位置")
            initializationStatus = "无法获取位置"
            isInitializing = false
            return
        }

        appLog(.info, category: "探索Tab", message: "位置获取成功: (\(location.coordinate.latitude), \(location.coordinate.longitude))")

        // 2. 搜索附近 POI 并提交候选
        initializationStatus = "正在搜索附近地点..."

        let candidateCount = await searchAndSubmitPOICandidates(location: location, userId: userId)
        appLog(.info, category: "探索Tab", message: "提交了 \(candidateCount) 个 POI 候选")

        // 3. 调用 Edge Function 生成 POI（如果有候选）
        if candidateCount > 0 {
            initializationStatus = "正在生成探索点..."
            await callGeneratePOIEdgeFunction(userId: userId, location: location)
        }

        // 4. 加载 POI
        initializationStatus = "正在加载探索点..."
        await poiManager.updatePOICacheWithRPC(location: location)
        await poiManager.loadDiscoveredPOIs(userId: userId)

        hasInitialized = true
        isInitializing = false

        appLog(.success, category: "探索Tab", message: "POI 初始化完成，共 \(poiManager.cachedPOIs.count) 个 POI")
    }

    // MARK: - 搜索并提交 POI 候选

    private func searchAndSubmitPOICandidates(location: CLLocation, userId: UUID) async -> Int {
        var totalCount = 0
        var seenKeys: Set<String> = []

        // 将 GPS 坐标转换为 GCJ-02（MapKit 使用 GCJ-02）
        let gcjCoord = CoordinateConverter.wgs84ToGcj02(location.coordinate)

        // 旅行风格的搜索配置
        let searchConfigs: [(type: String, keywords: [String], radius: Double)] = [
            ("cafe", ["咖啡", "咖啡店", "星巴克", "瑞幸"], 1000),
            ("bookstore", ["书店", "书城", "新华书店"], 1500),
            ("park", ["公园", "广场", "花园"], 2000),
            ("restaurant", ["餐厅", "美食", "网红店"], 1000),
            ("attraction", ["景点", "博物馆", "展览馆"], 2500),
            ("mall", ["商场", "购物中心", "万达"], 2000),
            ("convenience_store", ["便利店", "7-11", "全家"], 800),
            ("gym", ["健身房", "游泳馆", "运动"], 1500),
        ]

        for config in searchConfigs {
            for keyword in config.keywords {
                initializationStatus = "搜索: \(keyword)..."

                let results = await searchMapKit(
                    keyword: keyword,
                    center: gcjCoord,
                    radius: config.radius
                )

                for result in results {
                    // 生成网格 key（用于去重）
                    let gridKey = generateGridKey(name: result.name, lat: result.latitude, lon: result.longitude)

                    if !seenKeys.contains(gridKey) {
                        seenKeys.insert(gridKey)

                        // 提交到数据库
                        let success = await submitCandidate(
                            name: result.name,
                            poiType: config.type,
                            address: result.address,
                            latitude: result.latitude,
                            longitude: result.longitude,
                            gridKey: gridKey,
                            userId: userId
                        )

                        if success {
                            totalCount += 1
                        }
                    }
                }

                // 避免请求过快
                try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1秒
            }
        }

        return totalCount
    }

    // MARK: - MapKit 搜索

    private func searchMapKit(keyword: String, center: CLLocationCoordinate2D, radius: Double) async -> [(name: String, address: String?, latitude: Double, longitude: Double)] {

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = keyword
        request.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )

        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()
            appLog(.debug, category: "探索Tab", message: "搜索 '\(keyword)': 找到 \(response.mapItems.count) 个结果")

            return response.mapItems.compactMap { item -> (String, String?, Double, Double)? in
                guard let name = item.name, !name.isEmpty else { return nil }

                // MapKit 返回的坐标是 GCJ-02，直接使用
                return (
                    name,
                    item.placemark.title,
                    item.placemark.coordinate.latitude,
                    item.placemark.coordinate.longitude
                )
            }
        } catch {
            appLog(.warning, category: "探索Tab", message: "搜索 '\(keyword)' 失败: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - 提交候选到数据库

    private func submitCandidate(name: String, poiType: String, address: String?, latitude: Double, longitude: Double, gridKey: String, userId: UUID) async -> Bool {

        return await withCheckedContinuation { continuation in
            Task.detached {
                do {
                    let supabase = await SupabaseManager.shared.client

                    struct CandidateInsert: Encodable, Sendable {
                        let name: String
                        let poi_type: String
                        let address: String?
                        let latitude: Double
                        let longitude: Double
                        let grid_key: String
                        let submitted_by: String
                    }

                    let insertData = CandidateInsert(
                        name: name,
                        poi_type: poiType,
                        address: address,
                        latitude: latitude,
                        longitude: longitude,
                        grid_key: gridKey,
                        submitted_by: userId.uuidString
                    )

                    try await supabase.database
                        .from("mapkit_poi_candidates")
                        .insert([insertData])
                        .select()
                        .execute()

                    continuation.resume(returning: true)
                } catch {
                    // 忽略重复 key 错误
                    let errorStr = String(describing: error).lowercased()
                    if errorStr.contains("unique") || errorStr.contains("duplicate") || errorStr.contains("23505") {
                        continuation.resume(returning: false)
                        return
                    }

                    await MainActor.run {
                        appLog(.error, category: "探索Tab", message: "提交候选失败: \(error.localizedDescription)")
                    }
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // MARK: - 调用 Edge Function 生成 POI

    private func callGeneratePOIEdgeFunction(userId: UUID, location: CLLocation) async {
        let gcjCoord = CoordinateConverter.wgs84ToGcj02(location.coordinate)

        // 构建请求 URL
        let supabaseUrl = SupabaseConfig.supabaseURL.absoluteString
        let functionUrl = "\(supabaseUrl)/functions/v1/process-poi-candidates"

        guard let url = URL(string: functionUrl) else {
            appLog(.error, category: "探索Tab", message: "无效的 Edge Function URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(SupabaseConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "user_id": userId.uuidString,
            "latitude": gcjCoord.latitude,
            "longitude": gcjCoord.longitude,
            "radius_meters": 1000
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if (200...299).contains(httpResponse.statusCode) {
                    appLog(.success, category: "探索Tab", message: "Edge Function 调用成功")

                    if let responseStr = String(data: data, encoding: .utf8) {
                        appLog(.debug, category: "探索Tab", message: "响应: \(responseStr.prefix(200))")
                    }
                } else {
                    appLog(.warning, category: "探索Tab", message: "Edge Function 返回状态码: \(httpResponse.statusCode)")
                }
            }
        } catch {
            appLog(.error, category: "探索Tab", message: "调用 Edge Function 失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 刷新 POI

    private func refreshPOIs() async {
        guard let location = locationManager.currentLocation,
              let userId = authManager.currentUser?.id else { return }

        await poiManager.updatePOICacheWithRPC(location: location)
        await poiManager.loadDiscoveredPOIs(userId: userId)
    }

    // MARK: - 辅助方法

    private func generateGridKey(name: String, lat: Double, lon: Double) -> String {
        let latStr = String(format: "%.3f", lat)
        let lonStr = String(format: "%.3f", lon)
        return "\(name)_\(latStr)_\(lonStr)"
    }
}

// MARK: - POI 类型筛选标签

struct POITypeChip: View {
    let type: POIType
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: type.iconName)
                    .font(.caption)
                Text("\(type.displayName)(\(count))")
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color(hex: type.color) : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
    }
}

// MARK: - POI 列表卡片

struct POIListCard: View {
    let poi: POI
    let isDiscovered: Bool

    var body: some View {
        HStack(spacing: 12) {
            // 图标
            ZStack {
                Circle()
                    .fill(Color(hex: poi.type.color).opacity(0.15))
                    .frame(width: 50, height: 50)

                Image(systemName: poi.type.iconName)
                    .font(.system(size: 24))
                    .foregroundColor(Color(hex: poi.type.color))
            }

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(poi.name)
                        .font(.headline)

                    if isDiscovered {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }

                HStack(spacing: 12) {
                    Label(poi.type.displayName, systemImage: poi.type.iconName)
                    Label("资源: \(poi.remainingItems)/\(poi.totalItems)", systemImage: "cube.box")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .opacity(isDiscovered ? 0.6 : 1.0)
    }
}

// MARK: - Preview

#Preview {
    ExploreTabView()
}
