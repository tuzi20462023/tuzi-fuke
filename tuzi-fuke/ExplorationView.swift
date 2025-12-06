//
//  ExplorationView.swift
//  tuzi-fuke
//
//  探索视图 - 显示探索状态、统计数据、开始/结束按钮
//

import SwiftUI
import CoreLocation

struct ExplorationView: View {

    @ObservedObject var explorationManager: ExplorationManager
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var authManager: AuthManager

    @State private var showResultSheet = false
    @State private var explorationResult: ExplorationResult?
    @State private var showLoginAlert = false

    var body: some View {
        ZStack {
            // 背景
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.green.opacity(0.1)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {

                // 标题
                HStack {
                    Image(systemName: "figure.walk")
                        .font(.title)
                        .foregroundColor(.blue)
                    Text("探索模式")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
                .padding(.top, 40)

                // 状态卡片
                statusCard

                // 统计数据
                if explorationManager.isExploring {
                    statisticsGrid
                }

                Spacer()

                // 操作按钮
                actionButton

                Spacer()
                    .frame(height: 100)
            }
            .padding()
        }
        .alert("需要登录", isPresented: $showLoginAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("探索功能需要先登录账号")
        }
        .sheet(isPresented: $showResultSheet) {
            if let result = explorationResult {
                ExplorationResultSheet(result: result) {
                    showResultSheet = false
                    explorationResult = nil
                }
            }
        }
    }

    // MARK: - 状态卡片

    private var statusCard: some View {
        VStack(spacing: 12) {
            // 状态图标
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: statusIcon)
                    .font(.system(size: 36))
                    .foregroundColor(statusColor)

                if explorationManager.isExploring {
                    Circle()
                        .stroke(statusColor, lineWidth: 3)
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(explorationManager.explorationDuration.truncatingRemainder(dividingBy: 360)))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: explorationManager.explorationDuration)
                }
            }

            // 状态文字
            Text(statusText)
                .font(.headline)
                .foregroundColor(statusColor)

            // 时长（探索中显示）
            if explorationManager.isExploring {
                Text(explorationManager.durationDisplay)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }

    // MARK: - 统计数据网格

    private var statisticsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            StatisticCard(
                icon: "arrow.triangle.swap",
                title: "距离",
                value: explorationManager.distanceDisplay,
                color: .blue
            )

            StatisticCard(
                icon: "square.grid.3x3",
                title: "探索面积",
                value: explorationManager.areaDisplay,
                color: .green
            )

            StatisticCard(
                icon: "flame.fill",
                title: "消耗热量",
                value: explorationManager.caloriesDisplay,
                color: .orange
            )

            StatisticCard(
                icon: "mappin.and.ellipse",
                title: "网格数",
                value: "\(explorationManager.currentGridCount)",
                color: .purple
            )
        }
    }

    // MARK: - 操作按钮

    private var actionButton: some View {
        Group {
            if explorationManager.isExploring {
                // 结束探索按钮
                Button(action: {
                    Task {
                        let result = await explorationManager.endExploration(
                            endLocation: locationManager.currentLocation
                        )
                        if let result = result {
                            explorationResult = result
                            showResultSheet = true
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("结束探索")
                    }
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.red)
                    .cornerRadius(16)
                }
            } else {
                // 开始探索按钮
                Button(action: {
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
                            startLocationTracking()
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("开始探索")
                    }
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .green]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                }
                .disabled(explorationManager.state == .ending)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - 辅助属性

    private var statusColor: Color {
        switch explorationManager.state {
        case .idle: return .gray
        case .exploring: return .green
        case .ending: return .orange
        case .completed: return .blue
        case .failed: return .red
        }
    }

    private var statusIcon: String {
        switch explorationManager.state {
        case .idle: return "figure.stand"
        case .exploring: return "figure.walk"
        case .ending: return "hourglass"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private var statusText: String {
        switch explorationManager.state {
        case .idle: return "准备就绪"
        case .exploring: return "探索中..."
        case .ending: return "正在结束..."
        case .completed: return "探索完成"
        case .failed(let msg): return "失败: \(msg)"
        }
    }

    // MARK: - 位置追踪

    private func startLocationTracking() {
        // 监听位置更新，传递给探索管理器
        // 使用 Task 和循环代替 Timer，避免并发问题
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

// MARK: - 统计卡片组件

struct StatisticCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - 探索结果弹窗（含 AI 物资描述）

struct ExplorationResultSheet: View {
    let result: ExplorationResult
    let onDismiss: () -> Void

    @StateObject private var aiGenerator = AILootDescriptionGenerator.shared
    @State private var lootResult: ExplorationLoot?
    @State private var isLoadingLoot = true

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 成功图标
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.2))
                            .frame(width: 80, height: 80)

                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.green)
                    }
                    .padding(.top, 16)

                    Text("探索完成!")
                        .font(.title)
                        .fontWeight(.bold)

                    // 统计结果（折叠显示）
                    DisclosureGroup {
                        VStack(spacing: 12) {
                            ResultRow(icon: "clock.fill", title: "探索时长", value: "\(result.durationMinutes) 分钟", color: .blue)
                            ResultRow(icon: "arrow.triangle.swap", title: "行走距离", value: String(format: "%.2f km", result.distanceKm), color: .green)
                            ResultRow(icon: "square.grid.3x3", title: "探索面积", value: result.areaDisplay, color: .purple)
                            ResultRow(icon: "flame.fill", title: "消耗热量", value: String(format: "%.0f 千卡", result.session.caloriesBurned), color: .orange)
                            ResultRow(icon: "mappin.and.ellipse", title: "探索网格", value: "\(result.session.gridCount) 个", color: .cyan)
                        }
                        .padding(.top, 8)
                    } label: {
                        HStack {
                            Image(systemName: "chart.bar.fill")
                                .foregroundColor(.blue)
                            Text("探索统计")
                                .fontWeight(.medium)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    // AI 物资描述区域
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.orange)
                            Text("探索发现")
                                .font(.headline)
                                .fontWeight(.bold)
                        }

                        if isLoadingLoot {
                            // 加载中
                            HStack {
                                Spacer()
                                VStack(spacing: 12) {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                    Text("正在搜索物资...")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 30)
                        } else if let loot = lootResult {
                            // AI 叙述文本
                            Text(loot.narrative)
                                .font(.body)
                                .foregroundColor(.primary)
                                .lineSpacing(4)
                                .padding()
                                .background(narrativeBackground(mood: loot.mood))
                                .cornerRadius(12)

                            // 物资列表
                            VStack(spacing: 8) {
                                ForEach(loot.items) { item in
                                    LootItemRow(item: item)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    Spacer(minLength: 20)

                    // 确定按钮
                    Button(action: onDismiss) {
                        Text("收下物资")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [.green, .blue]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                    }
                    .disabled(isLoadingLoot)
                    .opacity(isLoadingLoot ? 0.6 : 1.0)
                    .padding(.bottom, 20)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .onAppear {
            loadLootDescription()
        }
    }

    // 加载 AI 物资描述
    private func loadLootDescription() {
        Task {
            let loot = await aiGenerator.generateLootDescription(
                distance: result.session.totalDistance,
                area: result.session.totalArea,
                duration: result.session.endedAt?.timeIntervalSince(result.session.startedAt) ?? 0,
                discoveredPOIs: result.session.discoveredPOIs
            )

            await MainActor.run {
                self.lootResult = loot
                self.isLoadingLoot = false
            }
        }
    }

    // 根据氛围返回背景颜色（旅行风格）
    private func narrativeBackground(mood: String) -> Color {
        switch mood {
        case "excited":
            return Color.orange.opacity(0.1)
        case "peaceful":
            return Color.blue.opacity(0.1)
        case "adventurous":
            return Color.purple.opacity(0.1)
        default: // relaxed
            return Color.green.opacity(0.1)
        }
    }
}

// MARK: - 物资行视图

struct LootItemRow: View {
    let item: LootItem

    var body: some View {
        HStack {
            Image(systemName: item.icon)
                .font(.title3)
                .foregroundColor(.orange)
                .frame(width: 30)

            Text(item.name)
                .font(.body)

            Spacer()

            Text("x \(item.quantity)")
                .font(.headline)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

struct ResultRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 30)

            Text(title)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Preview

#Preview {
    ExplorationView(
        explorationManager: ExplorationManager.shared,
        locationManager: LocationManager.shared,
        authManager: AuthManager.shared
    )
}
