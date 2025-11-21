//
//  TestManagersView.swift
//  tuzi-fuke (地球新主复刻版)
//
//  Manager测试视图 - 验证Day1基础架构
//  Created by AI Assistant on 2025/11/21.
//

import SwiftUI
import CoreLocation

/// Manager功能测试视图 - 用于验证基础架构
struct TestManagersView: View {

    // MARK: - Manager引用
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var dataManager = DataManager.shared

    // MARK: - 状态属性
    @State private var testResults: [String] = []
    @State private var isRunningTests = false

    // MARK: - 计算属性
    private var locationDetailText: String {
        if let location = locationManager.currentLocation {
            let lat = String(format: "%.6f", location.coordinate.latitude)
            let lng = String(format: "%.6f", location.coordinate.longitude)
            let accuracy = String(format: "%.1f", location.horizontalAccuracy)
            return "位置: \(lat), \(lng) (精度: \(accuracy)m)"
        } else {
            return "无位置信息"
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {

                // 标题
                Text("🧪 Manager系统测试")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding()

                // 状态卡片
                VStack(spacing: 15) {
                    managerStatusCard(
                        title: "🔐 认证管理器",
                        status: authManager.isAuthenticated ? "已认证" : "未认证",
                        details: "用户: \(authManager.userDisplayName)",
                        isGood: authManager.isAuthenticated
                    )

                    managerStatusCard(
                        title: "📍 定位管理器",
                        status: locationManager.authorizationStatus.description,
                        details: locationDetailText,
                        isGood: locationManager.hasLocationPermission
                    )

                    managerStatusCard(
                        title: "💾 数据管理器",
                        status: dataManager.connectionState.description,
                        details: "配置: \(SupabaseConfig.validateConfig() ? "有效" : "无效")",
                        isGood: dataManager.isConnected
                    )
                }
                .padding(.horizontal)

                Spacer()

                // 测试按钮组
                VStack(spacing: 15) {
                    testButton("匿名登录测试", action: testAnonymousLogin)
                    testButton("位置权限测试", action: testLocationPermission)
                    testButton("启动位置监听", action: startLocationUpdates)
                    testButton("数据连接测试", action: testDataConnection)
                    testButton("运行所有测试", action: runAllTests)
                }
                .padding(.horizontal)

                // 测试结果
                if !testResults.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("测试结果:")
                                .font(.headline)
                                .padding(.top)

                            ForEach(Array(testResults.enumerated()), id: \.offset) { index, result in
                                Text(result)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                    }
                    .frame(maxHeight: 200)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                addTestResult("🚀 Manager测试界面已加载")
                printManagerStatus()
            }
        }
    }

    // MARK: - UI组件

    private func managerStatusCard(title: String, status: String, details: String, isGood: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(isGood ? Color.green : Color.orange)
                    .frame(width: 12, height: 12)
            }

            Text(status)
                .font(.subheadline)
                .fontWeight(.medium)

            Text(details)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func testButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button(action: {
            Task {
                await action()
            }
        }) {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
        }
        .disabled(isRunningTests)
    }

    // MARK: - 测试方法

    private func testAnonymousLogin() async {
        addTestResult("🔐 开始匿名登录测试...")
        isRunningTests = true

        defer { isRunningTests = false }

        do {
            await authManager.signOut()
            addTestResult("  - 已登出现有用户")

            try await authManager.signInAnonymously()
            addTestResult("  - ✅ 匿名登录成功")
            addTestResult("  - 用户ID: \(authManager.currentUserId?.uuidString.prefix(8) ?? "无")")
            addTestResult("  - 用户名: \(authManager.userDisplayName)")

        } catch {
            addTestResult("  - ❌ 匿名登录失败: \(error.localizedDescription)")
        }
    }

    private func testLocationPermission() async {
        addTestResult("📍 开始位置权限测试...")
        isRunningTests = true

        defer { isRunningTests = false }

        locationManager.requestLocationPermission()
        addTestResult("  - 已请求位置权限")

        // 等待权限响应
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        if locationManager.hasLocationPermission {
            addTestResult("  - ✅ 位置权限已获得")

            do {
                let location = try await locationManager.getCurrentLocation()
                addTestResult("  - ✅ 成功获取位置: \(location.coordinate)")
            } catch {
                addTestResult("  - ⚠️ 获取位置失败: \(error.localizedDescription)")
            }
        } else {
            addTestResult("  - ❌ 位置权限被拒绝或未获得")
        }
    }

    private func testDataConnection() async {
        addTestResult("💾 开始数据连接测试...")
        isRunningTests = true

        defer { isRunningTests = false }

        do {
            try await dataManager.testConnection()
            addTestResult("  - ✅ 数据库连接测试成功")

            try await dataManager.initialize()
            addTestResult("  - ✅ 数据管理器初始化成功")

        } catch {
            addTestResult("  - ❌ 数据连接失败: \(error.localizedDescription)")
        }
    }

    private func runAllTests() async {
        addTestResult("🧪 运行所有测试...")
        isRunningTests = true

        defer { isRunningTests = false }

        await testAnonymousLogin()
        await testLocationPermission()
        await testDataConnection()

        addTestResult("✅ 所有测试完成")
    }

    private func startLocationUpdates() async {
        addTestResult("📍 启动位置监听...")
        isRunningTests = true

        defer { isRunningTests = false }

        guard locationManager.hasLocationPermission else {
            addTestResult("  - ❌ 需要先获取位置权限")
            return
        }

        do {
            try await locationManager.startLocationUpdates()
            addTestResult("  - ✅ 位置监听已启动")
            addTestResult("  - 💡 查看上方状态卡片的位置信息更新")

            // 等待一下让位置更新
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3秒

            if let location = locationManager.currentLocation {
                let lat = String(format: "%.6f", location.coordinate.latitude)
                let lng = String(format: "%.6f", location.coordinate.longitude)
                addTestResult("  - 🎯 当前位置: \(lat), \(lng)")
            }

        } catch {
            addTestResult("  - ❌ 启动位置监听失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 辅助方法

    private func addTestResult(_ message: String) {
        let timestamp = DateFormatter().string(from: Date()).suffix(8)
        testResults.append("[\(timestamp)] \(message)")

        // 保持最新50条记录
        if testResults.count > 50 {
            testResults.removeFirst()
        }
    }

    private func printManagerStatus() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🧪 Manager系统状态检查")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        authManager.printAuthStatus()
        locationManager.printLocationStatus()
        dataManager.printDataStatus()

        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}

// MARK: - 预览

#Preview {
    TestManagersView()
}