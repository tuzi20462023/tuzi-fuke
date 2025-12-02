//
//  CommsDeviceView.swift
//  tuzi-fuke
//
//  通讯终端 - 设备面板
//  显示设备状态与商店
//

import SwiftUI
import StoreKit

struct CommsDeviceView: View {
    @StateObject private var deviceManager = DeviceManager.shared
    @StateObject private var storeManager = StoreKitManager.shared
    @State private var showingPurchaseAlert = false
    @State private var purchasedItemName = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. 顶部：当前设备仪表盘
                deviceStatusDashboard
                
                // 2. 商店部分
                VStack(alignment: .leading, spacing: 16) {
                    Text("设备升级中心")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    if storeManager.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        ForEach(storeManager.products) { product in
                            DeviceUpgradeCard(
                                product: product,
                                isOwned: storeManager.isPurchased(product.id),
                                onPurchase: {
                                    buyProduct(product)
                                }
                            )
                        }
                    }
                    
                    // 恢复购买
                    Button {
                        Task { await storeManager.restorePurchases() }
                    } label: {
                        Text("恢复已购买项目")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
                .padding(.bottom, 40)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .task {
            await deviceManager.loadDevices()
            await storeManager.loadProducts()
        }
        .alert("购买成功", isPresented: $showingPurchaseAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("您已成功装备 \(purchasedItemName)")
        }
    }
    
    // MARK: - 仪表盘视图
    private var deviceStatusDashboard: some View {
        VStack(spacing: 20) {
            // 设备图标与名称
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.blue.opacity(0.2), .blue.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 100, height: 100)
                        .overlay(
                            Circle().stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                    
                    Image(systemName: currentDeviceIcon)
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                        .shadow(color: .blue.opacity(0.5), radius: 10)
                }
                
                VStack(spacing: 4) {
                    Text(deviceManager.activeDevice?.displayName ?? "无设备")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(deviceManager.activeDevice?.canSend == true ? "双向通讯模式" : "仅接收模式")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(deviceManager.activeDevice?.canSend == true ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        .foregroundColor(deviceManager.activeDevice?.canSend == true ? .green : .orange)
                        .cornerRadius(12)
                }
            }
            
            Divider()
            
            // 状态网格
            HStack(spacing: 0) {
                // 电量
                statusItem(
                    title: "电池电量",
                    value: "\(Int(deviceManager.activeDevice?.batteryLevel ?? 0))%",
                    icon: "battery.100",
                    color: .green
                )
                
                Divider().frame(height: 40)
                
                // 信号范围
                statusItem(
                    title: "通讯范围",
                    value: rangeText,
                    icon: "dot.radiowaves.left.and.right",
                    color: .blue
                )
                
                Divider().frame(height: 40)
                
                // 状态
                statusItem(
                    title: "设备状态",
                    value: "正常",
                    icon: "checkmark.shield.fill",
                    color: .primary
                )
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
        .padding(.horizontal)
    }
    
    private func statusItem(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundColor(.secondary)
            
            Text(value)
                .font(.headline)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - 逻辑助手
    
    private var currentDeviceIcon: String {
        deviceManager.activeDevice?.deviceType.icon ?? "antenna.radiowaves.left.and.right.slash"
    }
    
    private var rangeText: String {
        guard let device = deviceManager.activeDevice else { return "0 km" }
        // 根据设备类型返回通讯范围
        switch device.deviceType {
        case .radio: return "仅接收"
        case .walkieTalkie: return "3 km"
        case .campRadio: return "30 km"
        case .cellphone: return "\(Int(device.effectiveRangeKm)) km"
        }
    }
    
    private func buyProduct(_ product: Product) {
        Task {
            if await storeManager.purchase(product) {
                purchasedItemName = product.displayName
                showingPurchaseAlert = true
                await deviceManager.loadDevices() // 刷新设备状态
            }
        }
    }
}

// MARK: - 商店卡片组件

struct DeviceUpgradeCard: View {
    let product: Product
    let isOwned: Bool
    let onPurchase: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // 图标背景
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .frame(width: 64, height: 64)
                
                Image(systemName: iconForProduct)
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            
            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(product.displayName)
                    .font(.headline)
                
                Text(product.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // 按钮
            if isOwned {
                Text("已拥有")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
            } else {
                Button(action: onPurchase) {
                    Text(product.displayPrice)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(20)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .padding(.horizontal)
        .shadow(color: .black.opacity(0.02), radius: 5, y: 2)
    }
    
    private var iconForProduct: String {
        // 根据ID简单映射图标
        if product.id.contains("walkie") { return "antenna.radiowaves.left.and.right" }
        if product.id.contains("radio") { return "antenna.radiowaves.left.and.right.circle" }
        if product.id.contains("cell") { return "iphone" }
        return "shippingbox.fill"
    }
}
