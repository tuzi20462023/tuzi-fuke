//
//  ContentView.swift
//  tuzi-fuke
//
//  Created by Mike Liu on 2025/11/21.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @StateObject private var territoryManager = TerritoryManager.shared
    @StateObject private var explorationManager = ExplorationManager.shared
    @ObservedObject private var authManager = AuthManager.shared
    @StateObject private var locationTracker = LocationTrackerManager.shared

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                // 已登录 - 显示主界面
                mainTabView
                    .task {
                        // 启动位置追踪（用于附近玩家功能）
                        await startLocationTracking()
                    }
                    .onDisappear {
                        // 停止位置追踪
                        locationTracker.stopTracking()
                    }
            } else {
                // 未登录 - 显示登录界面
                AuthView(authManager: authManager)
            }
        }
    }

    /// 启动位置追踪
    private func startLocationTracking() async {
        // 确保有位置权限
        let locationManager = LocationManager.shared
        locationManager.requestLocationPermission()

        // 等待权限
        try? await Task.sleep(nanoseconds: 500_000_000)

        guard locationManager.hasLocationPermission else {
            print("❌ [ContentView] 没有位置权限，跳过位置追踪")
            return
        }

        // 启动位置更新
        try? await locationManager.startLocationUpdates()

        // 等待获取位置
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // 启动位置追踪器
        locationTracker.startTracking()
        print("✅ [ContentView] 位置追踪已启动")
    }

    // MARK: - 主界面 TabView

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: 地图（主界面，包含圈地和探索）
            NavigationView {
                SimpleMapView(
                    locationManager: LocationManager.shared,
                    territoryManager: territoryManager,
                    authManager: authManager,
                    explorationManager: explorationManager,
                    switchToDebugTab: { selectedTab = 4 }  // 调试Tab改为4
                )
                .navigationTitle(authManager.currentUser?.email ?? "地图")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            // 显示当前用户
                            if let user = authManager.currentUser {
                                Text("当前用户: \(user.email ?? user.username)")
                            }

                            Divider()

                            Button(role: .destructive) {
                                Task {
                                    await authManager.signOut()
                                }
                            } label: {
                                Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        } label: {
                            Image(systemName: "person.circle")
                        }
                    }
                }
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Image(systemName: "map.fill")
                Text("地图")
            }
            .tag(0)

            // Tab 2: 探索（POI发现和探索模式）
            ExploreTabView()
                .tabItem {
                    Image(systemName: "figure.walk")
                    Text("探索")
                }
                .tag(1)

            // Tab 3: 领地（建筑管理入口，无MapKit，不会白屏）
            TerritoryTabView()
                .tabItem {
                    Image(systemName: "building.2.fill")
                    Text("领地")
                }
                .tag(2)

            // Tab 4: 聊天（通信系统）
            CommunicationHubView()
                .tabItem {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                    Text("通讯")
                }
                .tag(3)

            // Tab 5: 调试
            TestManagersView()
                .tabItem {
                    Image(systemName: "wrench.fill")
                    Text("调试")
                }
                .tag(4)

            // Tab 6: 日志
            LogViewerView()
                .tabItem {
                    Image(systemName: "doc.text.fill")
                    Text("日志")
                }
                .tag(5)
        }
    }
}

#Preview {
    ContentView()
}
