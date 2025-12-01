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

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: 地图（主界面）
            SimpleMapView(
                locationManager: LocationManager.shared,
                territoryManager: territoryManager,
                authManager: AuthManager.shared,
                switchToDebugTab: { selectedTab = 1 }
            )
            .tabItem {
                Image(systemName: "map.fill")
                Text("地图")
            }
            .tag(0)

            // Tab 2: 聊天（通信系统）
            ChatView()
                .tabItem {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                    Text("聊天")
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
