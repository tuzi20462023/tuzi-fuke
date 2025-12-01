//
//  LocationView.swift
//  tuzi-fuke (地球新主复刻版)
//
//  位置数据采集和上传状态展示视图
//  Created by AI Assistant on 2025/11/21.
//

import SwiftUI
import CoreLocation

// MARK: - LocationView

/// 位置数据采集和上传状态视图
struct LocationView: View {

    // MARK: - 环境对象
    @StateObject private var locationManager = LocationManager.shared
    @StateObject private var authManager = AuthManager.shared

    // MARK: - 状态属性
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isStartingCollection = false
    @State private var showingSettings = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 位置权限状态
                    locationPermissionSection

                    // 当前位置信息
                    currentLocationSection

                    // 数据采集控制
                    collectionControlSection

                    // 采集统计信息
                    statisticsSection

                    // 上传状态
                    uploadStatusSection

                    // 设置选项
                    settingsSection
                }
                .padding()
            }
            .navigationTitle("位置数据采集")
            .refreshable {
                locationManager.printLocationStatus()
            }
            .alert("提示", isPresented: $showingAlert) {
                Button("确定") { }
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsSheetView(locationManager: locationManager)
            }
        }
    }

    // MARK: - 位置权限状态
    @ViewBuilder
    private var locationPermissionSection: some View {
        SectionCard(title: "📍 位置权限", titleColor: .blue) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("权限状态:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(locationManager.authorizationStatus.description)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(locationManager.hasLocationPermission ? .green : .orange)
                }

                HStack {
                    Text("位置服务:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(locationManager.isLocationServiceEnabled ? "已启用" : "已禁用")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(locationManager.isLocationServiceEnabled ? .green : .red)
                }

                if !locationManager.hasLocationPermission {
                    Button("请求位置权限") {
                        locationManager.requestLocationPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - 当前位置信息
    @ViewBuilder
    private var currentLocationSection: some View {
        SectionCard(title: "🌐 当前位置", titleColor: .green) {
            VStack(alignment: .leading, spacing: 12) {
                if let location = locationManager.currentLocation {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("坐标:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.6f, %.6f", location.coordinate.latitude, location.coordinate.longitude))
                                .font(.caption.monospaced())
                        }

                        HStack {
                            Text("精度:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            HStack(spacing: 4) {
                                let position = Position(from: location, userId: authManager.currentUserId ?? UUID())
                                Text(position.accuracyLevel.color)
                                Text(String(format: "±%.1fm", location.horizontalAccuracy))
                                    .font(.caption.monospaced())
                            }
                        }

                        if let lastUpdate = locationManager.lastLocationUpdate {
                            HStack {
                                Text("更新时间:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(lastUpdate, format: .dateTime.hour().minute().second())
                                    .font(.caption)
                            }
                        }
                    }
                } else {
                    Text("位置信息不可用")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - 数据采集控制
    @ViewBuilder
    private var collectionControlSection: some View {
        SectionCard(title: "🔄 数据采集", titleColor: .purple) {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(locationManager.isCollecting ? "采集进行中" : "采集已停止")
                            .font(.headline)
                            .foregroundColor(locationManager.isCollecting ? .green : .secondary)

                        if locationManager.isCollecting {
                            Text("每 \(Int(locationManager.collectionInterval)) 秒采集一次位置")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()

                    // 状态指示器
                    Circle()
                        .fill(locationManager.isCollecting ? Color.green : Color.gray)
                        .frame(width: 12, height: 12)
                        .scaleEffect(locationManager.isCollecting ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                                 value: locationManager.isCollecting)
                }

                HStack(spacing: 12) {
                    if locationManager.isCollecting {
                        Button("停止采集") {
                            locationManager.stopLocationCollection()
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(!authManager.isAuthenticated)

                        Button("立即上传") {
                            Task {
                                await locationManager.uploadNow()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!authManager.isAuthenticated)

                    } else {
                        Button("开始采集") {
                            startLocationCollection()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isStartingCollection || !authManager.isAuthenticated)
                        .overlay {
                            if isStartingCollection {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }

                    Button("设置") {
                        showingSettings = true
                    }
                    .buttonStyle(.bordered)
                }

                if !authManager.isAuthenticated {
                    Text("需要登录后才能开始数据采集")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    // MARK: - 采集统计信息
    @ViewBuilder
    private var statisticsSection: some View {
        SectionCard(title: "📊 采集统计", titleColor: .blue) {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {

                StatisticItem(
                    title: "已采集",
                    value: "\(locationManager.totalCollectedCount)",
                    icon: "location.circle.fill",
                    color: .blue
                )

                StatisticItem(
                    title: "已上传",
                    value: "\(locationManager.totalUploadedCount)",
                    icon: "icloud.and.arrow.up.fill",
                    color: .green
                )

                StatisticItem(
                    title: "待上传",
                    value: "\(locationManager.pendingPositions.count)",
                    icon: "clock.fill",
                    color: .orange
                )

                StatisticItem(
                    title: "采集间隔",
                    value: "\(Int(locationManager.collectionInterval))s",
                    icon: "timer.circle.fill",
                    color: .purple
                )
            }
        }
    }

    // MARK: - 上传状态
    @ViewBuilder
    private var uploadStatusSection: some View {
        SectionCard(title: "⬆️ 上传状态", titleColor: .green) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("状态:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Text(locationManager.uploadStatus.icon)
                        Text(locationManager.uploadStatus.description)
                            .font(.subheadline.weight(.medium))
                    }
                }

                if let lastUpload = locationManager.lastUploadTime {
                    HStack {
                        Text("最后上传:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(lastUpload, format: .dateTime.hour().minute().second())
                            .font(.subheadline)
                    }
                }

                HStack {
                    Text("上传间隔:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("每 \(Int(locationManager.uploadInterval)) 秒")
                        .font(.subheadline)
                }
            }
        }
    }

    // MARK: - 设置选项
    @ViewBuilder
    private var settingsSection: some View {
        SectionCard(title: "⚙️ 调试选项", titleColor: .gray) {
            VStack(spacing: 12) {
                Button("打印状态到控制台") {
                    locationManager.printLocationStatus()
                }
                .buttonStyle(.bordered)

                Button("获取单次位置") {
                    Task {
                        do {
                            let location = try await locationManager.getCurrentLocation()
                            alertMessage = "位置获取成功:\n\(String(format: "%.6f, %.6f", location.coordinate.latitude, location.coordinate.longitude))"
                            showingAlert = true
                        } catch {
                            alertMessage = "位置获取失败: \(error.localizedDescription)"
                            showingAlert = true
                        }
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - 私有方法
    private func startLocationCollection() {
        guard let userId = authManager.currentUserId else {
            alertMessage = "需要先登录才能开始数据采集"
            showingAlert = true
            return
        }

        isStartingCollection = true

        Task {
            do {
                try await locationManager.startLocationCollection(userId: userId)
                await MainActor.run {
                    isStartingCollection = false
                }
            } catch {
                await MainActor.run {
                    isStartingCollection = false
                    alertMessage = "开始数据采集失败: \(error.localizedDescription)"
                    showingAlert = true
                }
            }
        }
    }
}

// MARK: - 辅助视图

/// 统计项目视图
struct StatisticItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundColor(.primary)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        }
    }
}

/// 区域卡片视图
struct SectionCard<Content: View>: View {
    let title: String
    let titleColor: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundColor(titleColor)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
    }
}

/// 设置表单视图
struct SettingsSheetView: View {
    @ObservedObject var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss

    @State private var collectionInterval: Double
    @State private var uploadInterval: Double
    @State private var maxBatchSize: Double

    init(locationManager: LocationManager) {
        self.locationManager = locationManager
        self._collectionInterval = State(initialValue: locationManager.collectionInterval)
        self._uploadInterval = State(initialValue: locationManager.uploadInterval)
        self._maxBatchSize = State(initialValue: Double(locationManager.maxBatchSize))
    }

    var body: some View {
        NavigationView {
            Form {
                Section("采集设置") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("采集间隔: \(Int(collectionInterval)) 秒")
                        Slider(value: $collectionInterval, in: 10...300, step: 10)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("上传间隔: \(Int(uploadInterval)) 秒")
                        Slider(value: $uploadInterval, in: 60...1800, step: 60)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("批量大小: \(Int(maxBatchSize)) 条")
                        Slider(value: $maxBatchSize, in: 5...50, step: 5)
                    }
                }

                Section("说明") {
                    Text("• 采集间隔：每隔多少秒采集一次位置数据")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("• 上传间隔：每隔多少秒上传一批数据到服务器")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("• 批量大小：达到多少条数据时立即上传")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("采集设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveSettings()
                        dismiss()
                    }
                }
            }
        }
    }

    private func saveSettings() {
        locationManager.configureCollection(
            interval: collectionInterval,
            uploadInterval: uploadInterval,
            batchSize: Int(maxBatchSize)
        )
    }
}

// MARK: - 预览
struct LocationView_Previews: PreviewProvider {
    static var previews: some View {
        LocationView()
    }
}