//
//  DeviceStoreView.swift
//  tuzi-fuke
//
//  通讯设备商店界面
//

import SwiftUI
import StoreKit

struct DeviceStoreView: View {
    @StateObject private var storeManager = StoreKitManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showSuccessAlert = false
    @State private var purchasedProductName = ""

    var body: some View {
        NavigationView {
            ZStack {
                // 背景
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if storeManager.isLoading {
                    // 加载中
                    ProgressView("加载商品中...")
                } else if storeManager.products.isEmpty {
                    // 无产品
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("无法加载商品")
                            .font(.headline)
                        Text("请检查网络连接后重试")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("重试") {
                            Task {
                                await storeManager.loadProducts()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    // 产品列表
                    ScrollView {
                        VStack(spacing: 16) {
                            // 标题说明
                            headerSection

                            // 产品卡片
                            ForEach(storeManager.products, id: \.id) { product in
                                ProductCard(
                                    product: product,
                                    isPurchased: storeManager.isPurchased(product.id),
                                    onPurchase: {
                                        Task {
                                            let success = await storeManager.purchase(product)
                                            if success {
                                                purchasedProductName = product.displayName
                                                showSuccessAlert = true
                                            }
                                        }
                                    }
                                )
                            }

                            // 恢复购买按钮
                            restoreButton

                            // 说明文字
                            disclaimerSection
                        }
                        .padding()
                    }
                }

                // 购买中遮罩
                if storeManager.purchaseStatus == .purchasing {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("处理中...")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
                    .padding(40)
                    .background(Color(.systemGray5))
                    .cornerRadius(16)
                }
            }
            .navigationTitle("通讯设备商店")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
        .alert("购买成功", isPresented: $showSuccessAlert) {
            Button("太好了") {
                dismiss()
            }
        } message: {
            Text("恭喜获得「\(purchasedProductName)」！\n现在可以发送消息了。")
        }
    }

    // MARK: - 标题说明
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 50))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("升级通讯设备")
                .font(.title2)
                .fontWeight(.bold)

            Text("购买更强大的设备，扩大通讯范围")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 20)
    }

    // MARK: - 恢复购买按钮
    private var restoreButton: some View {
        Button {
            Task {
                await storeManager.restorePurchases()
            }
        } label: {
            Text("恢复购买")
                .font(.subheadline)
                .foregroundColor(.blue)
        }
        .padding(.top, 8)
    }

    // MARK: - 说明文字
    private var disclaimerSection: some View {
        VStack(spacing: 4) {
            Text("购买后设备将永久解锁")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("如有问题请联系客服")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 16)
    }
}

// MARK: - 产品卡片

struct ProductCard: View {
    let product: Product
    let isPurchased: Bool
    let onPurchase: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // 设备图标
            ZStack {
                Circle()
                    .fill(deviceColor.opacity(0.15))
                    .frame(width: 60, height: 60)

                Image(systemName: deviceIcon)
                    .font(.system(size: 28))
                    .foregroundColor(deviceColor)
            }

            // 设备信息
            VStack(alignment: .leading, spacing: 4) {
                Text(product.displayName)
                    .font(.headline)

                Text(deviceDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)

                // 通讯范围标签
                HStack(spacing: 4) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.caption2)
                    Text("通讯范围: \(rangeText)")
                        .font(.caption)
                }
                .foregroundColor(.blue)
            }

            Spacer()

            // 购买按钮
            if isPurchased {
                // 已购买
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                    Text("已拥有")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            } else {
                // 购买按钮
                Button(action: onPurchase) {
                    Text(product.displayPrice)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(20)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }

    // 设备图标
    private var deviceIcon: String {
        switch product.id {
        case ProductIDs.walkieTalkie:
            return "antenna.radiowaves.left.and.right"
        case ProductIDs.campRadio:
            return "antenna.radiowaves.left.and.right.circle"
        case ProductIDs.cellphone:
            return "iphone.radiowaves.left.and.right"
        default:
            return "radio"
        }
    }

    // 设备颜色
    private var deviceColor: Color {
        switch product.id {
        case ProductIDs.walkieTalkie:
            return .green
        case ProductIDs.campRadio:
            return .orange
        case ProductIDs.cellphone:
            return .purple
        default:
            return .blue
        }
    }

    // 设备描述
    private var deviceDescription: String {
        switch product.id {
        case ProductIDs.walkieTalkie:
            return "短距离双向通讯设备"
        case ProductIDs.campRadio:
            return "中距离通讯设备，适合营地使用"
        case ProductIDs.cellphone:
            return "远距离通讯设备，可升级扩展范围"
        default:
            return "通讯设备"
        }
    }

    // 通讯范围文本
    private var rangeText: String {
        switch product.id {
        case ProductIDs.walkieTalkie:
            return "3km"
        case ProductIDs.campRadio:
            return "30km"
        case ProductIDs.cellphone:
            return "100km"
        default:
            return "未知"
        }
    }
}

// MARK: - 预览

#Preview {
    DeviceStoreView()
}
