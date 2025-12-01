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

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: 地图（主界面，包含圈地和探索）
            SimpleMapView(
                locationManager: LocationManager.shared,
                territoryManager: territoryManager,
                authManager: AuthManager.shared,
                explorationManager: explorationManager,
                switchToDebugTab: { selectedTab = 1 }
            )
            .tabItem {
                Image(systemName: "map.fill")
                Text("地图")
            }
            .tag(0)

            // Tab 2: 调试
            TestManagersView()
                .tabItem {
                    Image(systemName: "wrench.fill")
                    Text("调试")
                }
                .tag(1)

            // Tab 3: 日志
            LogViewerView()
                .tabItem {
                    Image(systemName: "doc.text.fill")
                    Text("日志")
                }
                .tag(2)
        }
    }
}

#Preview {
    ContentView()
}
