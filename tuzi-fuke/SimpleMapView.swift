import SwiftUI
import MapKit
import UIKit  // 用于触觉反馈

/// 简易地图视图 - SwiftUI 层封装
struct SimpleMapView: View {

    // MARK: - 环境对象
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var territoryManager: TerritoryManager
    @ObservedObject var authManager: AuthManager
    @ObservedObject var explorationManager: ExplorationManager
    @StateObject private var poiManager = POIManager.shared

    // MARK: - 回调
    var switchToDebugTab: (() -> Void)?

    // MARK: - 状态
    @State private var shouldCenterOnUser = false
    @State private var showLoginAlert = false
    @State private var showCollisionAlert = false
    @State private var collisionAlertMessage = ""
    @State private var showPOIFilter = false
    @State private var showExplorationResult = false
    @State private var explorationResult: ExplorationResult?

    // MARK: - 建筑系统状态
    @State private var showTerritoryPicker = false
    @State private var selectedTerritoryForBuilding: Territory?
    @State private var showBuildingsView = false
    @StateObject private var buildingManager = BuildingManager.shared

    // MARK: - 实时碰撞检测定时器
    @State private var collisionCheckTimer: Timer?
    private let collisionCheckInterval: TimeInterval = 5.0  // 每5秒检查一次

    // MARK: - POI 检测定时器
    @State private var poiCheckTimer: Timer?
    private let poiCheckInterval: TimeInterval = 2.0  // 每2秒检查一次POI

    // MARK: - 触觉反馈生成器
    private let notificationFeedback = UINotificationFeedbackGenerator()
    private let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)

    // MARK: - Body

    var body: some View {
        ZStack {
            // 地图
            MapViewRepresentable(
                locationManager: locationManager,
                territoryManager: territoryManager,
                buildingManager: buildingManager,
                poiManager: poiManager,
                shouldCenterOnUser: $shouldCenterOnUser
            )
            .ignoresSafeArea(edges: .bottom) // 只忽略底部，保留顶部导航栏空间

            // 控制按钮层（底部三按钮布局：圈地 - 定位 - 探索）
            VStack {
                Spacer()

                // 右侧工具按钮（POI筛选 + 建筑）
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        // 建筑按钮
                        Button(action: {
                            if authManager.currentUser != nil {
                                if territoryManager.territories.isEmpty {
                                    // 没有领地，提示需要先圈地
                                    collisionAlertMessage = "请先圈地再建造建筑"
                                    showCollisionAlert = true
                                } else if territoryManager.territories.count == 1 {
                                    // 只有一个领地，直接进入
                                    selectedTerritoryForBuilding = territoryManager.territories.first
                                    showBuildingsView = true
                                } else {
                                    // 多个领地，显示选择器
                                    showTerritoryPicker = true
                                }
                            } else {
                                showLoginAlert = true
                            }
                        }) {
                            Image(systemName: "hammer.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.orange)
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }

                        // POI 筛选按钮
                        Button(action: {
                            showPOIFilter.toggle()
                        }) {
                            ZStack {
                                Image(systemName: "building.2.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(poiManager.filteredPOIs.isEmpty ? Color.gray : Color.purple)
                                    .clipShape(Circle())
                                    .shadow(radius: 4)

                                // POI 数量角标
                                if !poiManager.filteredPOIs.isEmpty {
                                    Text("\(poiManager.filteredPOIs.count)")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .padding(4)
                                        .background(Color.red)
                                        .clipShape(Circle())
                                        .offset(x: 16, y: -16)
                                }
                            }
                        }
                    }
                    .padding(.trailing, 16)
                }
                .padding(.bottom, 8)

                // 底部三按钮：圈地 - 定位 - 探索
                HStack(spacing: 20) {
                    // 圈地按钮（左）
                    walkingClaimButton
                        .disabled(explorationManager.isExploring)
                        .opacity(explorationManager.isExploring ? 0.5 : 1.0)

                    // 定位按钮（中心，黄色圆形）
                    Button(action: {
                        shouldCenterOnUser = true
                    }) {
                        Image(systemName: "location.fill")
                            .font(.title)
                            .foregroundColor(.black)
                            .frame(width: 60, height: 60)
                            .background(Color.yellow)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }

                    // 探索按钮（右）
                    explorationButton
                        .disabled(locationManager.isTracking)
                        .opacity(locationManager.isTracking ? 0.5 : 1.0)
                }
                .padding(.bottom, 100)
            }

            // 状态信息层
            VStack {
                // 顶部状态栏
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if let location = locationManager.currentLocation {
                            Text("纬度: \(location.coordinate.latitude, specifier: "%.6f")")
                                .font(.caption)
                            Text("经度: \(location.coordinate.longitude, specifier: "%.6f")")
                                .font(.caption)
                            Text("精度: ±\(location.horizontalAccuracy, specifier: "%.1f")m")
                                .font(.caption)
                        } else {
                            Text("等待定位...")
                                .font(.caption)
                        }

                        // 领地数量
                        Text("我的领地: \(territoryManager.territories.count) 块")
                            .font(.caption)
                            .foregroundColor(.green)

                        // 附近领地
                        if !territoryManager.nearbyTerritories.isEmpty {
                            Text("附近领地: \(territoryManager.nearbyTerritories.count) 块")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }

                        // 附近 POI
                        if !poiManager.filteredPOIs.isEmpty {
                            Text("附近POI: \(poiManager.filteredPOIs.count) 个")
                                .font(.caption)
                                .foregroundColor(.purple)
                        }
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .foregroundColor(.white)
                    .cornerRadius(8)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8) // 导航栏下方，不需要那么大的 padding

                // 碰撞警告卡片（参考源项目 MapWarningsView）
                if let warning = locationManager.collisionWarning, locationManager.isTracking {
                    collisionWarningCard(message: warning)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.3), value: locationManager.collisionWarning)
                }

                Spacer()

                // 提示信息
                if !locationManager.isTracking && territoryManager.territories.isEmpty && !explorationManager.isExploring {
                    Text("点击左下角按钮开始行走圈地")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                        .padding(.bottom, 160)
                }

                // 行走圈地状态信息
                if locationManager.isTracking {
                    trackingStatusOverlay
                        .padding(.bottom, 160)
                }

                // 探索状态信息
                if explorationManager.isExploring {
                    explorationStatusOverlay
                        .padding(.bottom, 160)
                }
            }

            // 圈地确认弹窗（长按圈地）
            if territoryManager.showClaimConfirmation {
                claimConfirmationOverlay
            }

            // 行走圈地确认弹窗
            if locationManager.isPathClosed && locationManager.isTracking {
                walkingClaimConfirmationOverlay
            }

            // 圈地状态提示
            if case .success = territoryManager.claimingState {
                successOverlay
            }

            // POI 发现弹窗
            if poiManager.showDiscoveryAlert, let poi = poiManager.lastDiscoveredPOI {
                poiDiscoveryOverlay(poi: poi)
            }
        }
        .alert("需要登录", isPresented: $showLoginAlert) {
            Button("去登录") {
                switchToDebugTab?()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("圈地功能需要先登录账号，是否前往登录？")
        }
        .alert("碰撞违规", isPresented: $showCollisionAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(collisionAlertMessage)
        }
        // 领地选择器（多个领地时）
        .sheet(isPresented: $showTerritoryPicker) {
            territoryPickerSheet
        }
        // 建筑管理视图
        .sheet(isPresented: $showBuildingsView) {
            if let territory = selectedTerritoryForBuilding {
                TerritoryBuildingsView(territory: territory)
            }
        }
        .sheet(isPresented: $showPOIFilter) {
            POIFilterSheet(poiManager: poiManager)
        }
        .sheet(isPresented: $showExplorationResult) {
            if let result = explorationResult {
                ExplorationResultSheet(result: result) {
                    showExplorationResult = false
                    explorationResult = nil
                }
            }
        }
        .onAppear {
            // 请求定位权限并开始更新
            locationManager.requestLocationPermission()
            Task {
                try? await locationManager.startLocationUpdates()

                // 首次定位后居中并查询附近领地和POI
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    shouldCenterOnUser = true

                    // 查询领地数据和 POI 数据
                    Task {
                        if let location = locationManager.currentLocation {
                            await territoryManager.refreshTerritories(at: location)
                        }
                    }

                    // 加载建筑数据（优先，不阻塞）
                    Task {
                        await buildingManager.fetchBuildingTemplates()
                        await buildingManager.fetchAllPlayerBuildings()
                    }

                    // POI 搜索放到独立 Task，不阻塞 UI
                    Task.detached(priority: .background) {
                        if let location = await MainActor.run(body: { locationManager.currentLocation }) {
                            // 使用 onLocationReady 触发完整的 POI 流程
                            // 包括: 搜索MapKit → 提交候选 → 创建POI → 加载已发现 → 更新缓存
                            if let userId = await MainActor.run(body: { authManager.currentUser?.id }) {
                                await poiManager.onLocationReady(location: location, userId: userId)
                            } else {
                                // 未登录时只搜索本地 POI
                                await poiManager.searchNearbyPOIs(location: location)
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: locationManager.isTracking) { _, isTracking in
            if isTracking {
                startCollisionMonitoring()
                startPOIMonitoring()
            } else {
                stopCollisionMonitoring()
                stopPOIMonitoring()
            }
        }
        .onChange(of: explorationManager.isExploring) { _, isExploring in
            if isExploring {
                startPOIMonitoring()
            } else {
                stopPOIMonitoring()
            }
        }
        .onDisappear {
            stopCollisionMonitoring()
            stopPOIMonitoring()
        }
    }

    // MARK: - 实时碰撞监控（参考源项目）

    /// 开始实时碰撞监控（每5秒检查一次）
    private func startCollisionMonitoring() {
        guard let userId = authManager.currentUser?.id else {
            appLog(.warning, category: "碰撞监控", message: "用户未登录，跳过碰撞监控")
            return
        }

        appLog(.info, category: "碰撞监控", message: "🚀 启动实时碰撞检测，间隔: \(collisionCheckInterval)秒")

        // 停止之前的定时器
        collisionCheckTimer?.invalidate()

        // 立即检查一次
        checkPathCollisionComprehensive(userId: userId)

        // 启动定时器
        collisionCheckTimer = Timer.scheduledTimer(withTimeInterval: collisionCheckInterval, repeats: true) { _ in
            Task { @MainActor in
                self.checkPathCollisionComprehensive(userId: userId)
            }
        }
    }

    /// 停止碰撞监控
    private func stopCollisionMonitoring() {
        collisionCheckTimer?.invalidate()
        collisionCheckTimer = nil
        locationManager.updateCollisionWarning(nil, level: .safe)
        appLog(.info, category: "碰撞监控", message: "🛑 停止实时碰撞检测")
    }

    /// 综合碰撞检测
    private func checkPathCollisionComprehensive(userId: UUID) {
        let currentPath = locationManager.trackingPath

        guard currentPath.count >= 2 else {
            appLog(.debug, category: "碰撞监控", message: "路径点不足，跳过检测: \(currentPath.count)/2")
            return
        }

        appLog(.debug, category: "碰撞监控", message: "🔍 开始实时碰撞检测，路径点: \(currentPath.count)")

        let result = territoryManager.checkPathCollisionComprehensive(
            path: currentPath,
            currentUserId: userId,
            locationManager: locationManager
        )

        appLog(.debug, category: "碰撞监控", message: "检测结果: 碰撞=\(result.hasCollision), 预警=\(result.warningLevel), 距离=\(result.closestDistance ?? -1)m")

        // 处理碰撞违规（立即终止圈地）
        if result.hasCollision {
            appLog(.error, category: "碰撞监控", message: "❌ 检测到碰撞违规，立即终止圈地")

            // 更新警告状态
            locationManager.updateCollisionWarning(result.message, level: .violation)

            // 触觉反馈
            triggerHapticFeedback(level: .violation)

            // 停止圈地
            locationManager.stopPathTracking()
            locationManager.clearPath()

            // 显示警告弹窗
            if let message = result.message {
                collisionAlertMessage = message
                showCollisionAlert = true
            }
            return
        }

        // 处理距离预警（不终止，仅提醒）
        locationManager.updateCollisionWarning(result.message, level: result.warningLevel)

        // 根据预警级别触发触觉反馈
        if result.warningLevel != .safe {
            triggerHapticFeedback(level: result.warningLevel)
        }
    }

    /// 触觉反馈（参考源项目）
    private func triggerHapticFeedback(level: WarningLevel) {
        switch level {
        case .caution:
            // 注意：轻微震动1次
            notificationFeedback.notificationOccurred(.warning)

        case .warning:
            // 警告：中等震动2次
            impactFeedback.prepare()
            impactFeedback.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.impactFeedback.impactOccurred()
            }

        case .danger:
            // 危险：强烈震动3次
            impactFeedback.prepare()
            impactFeedback.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.impactFeedback.impactOccurred()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.impactFeedback.impactOccurred()
            }

        case .violation:
            // 违规：错误震动
            notificationFeedback.notificationOccurred(.error)

        case .safe:
            // 安全：无震动
            break
        }
    }

    // MARK: - 碰撞警告卡片

    private func collisionWarningCard(message: String) -> some View {
        let warningLevel = locationManager.currentWarningLevel
        let color: Color = {
            switch warningLevel {
            case .safe: return .green
            case .caution: return .yellow
            case .warning: return .orange
            case .danger, .violation: return .red
            }
        }()

        return HStack {
            Image(systemName: warningLevel == .violation ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(color)
                .font(.title2)
            Text(message)
                .font(.subheadline)
                .foregroundColor(color)
                .fontWeight(.semibold)
        }
        .padding()
        .background(color.opacity(0.15))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: color.opacity(0.2), radius: 5, x: 0, y: 2)
    }

    // MARK: - 圈地确认弹窗

    private var claimConfirmationOverlay: some View {
        VStack {
            Spacer()

            VStack(spacing: 16) {
                Text("确认圈地")
                    .font(.headline)
                    .foregroundColor(.white)

                if let coord = territoryManager.selectedLocation {
                    VStack(spacing: 4) {
                        Text("位置: \(coord.latitude, specifier: "%.6f"), \(coord.longitude, specifier: "%.6f")")
                            .font(.caption)
                        Text("半径: \(Int(territoryManager.defaultRadius))米")
                            .font(.caption)
                        Text("面积: \(Int(Double.pi * territoryManager.defaultRadius * territoryManager.defaultRadius))m²")
                            .font(.caption)
                    }
                    .foregroundColor(.white.opacity(0.8))
                }

                HStack(spacing: 20) {
                    Button("取消") {
                        territoryManager.cancelClaiming()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.gray)
                    .cornerRadius(8)

                    Button("确认圈地") {
                        if territoryManager.isLoggedIn {
                            Task {
                                await territoryManager.confirmClaim()
                            }
                        } else {
                            territoryManager.cancelClaiming()
                            showLoginAlert = true
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(territoryManager.isLoggedIn ? Color.green : Color.orange)
                    .cornerRadius(8)
                }
            }
            .padding(20)
            .background(Color.black.opacity(0.8))
            .cornerRadius(16)
            .padding(.horizontal, 40)
            .padding(.bottom, 120)
        }
    }

    // MARK: - 成功提示

    private var successOverlay: some View {
        VStack {
            Spacer()

            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("圈地成功！")
                    .foregroundColor(.white)
            }
            .padding()
            .background(Color.black.opacity(0.8))
            .cornerRadius(12)
            .padding(.bottom, 200)
        }
    }

    // MARK: - 行走圈地按钮

    private var walkingClaimButton: some View {
        Button(action: {
            if locationManager.isTracking {
                // 停止追踪
                locationManager.stopPathTracking()
            } else {
                // 检查登录状态
                if authManager.currentUser == nil {
                    showLoginAlert = true
                } else {
                    // 开始追踪
                    locationManager.startPathTracking()
                }
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: locationManager.isTracking ? "stop.fill" : "figure.walk")
                    .font(.title3)
                Text(locationManager.isTracking ? "停止" : "圈地")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(locationManager.isTracking ? Color.red : Color.orange)
            .cornerRadius(25)
            .shadow(radius: 4)
        }
    }

    // MARK: - 行走追踪状态信息

    private var trackingStatusOverlay: some View {
        let pathPoints = locationManager.trackingPath.count
        let distance = locationManager.calculateTotalPathDistance()
        let distanceToStart = locationManager.distanceToStart()
        let area = locationManager.calculatePolygonArea()

        // 闭环条件检测（与 LocationManager 保持一致）
        let minPoints = 10
        let minDistance = 50.0
        let minArea = 100.0
        let maxClosureDistance = 30.0

        let pointsOK = pathPoints >= minPoints
        let distanceOK = distance >= minDistance
        let areaOK = area >= minArea
        let closureOK = pathPoints > 0 && distanceToStart <= maxClosureDistance

        return VStack(spacing: 8) {
            // 标题
            HStack {
                Image(systemName: "figure.walk")
                    .foregroundColor(.orange)
                Text("正在圈地...")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                // 实时面积
                Text("\(Int(area))m²")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(areaOK ? Color.green : Color.gray)
                    .cornerRadius(4)
                    .foregroundColor(.white)
            }

            Divider().background(Color.white.opacity(0.3))

            // 核心数据
            HStack(spacing: 16) {
                VStack {
                    Text("\(pathPoints)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(pointsOK ? .green : .orange)
                    Text("点数")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }

                VStack {
                    Text("\(Int(distance))m")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(distanceOK ? .green : .orange)
                    Text("已走")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }

                VStack {
                    Text("\(Int(distanceToStart))m")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(closureOK ? .green : .orange)
                    Text("距起点")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            Divider().background(Color.white.opacity(0.3))

            // 闭环条件检查列表（已移除形状检查，原项目没有此限制）
            VStack(alignment: .leading, spacing: 2) {
                conditionRow(label: "点数", current: "\(pathPoints)", required: "≥\(minPoints)", isOK: pointsOK)
                conditionRow(label: "距离", current: "\(Int(distance))m", required: "≥\(Int(minDistance))m", isOK: distanceOK)
                conditionRow(label: "面积", current: "\(Int(area))m²", required: "≥\(Int(minArea))m²", isOK: areaOK)
                conditionRow(label: "闭合", current: "\(Int(distanceToStart))m", required: "≤\(Int(maxClosureDistance))m", isOK: closureOK)
            }

            // 闭环成功提示
            if locationManager.isPathClosed {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("路径已闭合！可以确认圈地")
                        .foregroundColor(.green)
                        .fontWeight(.bold)
                }
                .font(.caption)
                .padding(.top, 4)
            } else if locationManager.hasSelfIntersection {
                HStack {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundColor(.red)
                    Text("路径存在自相交，请调整路线")
                        .foregroundColor(.red)
                        .fontWeight(.bold)
                }
                .font(.caption)
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.85))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    // 条件行组件
    private func conditionRow(label: String, current: String, required: String, isOK: Bool) -> some View {
        HStack {
            Image(systemName: isOK ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isOK ? .green : .gray)
                .font(.caption2)
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 30, alignment: .leading)
            Text(current)
                .font(.caption2)
                .foregroundColor(isOK ? .green : .white)
                .frame(width: 45, alignment: .trailing)
            Text("/")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
            Text(required)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - 行走圈地确认弹窗

    private var walkingClaimConfirmationOverlay: some View {
        VStack {
            Spacer()

            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                    Text("路径已闭合！")
                        .font(.headline)
                        .foregroundColor(.white)
                }

                VStack(spacing: 4) {
                    Text("面积: \(Int(locationManager.enclosedArea))m²")
                        .font(.subheadline)
                    Text("顶点数: \(locationManager.trackingPath.count)")
                        .font(.caption)
                    Text("周长: \(Int(locationManager.calculateTotalPathDistance()))米")
                        .font(.caption)
                }
                .foregroundColor(.white.opacity(0.8))

                HStack(spacing: 20) {
                    Button("取消") {
                    locationManager.clearPath()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.gray)
                .cornerRadius(8)

                    Button("确认圈地") {
                        Task {
                            await confirmWalkingClaim()
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(locationManager.hasSelfIntersection ? Color.gray : Color.green)
                    .cornerRadius(8)
                    .disabled(locationManager.hasSelfIntersection)
                }
            }
            .padding(20)
            .background(Color.black.opacity(0.85))
            .cornerRadius(16)
            .padding(.horizontal, 40)
            .padding(.bottom, 120)
        }
    }

    // MARK: - 确认行走圈地

    private func confirmWalkingClaim() async {
        guard locationManager.isPathClosed else {
            appLog(.warning, category: "确认圈地", message: "路径未闭环，取消")
            return
        }
        guard let user = authManager.currentUser else {
            appLog(.warning, category: "确认圈地", message: "用户未登录")
            showLoginAlert = true
            return
        }

        // 获取路径位置（CLLocation 数组，包含时间戳等完整信息）
        let pathLocations = locationManager.trackingPath
        let area = locationManager.enclosedArea
        let startTime = locationManager.trackingStartTime

        appLog(.info, category: "确认圈地", message: "🏴 用户确认圈地")
        appLog(.info, category: "确认圈地", message: "用户: \(user.username) (\(user.id))")
        appLog(.info, category: "确认圈地", message: "顶点数: \(pathLocations.count), 面积: \(Int(area))m²")

        // 调用 TerritoryManager 进行圈地（使用完整的 CLLocation 数据）
        await territoryManager.confirmWalkingClaim(
            pathLocations: pathLocations,
            area: area,
            startTime: startTime
        )

        // 清除路径
        locationManager.clearPath()

        // 刷新领地数据
        if let location = locationManager.currentLocation {
            await territoryManager.refreshTerritories(at: location)
        }
    }

    // MARK: - POI 监控

    /// 开始 POI 监控（探索时检测附近 POI）
    private func startPOIMonitoring() {
        guard let userId = authManager.currentUser?.id else {
            appLog(.warning, category: "POI监控", message: "用户未登录，跳过POI监控")
            return
        }

        appLog(.info, category: "POI监控", message: "🚀 启动POI检测，间隔: \(poiCheckInterval)秒")

        // 重置检查位置
        poiManager.resetCheckLocation()

        // 停止之前的定时器
        poiCheckTimer?.invalidate()

        // 搜索附近POI
        Task {
            if let location = locationManager.currentLocation {
                await poiManager.searchNearbyPOIs(location: location)
            }
        }

        // 启动定时器
        poiCheckTimer = Timer.scheduledTimer(withTimeInterval: poiCheckInterval, repeats: true) { _ in
            Task { @MainActor in
                await self.checkNearbyPOIs(userId: userId)
            }
        }
    }

    /// 停止 POI 监控
    private func stopPOIMonitoring() {
        poiCheckTimer?.invalidate()
        poiCheckTimer = nil
        appLog(.info, category: "POI监控", message: "🛑 停止POI检测")
    }

    /// 检查附近 POI
    private func checkNearbyPOIs(userId: UUID) async {
        guard let location = locationManager.currentLocation else { return }

        // 检查是否有 POI 被发现
        if let _ = await poiManager.checkNearbyPOIs(location: location, userId: userId) {
            // 触发成功震动
            notificationFeedback.notificationOccurred(.success)
        }
    }

    // MARK: - 领地选择器

    private var territoryPickerSheet: some View {
        NavigationView {
            List {
                ForEach(territoryManager.territories) { territory in
                    Button {
                        selectedTerritoryForBuilding = territory
                        showTerritoryPicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showBuildingsView = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(.green)
                                .font(.title2)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(territory.name ?? "我的领地")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("半径: \(Int(territory.radius))m")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            // 建筑数量
                            let buildingCount = buildingManager.buildingCount(in: territory.id)
                            if buildingCount > 0 {
                                Text("\(buildingCount) 个建筑")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }

                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("选择领地")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        showTerritoryPicker = false
                    }
                }
            }
        }
    }

    // MARK: - POI 发现弹窗

    private func poiDiscoveryOverlay(poi: POI) -> some View {
        VStack {
            Spacer()

            VStack(spacing: 16) {
                // 标题
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.title2)
                    Text("发现POI!")
                        .font(.headline)
                        .foregroundColor(.white)
                }

                // POI 图标和名称
                HStack(spacing: 12) {
                    Image(systemName: poi.type.iconName)
                        .font(.largeTitle)
                        .foregroundColor(.yellow)
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(10)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("你发现了【\(poi.name)】")
                            .font(.subheadline)
                            .foregroundColor(.white)
                        Text("类型: \(poi.type.displayName)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        Text("可获得资源: \(poi.remainingItems) 个")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                // 确认按钮
                Button("太棒了!") {
                    poiManager.clearDiscoveryAlert()
                }
                .foregroundColor(.black)
                .fontWeight(.semibold)
                .padding(.horizontal, 40)
                .padding(.vertical, 12)
                .background(Color.yellow)
                .cornerRadius(25)
            }
            .padding(24)
            .background(Color.black.opacity(0.9))
            .cornerRadius(20)
            .padding(.horizontal, 30)
            .padding(.bottom, 150)
            .shadow(color: .yellow.opacity(0.3), radius: 20, x: 0, y: 0)
        }
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: poiManager.showDiscoveryAlert)
    }

    // MARK: - 探索按钮

    private var explorationButton: some View {
        Button(action: {
            if explorationManager.isExploring {
                // 结束探索
                Task {
                    let result = await explorationManager.endExploration(
                        endLocation: locationManager.currentLocation
                    )
                    if let result = result {
                        explorationResult = result
                        showExplorationResult = true
                    }
                }
            } else {
                // 开始探索
                guard let userId = authManager.currentUser?.id else {
                    showLoginAlert = true
                    return
                }

                Task {
                    let success = await explorationManager.startExploration(
                        userId: userId,
                        startLocation: locationManager.currentLocation
                    )
                    if success {
                        // 开始追踪位置
                        startExplorationTracking()
                    }
                }
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: explorationManager.isExploring ? "stop.fill" : "magnifyingglass")
                    .font(.title3)
                Text(explorationManager.isExploring ? "结束" : "探索")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(explorationManager.isExploring ? Color.red : Color.green)
            .cornerRadius(25)
            .shadow(radius: 4)
        }
    }

    // MARK: - 探索状态卡片

    private var explorationStatusOverlay: some View {
        VStack(spacing: 8) {
            // 标题
            HStack {
                Image(systemName: "figure.walk")
                    .foregroundColor(.green)
                Text("探索中...")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                // 时长
                Text(explorationManager.durationDisplay)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
            }

            Divider().background(Color.white.opacity(0.3))

            // 统计数据
            HStack(spacing: 16) {
                VStack {
                    Text(explorationManager.distanceDisplay)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text("距离")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }

                VStack {
                    Text(explorationManager.areaDisplay)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("面积")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }

                VStack {
                    Text(explorationManager.caloriesDisplay)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    Text("热量")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }

                VStack {
                    Text("\(explorationManager.currentGridCount)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.purple)
                    Text("网格")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.85))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    // MARK: - 探索位置追踪

    private func startExplorationTracking() {
        Task { @MainActor in
            while explorationManager.isExploring {
                if let location = locationManager.currentLocation {
                    explorationManager.trackLocation(location)
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2秒
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SimpleMapView(
        locationManager: LocationManager.shared,
        territoryManager: TerritoryManager.shared,
        authManager: AuthManager.shared,
        explorationManager: ExplorationManager.shared
    )
}
