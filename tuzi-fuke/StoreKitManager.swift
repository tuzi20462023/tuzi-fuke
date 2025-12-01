//
//  StoreKitManager.swift
//  tuzi-fuke
//
//  StoreKit 2 管理器 - 处理应用内购买
//

import Foundation
import StoreKit
import Combine
import Supabase

// MARK: - 产品ID定义

struct ProductIDs {
    // 通讯设备（一次性购买）
    static let walkieTalkie = "com.tuzi.device.walkietalkie"
    static let campRadio = "com.tuzi.device.campradio"
    static let cellphone = "com.tuzi.device.cellphone"

    // 所有产品ID列表
    static let all: [String] = [
        walkieTalkie,
        campRadio,
        cellphone
    ]

    // 产品ID到设备类型的映射
    static func deviceType(for productID: String) -> DeviceType? {
        switch productID {
        case walkieTalkie: return .walkieTalkie
        case campRadio: return .campRadio
        case cellphone: return .cellphone
        default: return nil
        }
    }

    // 产品ID到设备名称的映射
    static func deviceName(for productID: String) -> String? {
        switch productID {
        case walkieTalkie: return "对讲机"
        case campRadio: return "营地电台"
        case cellphone: return "手机通讯"
        default: return nil
        }
    }

    // 产品ID到通讯范围的映射
    static func rangeKm(for productID: String) -> Double {
        switch productID {
        case walkieTalkie: return 3.0
        case campRadio: return 30.0
        case cellphone: return 100.0
        default: return 0
        }
    }
}

// MARK: - 购买状态

enum PurchaseStatus: Equatable {
    case idle
    case loading
    case purchasing
    case success(String)
    case failed(String)
}

// MARK: - StoreKitManager

@MainActor
class StoreKitManager: ObservableObject {

    // MARK: - 单例
    static let shared = StoreKitManager()

    // MARK: - Published 属性
    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var purchaseStatus: PurchaseStatus = .idle
    @Published var isLoading: Bool = false

    // MARK: - 私有属性
    private var transactionListener: Task<Void, Error>?

    // MARK: - 初始化
    private init() {
        print("🛒 [StoreKitManager] 初始化")

        // 启动交易监听
        transactionListener = listenForTransactions()

        // 加载产品
        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - 加载产品

    func loadProducts() async {
        isLoading = true

        do {
            print("🛒 [StoreKitManager] 加载产品列表...")
            let storeProducts = try await Product.products(for: ProductIDs.all)

            // 按价格排序
            products = storeProducts.sorted { $0.price < $1.price }

            print("✅ [StoreKitManager] 加载了 \(products.count) 个产品")
            for product in products {
                print("   - \(product.displayName): \(product.displayPrice)")
            }
        } catch {
            print("❌ [StoreKitManager] 加载产品失败: \(error)")
        }

        isLoading = false
    }

    // MARK: - 购买产品

    func purchase(_ product: Product) async -> Bool {
        purchaseStatus = .purchasing

        do {
            print("🛒 [StoreKitManager] 开始购买: \(product.displayName)")

            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                // 验证交易
                let transaction = try checkVerified(verification)

                // 更新已购买列表
                purchasedProductIDs.insert(product.id)

                // 添加设备到数据库
                await addDeviceToDatabase(productID: product.id)

                // 完成交易
                await transaction.finish()

                purchaseStatus = .success(product.displayName)
                print("✅ [StoreKitManager] 购买成功: \(product.displayName)")
                return true

            case .userCancelled:
                purchaseStatus = .idle
                print("⚠️ [StoreKitManager] 用户取消购买")
                return false

            case .pending:
                purchaseStatus = .idle
                print("⏳ [StoreKitManager] 购买待处理")
                return false

            @unknown default:
                purchaseStatus = .failed("未知状态")
                return false
            }
        } catch {
            purchaseStatus = .failed(error.localizedDescription)
            print("❌ [StoreKitManager] 购买失败: \(error)")
            return false
        }
    }

    // MARK: - 恢复购买

    func restorePurchases() async {
        purchaseStatus = .loading

        do {
            print("🛒 [StoreKitManager] 恢复购买...")
            try await AppStore.sync()
            await updatePurchasedProducts()
            purchaseStatus = .success("恢复完成")
            print("✅ [StoreKitManager] 恢复购买完成")
        } catch {
            purchaseStatus = .failed(error.localizedDescription)
            print("❌ [StoreKitManager] 恢复购买失败: \(error)")
        }
    }

    // MARK: - 检查是否已购买

    func isPurchased(_ productID: String) -> Bool {
        // 先检查 StoreKit 记录
        if purchasedProductIDs.contains(productID) {
            return true
        }

        // 再检查数据库中是否已有该设备
        if let deviceType = ProductIDs.deviceType(for: productID) {
            let hasDevice = DeviceManager.shared.devices.contains { $0.deviceType == deviceType }
            return hasDevice
        }

        return false
    }

    // MARK: - 私有方法

    /// 监听交易更新
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try await self.checkVerified(result)

                    await MainActor.run {
                        self.purchasedProductIDs.insert(transaction.productID)
                    }

                    // 添加设备到数据库
                    await self.addDeviceToDatabase(productID: transaction.productID)

                    await transaction.finish()
                    print("🛒 [StoreKitManager] 交易更新: \(transaction.productID)")
                } catch {
                    print("❌ [StoreKitManager] 交易验证失败: \(error)")
                }
            }
        }
    }

    /// 验证交易
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }

    /// 更新已购买产品列表
    private func updatePurchasedProducts() async {
        var purchased: Set<String> = []

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                purchased.insert(transaction.productID)
            } catch {
                print("❌ [StoreKitManager] 验证权益失败: \(error)")
            }
        }

        purchasedProductIDs = purchased
        print("🛒 [StoreKitManager] 已购买产品: \(purchased)")
    }

    /// 购买成功后添加设备到数据库
    private func addDeviceToDatabase(productID: String) async {
        guard let deviceType = ProductIDs.deviceType(for: productID),
              let deviceName = ProductIDs.deviceName(for: productID),
              let userId = await SupabaseManager.shared.getCurrentUserId() else {
            print("❌ [StoreKitManager] 无法添加设备：信息不完整")
            return
        }

        let rangeKm = ProductIDs.rangeKm(for: productID)

        do {
            try await addDeviceViaREST(
                userId: userId,
                deviceType: deviceType.rawValue,
                deviceName: deviceName,
                rangeKm: rangeKm
            )

            // 刷新设备列表
            await DeviceManager.shared.loadDevices()

            print("✅ [StoreKitManager] 设备已添加到数据库: \(deviceName)")
        } catch {
            print("❌ [StoreKitManager] 添加设备到数据库失败: \(error)")
        }
    }

    /// 通过 REST API 添加设备
    private func addDeviceViaREST(userId: UUID, deviceType: String, deviceName: String, rangeKm: Double) async throws {
        let url = SupabaseConfig.supabaseURL
            .appendingPathComponent("rest/v1/player_devices")

        let body: [String: Any] = [
            "user_id": userId.uuidString,
            "device_type": deviceType,
            "device_name": deviceName,
            "range_km": rangeKm,
            "battery_level": 100.0,
            "signal_strength": 100.0,
            "is_active": true
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        if let accessToken = try? await SupabaseManager.shared.client.auth.session.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(SupabaseConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw StoreError.databaseError
        }
    }

    // MARK: - 调试方法

    func printStatus() {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🛒 StoreKitManager 状态")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("产品数量: \(products.count)")
        print("已购买: \(purchasedProductIDs)")
        print("购买状态: \(purchaseStatus)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}

// MARK: - 错误类型

enum StoreError: LocalizedError {
    case verificationFailed
    case databaseError
    case unknown

    var errorDescription: String? {
        switch self {
        case .verificationFailed:
            return "购买验证失败"
        case .databaseError:
            return "数据库操作失败"
        case .unknown:
            return "未知错误"
        }
    }
}
