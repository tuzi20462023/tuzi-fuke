# 通讯设备系统 L1 开发经验总结

**日期**: 2025年12月1日
**项目**: tuzi-fuke (地球新主复刻版)
**功能**: 通讯设备系统（收音机、对讲机、营地电台、手机）

---

## 背景

在完成基础聊天功能后，需要增加"通讯设备"概念，让游戏更有沉浸感：

- **小收音机**: 新玩家默认设备，只能收听，不能发送
- **对讲机**: 可收发，3km 范围
- **营地电台**: 可收发，30km 范围
- **手机通讯**: 可收发，100km 范围

核心设计：**不同设备有不同的通讯能力**，收音机玩家只能"听"不能"说"。

---

## 与 AI 协作的问题发现与解决

### 问题1: 收音机是干什么用的？

**我的困惑**:
> "在聊天界面有收音机了，但是我不明白收音机这个是干嘛用的？"

**AI 的解释**:

小收音机的设计目的：
1. **新手体验** - 让新玩家先观察聊天环境
2. **付费转化** - 想发言需要购买对讲机等设备
3. **游戏沉浸感** - 符合末日生存主题（收音机只能收听）

**关键理解**: 这是一个"先听后说"的游戏设计，引导玩家付费升级设备。

### 问题2: 购买设备后没有自动激活

**我的发现**:
> "我买了但是没有启用成功？"

控制台日志显示：
```
✅ [StoreKitManager] 设备已添加到数据库: 对讲机
✅ [StoreKitManager] 购买成功: 对讲机
✅ [DeviceManager] 加载了 2 个设备
📻 [DeviceManager] 当前激活设备: 小收音机  ← 问题：还是收音机
```

**问题定位**:

购买成功后调用了 `DeviceManager.loadDevices()`，设备列表加载正确（2个设备），但激活设备仍是收音机。

**根本原因**:

原代码只在 `activeDevice == nil` 时选择设备：
```swift
// 旧代码 - 只在没有激活设备时选择
if activeDevice == nil {
    activeDevice = devices.first(where: { $0.deviceType != .radio })
}
```

购买前已经有收音机作为激活设备，所以购买后不会切换。

**修复方案**:

每次加载都重新选择最佳设备：
```swift
// 新代码 - 每次都选择最佳设备
let bestDevice = devices.first(where: { $0.deviceType != .radio && $0.isActive })
    ?? devices.first(where: { $0.isActive })

if let best = bestDevice {
    activeDevice = best
}
```

### 问题3: 发送消息卡顿

**我的反馈**:
> "可以了，发送界面有点卡顿，你看看怎么优化一下"

**AI 分析的原因**:

1. **键盘收起阻塞UI** - `isInputFocused = false` 在主线程同步执行
2. **没有乐观更新** - 要等服务器返回才显示消息

**优化方案**:

1. 键盘异步收起：
```swift
// 异步收起键盘，避免阻塞UI
Task { @MainActor in
    isInputFocused = false
}
```

2. 乐观更新（Optimistic Update）：
```swift
// 立即在本地显示消息
let tempId = UUID()
let optimisticMessage = Message(
    id: tempId,
    senderId: userId,
    content: content,
    messageType: .broadcast,
    senderName: senderName,
    createdAt: Date()
)
messages.append(optimisticMessage)

do {
    try await messageUploader.upload(...)
} catch {
    // 发送失败，移除本地消息
    messages.removeAll { $0.id == tempId }
    throw error
}
```

---

## 技术实现要点

### 1. 数据库设计

使用 Supabase MCP 创建设备表：

```sql
CREATE TABLE player_devices (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id),
    device_type TEXT NOT NULL,
    device_name TEXT NOT NULL,
    range_km DOUBLE PRECISION DEFAULT 0,
    battery_level DOUBLE PRECISION DEFAULT 100,
    signal_strength DOUBLE PRECISION DEFAULT 100,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS 策略
ALTER TABLE player_devices ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own devices" ON player_devices
    FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own devices" ON player_devices
    FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
```

### 2. 设备模型 (CommunicationDevice.swift)

```swift
enum DeviceType: String, Codable, CaseIterable {
    case radio = "radio"           // 小收音机（只收）
    case walkieTalkie = "walkie_talkie"  // 对讲机
    case campRadio = "camp_radio"  // 营地电台
    case cellphone = "cellphone"   // 手机通讯

    var canSend: Bool {
        switch self {
        case .radio: return false  // 收音机不能发送
        default: return true
        }
    }

    var icon: String {
        switch self {
        case .radio: return "radio"
        case .walkieTalkie: return "antenna.radiowaves.left.and.right"
        case .campRadio: return "antenna.radiowaves.left.and.right.circle"
        case .cellphone: return "iphone.radiowaves.left.and.right"
        }
    }
}
```

### 3. 设备管理器核心逻辑

```swift
@MainActor
class DeviceManager: ObservableObject {
    @Published var devices: [CommunicationDevice] = []
    @Published var activeDevice: CommunicationDevice?

    /// 当前设备是否可以发送消息
    var canSendMessage: Bool {
        return activeDevice?.canSend ?? false
    }

    /// 获取不能发送的原因
    var cannotSendReason: String? {
        guard let device = activeDevice else {
            return "没有通讯设备"
        }
        if !device.deviceType.canSend {
            return "\(device.displayName)只能接收消息，无法发送"
        }
        return nil
    }
}
```

### 4. 聊天界面集成

在 ChatView 中检查设备能力：

```swift
// 输入栏禁用逻辑
TextField(
    deviceManager.canSendMessage ? "输入消息..." : "仅接收模式",
    text: $messageText
)
.disabled(!deviceManager.canSendMessage)

// 显示不能发送的原因
if !deviceManager.canSendMessage {
    HStack {
        Image(systemName: "exclamationmark.triangle.fill")
        Text(deviceManager.cannotSendReason ?? "无法发送")
    }
    .foregroundColor(.orange)
}
```

---

## 新玩家设备初始化

### 自动发放收音机

在用户注册成功后，自动添加默认收音机：

```swift
// AuthManager.swift - 注册成功后
private func createDefaultDevice(for userId: UUID) async {
    // 通过 REST API 插入默认收音机
    let body: [String: Any] = [
        "user_id": userId.uuidString,
        "device_type": "radio",
        "device_name": "小收音机",
        "range_km": Double.infinity,  // 收音机无限接收范围
        "is_active": true
    ]
    // POST to /rest/v1/player_devices
}
```

---

## 文件结构

```
tuzi-fuke/
├── CommunicationDevice.swift  # 设备数据模型
├── DeviceManager.swift        # 设备管理器
├── ChatManager.swift          # 聊天管理器（检查设备权限）
├── ChatView.swift             # 聊天界面（显示设备状态）
└── AuthManager.swift          # 认证管理（注册时发放设备）
```

---

## 教学经验

### 1. 问题定位的沟通技巧

当功能不符合预期时，提供**具体的日志输出**非常有帮助：

**好的反馈**:
> "我买了但是没有启用成功，日志显示加载了2个设备但激活的还是小收音机"

**不够好的反馈**:
> "购买没用"

### 2. 理解设计意图

遇到不理解的功能时，直接问 AI 设计目的：
> "收音机这个是干嘛用的？"

AI 会解释背后的游戏设计逻辑，帮助理解整体架构。

### 3. 乐观更新的概念

**传统方式**: 发送 → 等待服务器 → 等待 Realtime → 显示
**乐观更新**: 发送 → **立即本地显示** → 后台上传 → 失败则回滚

这是现代聊天应用的标准做法，提升用户体验。

---

## 总结

### 完成的功能

- ✅ 设备数据模型（4种设备类型）
- ✅ 设备管理器（加载、切换、权限检查）
- ✅ 收音机只收不发的限制
- ✅ 聊天界面显示设备状态
- ✅ 发送按钮根据设备能力禁用
- ✅ 购买设备后自动激活
- ✅ 发送消息性能优化（乐观更新）

### 关键代码修改

| 文件 | 修改内容 |
|------|----------|
| DeviceManager.swift | 每次加载都选择最佳设备 |
| ChatView.swift | 异步收起键盘 |
| ChatManager.swift | 乐观更新 |
| Message.swift | 添加本地初始化方法 |
