//
//  tuzi_fukeApp.swift
//  tuzi-fuke (地球新主复刻版)
//
//  Created by Mike Liu on 2025/11/21.
//  基于AI辅助开发的GPS策略游戏
//

import SwiftUI
import SwiftData
import MapKit
import CoreLocation

@main
struct tuzi_fukeApp: App {

    // MARK: - 初始化

    init() {
        // 🔧 启动时配置
        setupApp()
    }

    // MARK: - SwiftData容器

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            CachedCheckinPhoto.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    // MARK: - 应用主体

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // 应用启动后验证配置
                    validateAppSetup()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - 应用配置方法

extension tuzi_fukeApp {

    /// 应用启动配置
    private func setupApp() {
        print("🚀 [App] 地球新主启动中...")

        // 打印应用信息
        printAppInfo()

        // 验证Supabase配置
        SupabaseConfig.printDebugInfo()

        // 预初始化核心组件
        initializeComponents()

        print("✅ [App] 应用初始化完成")
    }

    /// 打印应用信息
    private func printAppInfo() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🎮 地球新主 (tuzi-fuke) - GPS策略游戏")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("版本: MVP v1.0")
        print("技术栈: SwiftUI + Supabase + MapKit + CoreLocation")
        print("目标: iOS 15.0+")
        print("模式: AI辅助开发")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    /// 预初始化核心组件
    private func initializeComponents() {
        print("🔧 [App] 核心组件初始化中...")

        // 初始化核心Manager (单例)
        let _ = AuthManager.shared
        let _ = LocationManager.shared
        let _ = DataManager.shared
        let _ = CheckinDataStore.shared

        print("🔐 [App] AuthManager已初始化")
        print("📍 [App] LocationManager已初始化")
        print("💾 [App] DataManager已初始化")
        print("💿 [App] CheckinDataStore已初始化")
        print("📱 [App] MapKit已导入")
        print("🗺️ [App] CoreLocation已导入")

        print("✅ [App] 所有核心组件初始化完成")
    }

    /// 验证应用配置
    private func validateAppSetup() {
        print("🔍 [App] 验证应用配置...")

        // 验证Supabase配置
        let supabaseValid = SupabaseConfig.validateConfig()

        // 验证权限配置
        let locationPermissionConfigured = Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") != nil

        // 打印验证结果
        print("📊 [App] 配置验证结果:")
        print("  - Supabase配置: \(supabaseValid ? "✅" : "❌")")
        print("  - 定位权限配置: \(locationPermissionConfigured ? "✅" : "❌")")
        print("  - MapKit导入: ✅")
        print("  - CoreLocation导入: ✅")

        if !supabaseValid {
            print("⚠️ [App] 请在SupabaseConfig.swift中配置正确的Supabase URL和密钥")
        }
    }
}
