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
    @ObservedObject private var authManager = AuthManager.shared

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                // 已登录 - 显示主界面
                mainTabView
            } else {
                // 未登录 - 显示登录界面
                AuthView(authManager: authManager)
            }
        }
    }

    // MARK: - 主界面 TabView

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: 地图（主界面）
            NavigationView {
                SimpleMapView(
                    locationManager: LocationManager.shared,
                    territoryManager: territoryManager,
                    authManager: authManager,
                    switchToDebugTab: { selectedTab = 2 }
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

            // Tab 2: 聊天（通信系统）
            CommunicationHubView()
                .tabItem {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                    Text("通讯")
                }
                .tag(1)

            // Tab 3: 调试
            TestManagersView()
                .tabItem {
                    Image(systemName: "wrench.fill")
                    Text("调试")
                }
                .tag(2)

            // Tab 4: 日志
            LogViewerView()
                .tabItem {
                    Image(systemName: "doc.text.fill")
                    Text("日志")
                }
                .tag(3)
        }
    }
}

#Preview {
    ContentView()
}
