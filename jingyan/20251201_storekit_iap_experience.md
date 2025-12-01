# StoreKit 2 内购 (IAP) 开发经验总结

**日期**: 2025年12月1日
**项目**: tuzi-fuke (地球新主复刻版)
**功能**: 应用内购买通讯设备

---

## 背景

游戏需要付费系统，让玩家购买通讯设备：

| 设备 | 价格 | 通讯范围 |
|------|------|----------|
| 对讲机 | $0.99 | 3km |
| 营地电台 | $2.99 | 30km |
| 手机通讯 | $4.99 | 100km |

选择 **StoreKit 2** 而非 StoreKit 1，因为：
- 更现代的 async/await API
- 自动收据验证
- 更简洁的代码

---

## 与 AI 协作的问题发现与解决

### 问题1: 内购是不是要先上架 App Store？

**我的疑问**:
> "如果我要做这个...是不是要先上架？联通 App Store 之类的？"

**AI 的解答**:

开发阶段**不需要上架**，有两种测试方式：

1. **Xcode StoreKit 配置文件** - 完全本地，不需要 App Store Connect
2. **沙盒测试** - 需要在 App Store Connect 创建产品

推荐先用方案1，简单快速。

### 问题2: 如何创建 StoreKit 配置文件？

**我的问题**:
> "这里好像没有，你可以帮我创建吗？" （截图显示 Xcode 新建文件菜单）

**AI 的指导**:

在 Xcode 中创建 StoreKit Configuration File：

1. File → New → File
2. 搜索 "StoreKit"
3. 选择 "StoreKit Configuration File"
4. 命名为 `Products.storekit`
5. 保存到项目根目录

然后添加产品：
1. 点击左下角 "+" 按钮
2. 选择 "Add Non-Consumable In-App Purchase"
3. 填写 Reference Name 和 Product ID

### 问题3: Product ID 的命名规范

**AI 的建议**:

Product ID 使用反向域名格式：
```
com.tuzi.device.walkietalkie   # 对讲机
com.tuzi.device.campradio      # 营地电台
com.tuzi.device.cellphone      # 手机通讯
```

**重要**: Product ID 一旦设定不要改，会与 App Store 记录关联。

### 问题4: 如何让 Xcode 使用配置文件？

**我的问题**:
> "这个在哪里？"（关于 Scheme 设置）

**设置步骤**:

1. Product → Scheme → Edit Scheme...
2. 选择 "Run" 配置
3. Options 标签页
4. "StoreKit Configuration" 下拉框
5. 选择 `Products.storekit`

### 问题5: 缺少 import 导致编译错误

**错误信息**:
```
Cannot find 'SupabaseManager' in scope
Cannot find type 'RealtimeChannelV2' in scope
```

**原因**: StoreKitManager.swift 缺少 import

**修复**:
```swift
import Foundation
import StoreKit
import Combine    // ← 添加
import Supabase   // ← 添加
```

---

## 技术实现要点

### 1. 产品 ID 定义

```swift
struct ProductIDs {
    static let walkieTalkie = "com.tuzi.device.walkietalkie"
    static let campRadio = "com.tuzi.device.campradio"
    static let cellphone = "com.tuzi.device.cellphone"

    static let all: [String] = [walkieTalkie, campRadio, cellphone]

    // Product ID → 设备类型映射
    static func deviceType(for productID: String) -> DeviceType? {
        switch productID {
        case walkieTalkie: return .walkieTalkie
        case campRadio: return .campRadio
        case cellphone: return .cellphone
        default: return nil
        }
    }
}
```

### 2. StoreKit 管理器核心代码

```swift
@MainActor
class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()

    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var purchaseStatus: PurchaseStatus = .idle

    private var transactionListener: Task<Void, Error>?

    private init() {
        // 启动交易监听
        transactionListener = listenForTransactions()

        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }

    // 加载产品
    func loadProducts() async {
        let storeProducts = try await Product.products(for: ProductIDs.all)
        products = storeProducts.sorted { $0.price < $1.price }
    }

    // 购买产品
    func purchase(_ product: Product) async -> Bool {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            purchasedProductIDs.insert(product.id)

            // 添加设备到数据库
            await addDeviceToDatabase(productID: product.id)

            await transaction.finish()
            return true

        case .userCancelled, .pending:
            return false
        }
    }
}
```

### 3. 交易监听（处理中断的购买）

```swift
private func listenForTransactions() -> Task<Void, Error> {
    return Task.detached {
        for await result in Transaction.updates {
            let transaction = try await self.checkVerified(result)

            await MainActor.run {
                self.purchasedProductIDs.insert(transaction.productID)
            }

            await self.addDeviceToDatabase(productID: transaction.productID)
            await transaction.finish()
        }
    }
}
```

### 4. 购买后添加设备到数据库

```swift
private func addDeviceToDatabase(productID: String) async {
    guard let deviceType = ProductIDs.deviceType(for: productID),
          let deviceName = ProductIDs.deviceName(for: productID),
          let userId = await SupabaseManager.shared.getCurrentUserId() else {
        return
    }

    let rangeKm = ProductIDs.rangeKm(for: productID)

    // 通过 REST API 插入设备
    let body: [String: Any] = [
        "user_id": userId.uuidString,
        "device_type": deviceType.rawValue,
        "device_name": deviceName,
        "range_km": rangeKm,
        "battery_level": 100.0,
        "is_active": true
    ]

    // POST to Supabase
    try await addDeviceViaREST(...)

    // 刷新设备列表
    await DeviceManager.shared.loadDevices()
}
```

### 5. 商店界面 (DeviceStoreView)

```swift
struct DeviceStoreView: View {
    @StateObject private var storeManager = StoreKitManager.shared

    var body: some View {
        NavigationView {
            ScrollView {
                ForEach(storeManager.products, id: \.id) { product in
                    ProductCard(
                        product: product,
                        isPurchased: storeManager.isPurchased(product.id),
                        onPurchase: {
                            Task {
                                await storeManager.purchase(product)
                            }
                        }
                    )
                }

                // 恢复购买按钮
                Button("恢复购买") {
                    Task {
                        await storeManager.restorePurchases()
                    }
                }
            }
        }
    }
}
```

---

## StoreKit 配置文件内容

`Products.storekit` 文件的 JSON 结构：

```json
{
  "products": [
    {
      "displayPrice": "0.99",
      "familyShareable": false,
      "internalID": "...",
      "localizations": [
        {
          "description": "短距离双向通讯设备",
          "displayName": "对讲机",
          "locale": "zh_CN"
        }
      ],
      "productID": "com.tuzi.device.walkietalkie",
      "referenceName": "对讲机",
      "type": "NonConsumable"
    }
    // ... 其他产品
  ]
}
```

---

## 完整的 IAP 流程

```
用户点击购买
    ↓
StoreKitManager.purchase()
    ↓
product.purchase() → Apple 弹出确认框
    ↓
用户确认/取消
    ↓
验证交易 checkVerified()
    ↓
添加设备到 Supabase 数据库
    ↓
刷新 DeviceManager.loadDevices()
    ↓
自动切换到新设备（因为新设备可发送）
    ↓
transaction.finish() 完成交易
```

---

## 教学经验

### 1. 本地测试 vs 沙盒测试

| 方式 | 优点 | 缺点 |
|------|------|------|
| StoreKit 配置文件 | 无需网络、立即生效 | 仅限开发 |
| 沙盒测试 | 接近真实环境 | 需要 App Store Connect 配置 |

**建议**: 开发阶段用配置文件，上线前用沙盒测试。

### 2. 必须处理的场景

1. **交易监听**: 用户购买被中断（电话、后台等），下次启动要恢复
2. **恢复购买**: 用户换机或重装 App
3. **重复购买**: Non-Consumable 已购买不能再买

### 3. 调试技巧

在 StoreKit 配置文件中可以：
- 模拟购买失败
- 模拟网络延迟
- 清除购买记录（重新测试）

右键产品 → "Subscription Options" 或编辑器菜单。

### 4. 常见错误

**错误**: `Cannot find 'Product' in scope`
**原因**: 缺少 `import StoreKit`

**错误**: `products(for:) is unavailable`
**原因**: 目标版本太低，StoreKit 2 需要 iOS 15+

---

## 文件结构

```
tuzi-fuke/
├── Products.storekit          # StoreKit 配置文件
├── StoreKitManager.swift      # IAP 管理器
├── DeviceStoreView.swift      # 商店界面
├── ProductIDs.swift           # 产品 ID 定义（或放在 StoreKitManager 中）
└── ChatView.swift             # 聊天界面（添加升级按钮）
```

---

## 总结

### 完成的功能

- ✅ StoreKit 2 集成
- ✅ 3个 Non-Consumable 产品
- ✅ 本地测试配置
- ✅ 购买流程
- ✅ 恢复购买
- ✅ 购买后自动添加设备到数据库
- ✅ 商店界面 UI

### 关键点

1. **StoreKit 2 比 1 简单很多** - async/await + 自动验证
2. **配置文件开发很方便** - 不需要 App Store Connect
3. **交易监听必不可少** - 处理中断的购买
4. **购买后要同步数据库** - IAP 记录设备，Supabase 存储用户数据

### 上线前还需要

- 在 App Store Connect 创建真实产品
- 配置银行账户和税务信息
- 沙盒环境测试
- 提交审核
