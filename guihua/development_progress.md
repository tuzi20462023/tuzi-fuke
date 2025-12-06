# 开发进展记录

**最后更新**: 2025年12月6日

---

## 当前状态总览

| 模块 | 状态 | 分支 | 备注 |
|------|------|------|------|
| **圈地功能** | ✅ 已完成 | 已合并到 main | L1-L4 已验证，L5-L6 待实测 |
| **探索功能** | 🚧 待开发 | feature/explore | 新分支已创建 |
| **通信功能** | 🚧 开发中 | feature/communication-L4-L5 已合并 | L2官方频道+L4附近玩家+L5私聊 已完成 |
| **建筑功能** | 🚧 开发中 | feature/building-system | L1-L4 核心功能已完成 |
| **AI打卡功能** | 🚧 开发中 | feature/building-system | 基础功能已完成，提示词待优化 |

---

## 圈地功能完成情况 (2025-12-01)

### 深度完成表

| 层级 | 模块 | 功能 | 状态 |
|------|------|------|------|
| **L1 追踪** | 开始/结束圈地按钮 | 基础UI控制 | ✅ |
| **L1 追踪** | 路径点记录 | GPS轨迹采集 | ✅ |
| **L1 追踪** | 实时路径显示 | 地图上绘制轨迹 | ✅ |
| **L2 验证-客户端** | 闭环检测(起终点≤30m) | 判断是否形成闭环 | ✅ |
| **L2 验证-客户端** | 最少点数检测(≥10个) | 防止无效圈地 | ✅ |
| **L2 验证-客户端** | 最小面积检测(≥100m²) | 防止过小圈地 | ✅ |
| **L3 验证-高级** | 路径自交叉检测 | 防止8字形轨迹 | ✅ |
| **L3 验证-高级** | 速度检测(防作弊) | 检测异常移动速度 | ✅ |
| **L4 上传** | GeoJSON→数据库 | Supabase写入 | ✅ |
| **L4 上传** | 面积/周长计算 | 几何属性计算 | ✅ |
| **L5 多人** | 与其他玩家领地碰撞检测 | 防止领地重叠 | ✅ (代码完成，待实测) |
| **L5 多人** | Edge Function验证 | 服务端二次验证 | ✅ (代码完成，待实测) |
| **L6 奖励** | 新手礼包(首个领地) | 首次圈地奖励 | ✅ (代码完成，待实测) |
| **L6 奖励** | 里程碑奖励 | 成就系统 | ✅ (代码完成，待实测) |

### 关键里程碑

- **2025-12-01 下午**: 完成实时碰撞检测功能
  - 每5秒检测一次碰撞
  - 分别检测他人领地和自己领地
  - 添加距离预警（100m/50m/25m）
  - 触觉反馈震动提醒

### PR 记录

| PR | 标题 | 状态 |
|----|------|------|
| [#1](https://github.com/tuzi20462023/tuzi-fuke/pull/1) | 完成圈地核心功能 (L1-L4) | ✅ 已合并 |

---

## 分支管理

### 当前 Worktree 结构

```
~/Desktop/
├── tuzi-fuke/                    # main 分支（稳定版）
├── tuzi-fuke-explore/            # feature/explore（探索功能开发）
└── tuzi-fuke-communication/      # feature/communication（通信功能开发）
```

### 已清理的分支

- `tuzi-fuke-claiming/` - 已合并到 main，worktree 已删除

---

## 通信功能完成情况 (2025-12-02)

### 深度完成表

| 层级 | 模块 | 功能 | 状态 |
|------|------|------|------|
| **L1 频道** | CommunicationHub | 通讯中心TabView界面 | ✅ |
| **L1 频道** | 频道列表 | 显示所有可用频道 | ✅ |
| **L2 官方频道** | ChannelChatView | 频道聊天界面 | ✅ |
| **L2 官方频道** | 消息发送 | 发送频道消息到Supabase | ✅ |
| **L2 官方频道** | Realtime订阅 | 实时接收新消息 | ✅ |
| **L3 公共频道** | 公共广场 | 面向所有玩家的频道 | ✅ |
| **L4 附近玩家** | NearbyPlayersView | 查找附近幸存者 | ✅ |
| **L4 附近玩家** | GPS距离计算 | Haversine公式 | ✅ |
| **L4 附近玩家** | 位置实时上报 | player_locations_realtime表 | ✅ |
| **L4 附近玩家** | 信号强度计算 | 基于距离和设备类型判断 | 🟡 基础实现 |
| **L5 私聊** | ConversationListView | 私聊对话列表 | ✅ |
| **L5 私聊** | DirectChatView | 一对一聊天界面 | ✅ |
| **L5 私聊** | DirectMessageManager | 私聊消息管理 | ✅ |
| **L5 私聊** | 消息路由 | 统一订阅+客户端过滤 | ❌ 未实现 |
| **L5 私聊** | 距离过滤 | 设备类型矩阵判断 | ❌ 未实现 |
| **L5 私聊** | 敏感词过滤 | 客户端/服务端过滤 | ❌ 未实现 |

### 关键里程碑

- **2025-12-02 上午**: 完成L4附近玩家 + L5私聊基础功能
  - 实现ConversationListView（使用sheet代替NavigationLink解决闪退）
  - 实现DirectChatView一对一聊天
  - 实现NearbyPlayersView附近玩家查找
  - GPS距离计算和位置实时上报

### L5 消息路由后续开发计划

基于源项目 `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/MessageRouterManager.swift` 分析，还需要实现以下功能：

#### 1. 统一订阅模式

当前问题：每个频道单独订阅，订阅数量多时性能差。

源项目方案：
```swift
// 统一订阅：只订阅一次 channel_messages 表
private var unifiedChannelSubscription: RealtimeChannelV2?
private var subscribedChannels: Set<UUID> = []  // 本地维护订阅列表

// 客户端过滤：收到消息后检查是否在订阅列表
guard subscribedChannels.contains(message.channelId) else {
    return  // 丢弃未订阅频道的消息
}
```

#### 2. 设备类型矩阵

根据发送者设备和接收者设备类型，决定通讯距离：

| 发送设备 | 接收设备 | 最大距离 |
|---------|---------|---------|
| 对讲机 | 对讲机 | 3km |
| 对讲机 | 营地电台 | 30km |
| 对讲机 | 卫星电话 | 100km |
| 营地电台 | 对讲机 | 30km |
| 营地电台 | 营地电台 | 30km |
| 营地电台 | 卫星电话 | 100km |
| 卫星电话 | 任意 | 100km |
| 收音机 | 任意 | ∞ (只接收) |

```swift
private func canReceiveMessage(
    senderDevice: DeviceType,
    myDevice: DeviceType,
    distance: Double
) -> Bool {
    switch (senderDevice, myDevice) {
    case (.walkieTalkie, .walkieTalkie):
        return distance <= 3.0
    case (.walkieTalkie, .campRadio):
        return distance <= 30.0
    // ... 更多组合
    }
}
```

#### 3. 距离过滤流程

```
收到新消息
    ↓
检查是否在订阅列表 → 否 → 丢弃
    ↓ 是
获取发送者设备类型和位置
    ↓
获取我的设备类型和位置
    ↓
计算距离（Haversine公式）
    ↓
查询设备矩阵判断是否在范围内
    ↓
范围内 → 显示消息
范围外 → 丢弃
```

#### 4. 敏感词过滤

源项目使用 `SensitiveWordFilter.shared.filterText(content)` 进行过滤：

```swift
let filterResult = SensitiveWordFilter.shared.filterText(content)
if !filterResult.passed {
    filteredContent = filterResult.filteredText  // 替换敏感词
} else {
    filteredContent = content
}
```

#### 5. 需要新建的文件

- [ ] `MessageRouterManager.swift` - 消息路由管理器
- [ ] `SensitiveWordFilter.swift` - 敏感词过滤器
- [ ] 数据库函数 `send_channel_message` 需要添加设备类型参数

#### 6. 需要修改的文件

- [ ] `DirectMessageManager.swift` - 整合到MessageRouter
- [ ] `ChannelMessage.swift` - 添加 senderDeviceType、senderLocation 字段
- [ ] `DirectMessage.swift` - 添加设备相关字段

---

## 建筑功能完成情况 (2025-12-03)

### 深度完成表

| 层级 | 模块 | 功能 | 状态 |
|------|------|------|------|
| **L1 模板** | 建筑模板定义 | BuildingTemplate 数据结构 | ✅ |
| **L1 模板** | 建筑列表UI | BuildingListView 分类展示 | ✅ |
| **L2 放置** | 建筑放置UI | BuildingPlacementView 地图选点 | ✅ |
| **L2 放置** | 位置验证(不重叠) | isLocationInTerritory() 射线法 | ✅ |
| **L2 放置** | 资源消耗检查 | requiredResources 字段定义 | 🟡 模板有字段，未实际扣除 |
| **L3 建造** | 建造计时 | BuildingManager 定时器 | ✅ |
| **L3 建造** | 建造进度显示 | BuildingDetailView 进度条 | ✅ |
| **L4 查询** | 领地建筑列表 | TerritoryBuildingsView | ✅ |
| **L4 查询** | 地图显示建筑 | MapViewRepresentable 标注 | ✅ |
| **L5 高级** | 建筑升级 | 升级按钮UI | 🟡 UI完成，逻辑TODO |
| **L5 高级** | 建筑效果(存储容量等) | effects 字段 + displayString | ✅ |
| **L5 高级** | AI生成建筑图片 | - | ❌ 未实现 |
| **L5 高级** | 维修功能 | 维修按钮UI | 🟡 UI完成，逻辑TODO |
| **L5 高级** | 拆除功能 | 拆除按钮UI | 🟡 UI完成，逻辑TODO |

### 关键里程碑

- **2025-12-03 上午**: 完成建筑系统核心功能
  - 修复建筑效果显示格式问题 (`+AnyCodableValue(value: 50)` → `+50`)
  - 修复建筑位置偏移900米问题（坐标系统统一为GCJ-02存储）
  - 修复领地边界显示问题（WGS-84转GCJ-02）
  - 修复位置验证坐标系不一致问题

### 核心技术点

#### 坐标系统处理

| 场景 | 坐标系 | 说明 |
|------|--------|------|
| GPS原始数据 | WGS-84 | iOS CLLocationManager 返回 |
| 数据库存储（领地） | WGS-84 | GPS路径直接存储 |
| 数据库存储（建筑） | GCJ-02 | 地图点击坐标直接存储 |
| 地图显示 | GCJ-02 | MapKit在中国使用 |

数据流：
```
领地数据: GPS采集(WGS-84) → 存储(WGS-84) → 显示时转换(GCJ-02)
建筑数据: 地图点击(GCJ-02) → 存储(GCJ-02) → 显示时直接用(GCJ-02)
```

#### AnyCodableValue 类型处理

```swift
// Building.swift 中添加 displayString 属性
var displayString: String {
    if let intVal = value as? Int {
        return "\(intVal)"
    } else if let doubleVal = value as? Double {
        return String(format: "%.1f", doubleVal)
    }
    // ...
}
```

### 文件清单

| 文件 | 用途 | 状态 |
|------|------|------|
| `Building.swift` | 数据模型 | ✅ 已完成 |
| `BuildingManager.swift` | 业务逻辑 | ✅ 已完成 |
| `BuildingListView.swift` | 建筑列表 | ✅ 已完成 |
| `BuildingPlacementView.swift` | 放置界面 | ✅ 已完成 |
| `BuildingDetailView.swift` | 详情页 | ✅ 已完成 |
| `TerritoryBuildingsView.swift` | 领地建筑 | ✅ 已完成 |
| `MapViewRepresentable.swift` | 地图显示 | ✅ 已完成 |

### L5 后续开发计划

#### 1. 资源消耗检查

需要对接资源系统，建造时扣除资源：

```swift
// BuildingManager.swift
func startConstruction(request: BuildingConstructionRequest) async -> BuildingConstructionResult {
    // TODO: 检查玩家资源是否足够
    // TODO: 扣除资源
    // 目前直接跳过资源检查
}
```

#### 2. 建筑升级逻辑

`BuildingDetailView.swift:276` 有 TODO：

```swift
Button {
    // TODO: 实现升级逻辑
    // 1. 检查升级资源需求
    // 2. 扣除资源
    // 3. 更新建筑等级
    // 4. 更新建筑效果
} label: {
    Text("升级建筑")
}
```

#### 3. 维修功能

`BuildingDetailView.swift:293` 有 TODO：

```swift
// TODO: 实现维修逻辑
// 1. 检查维修资源需求
// 2. 扣除资源
// 3. 恢复耐久度
```

#### 4. 拆除功能

`BuildingDetailView.swift:309` 有 TODO：

```swift
// TODO: 实现拆除逻辑
// 1. 确认拆除（弹窗）
// 2. 返还部分资源
// 3. 删除建筑数据
```

#### 5. AI生成建筑图片

可选功能，使用AI根据建筑类型生成图标。

---

## AI 打卡明信片功能完成情况 (2025-12-05~06)

### 深度完成表

| 层级 | 模块 | 功能 | 状态 |
|------|------|------|------|
| **L1 基础** | Edge Function | generate-checkin-image 函数 | ✅ |
| **L1 基础** | Gemini API 调用 | @google/genai SDK | ✅ |
| **L1 基础** | 图片上传 | Supabase Storage | ✅ |
| **L2 iOS端** | GeminiService | 调用 Edge Function | ✅ |
| **L2 iOS端** | CheckinManager | 打卡管理器 | ✅ |
| **L2 iOS端** | CheckinView | 打卡界面 | ✅ |
| **L3 头像** | AvatarManager | 头像上传管理 | ✅ |
| **L3 头像** | AvatarSettingsView | 头像设置界面 | ✅ |
| **L4 缓存** | CheckinDataStore | SwiftData 本地缓存 | ✅ |
| **L4 缓存** | 后台同步 | 异步同步到云端 | ✅ |
| **L5 优化** | 卡通风格提示词 | 生成动漫风格图片 | 🔴 待优化 |
| **L5 优化** | 打卡界面UI | 界面美化和交互优化 | 🔴 待优化 |
| **L5 优化** | 城市名称获取 | 动态获取城市名用于文字 | 🔴 待优化 |

### 关键里程碑

- **2025-12-05 晚**: 完成 AI 打卡基础功能
  - 创建 Edge Function 调用 Gemini API
  - 实现 iOS 端调用和图片展示
  - 实现头像上传和管理

- **2025-12-06 凌晨**: 完成本地缓存和提示词优化
  - 实现 SwiftData 本地缓存
  - 实现后台异步同步
  - 多次优化卡通风格提示词（仍有问题）

### 待优化项目

#### 1. 卡通风格提示词优化 🔴

**当前问题**: 提示词明确要求卡通/动漫风格，但 Gemini 仍然生成写实照片风格。

**已尝试的方案**:
- 使用警告符号 ⚠️🚨 强调
- 多次重复 "NOT a photo"
- 给具体参考（吉卜力、新海诚、迪士尼）
- 描述卡通特征（大眼睛、简化五官、cell-shading）
- 两层提示词双重强调

**可能的原因**:
- 传入真人头像时，Gemini 倾向保持"真实感"
- 模型对卡通风格的理解与预期不同

**后续方案**:
- [ ] 尝试不传头像，只生成卡通风景
- [ ] 尝试用文字描述人物特征代替照片
- [ ] 尝试分两步：先生成背景，再用其他方式处理人物
- [ ] 研究其他 AI 模型的卡通化能力

#### 2. 打卡界面 UI 优化 🔴

**待优化内容**:
- [ ] 生成中的加载动画和进度提示
- [ ] 生成结果展示界面美化
- [ ] 历史记录列表优化
- [ ] 分享功能完善
- [ ] 删除确认弹窗

#### 3. 城市名称动态获取 🔴

**当前问题**: 提示词中城市名硬编码为"惠州"

**解决方案**:
- [ ] iOS 端使用 CLGeocoder 反向地理编码获取城市名
- [ ] 将城市名传给 Edge Function
- [ ] 提示词中使用动态城市名

```swift
// 示例代码
let geocoder = CLGeocoder()
let placemarks = try await geocoder.reverseGeocodeLocation(location)
let city = placemarks.first?.locality ?? "Unknown"
```

#### 4. 每日打卡次数限制 🟡

**当前状态**: 数据库有 `daily_checkin_limits` 表，但前端限制逻辑需要验证。

- [ ] 验证每日限制是否生效
- [ ] 添加次数耗尽的提示
- [ ] 添加次数刷新倒计时

### 技术架构

```
用户点击建筑生成明信片
        ↓
iOS App (GeminiService)
        ↓ HTTP POST (坐标 + 头像 base64)
Supabase Edge Function (generate-checkin-image)
        ↓ 调用 Gemini API (gemini-2.0-flash-exp)
生成图片
        ↓ 上传到 Storage (checkin-photos bucket)
返回图片 URL
        ↓
保存到本地 SwiftData (状态: pending)
        ↓
UI 立即更新
        ↓
后台 Task 异步同步到 Supabase (checkin_photos 表)
        ↓
同步成功后更新状态为 synced
```

### 文件清单

| 文件 | 用途 | 状态 |
|------|------|------|
| `supabase/functions/generate-checkin-image/index.ts` | Edge Function | ✅ |
| `tuzi-fuke/GeminiService.swift` | API 调用 | ✅ |
| `tuzi-fuke/CheckinManager.swift` | 打卡管理 | ✅ |
| `tuzi-fuke/CheckinDataStore.swift` | 本地缓存 | ✅ |
| `tuzi-fuke/CheckinModels.swift` | 数据模型 | ✅ |
| `tuzi-fuke/CheckinView.swift` | 打卡界面 | 🔴 待优化 |
| `tuzi-fuke/AvatarManager.swift` | 头像管理 | ✅ |
| `tuzi-fuke/AvatarSettingsView.swift` | 头像设置 | ✅ |

### 相关文档

- 经验文档: `jingyan/20251206_ai_checkin_postcard_experience.md`
- 教学文档: `jiaoxue/DAY10_AI_CHECKIN_POSTCARD_TUTORIAL.md`
- 提示词手册: `jiaoxue/DAY10_AI_CHECKIN_POSTCARD_PROMPT.md`

---

## 下一步计划

### 建筑功能后续（优先）

- [ ] **资源消耗检查** - 建造时扣除资源
- [ ] **建筑升级逻辑** - 等级提升和效果增强
- [ ] **维修功能** - 恢复耐久度
- [ ] **拆除功能** - 确认弹窗 + 部分资源返还

### AI 打卡功能后续（优先）

- [ ] **卡通风格提示词优化** - 解决写实照片问题
- [ ] **打卡界面 UI 优化** - 加载动画、结果展示、历史列表
- [ ] **城市名称动态获取** - CLGeocoder 反向地理编码
- [ ] **每日次数限制验证** - 确保限制生效

### 探索功能 (feature/explore)

待规划...

### 通信功能后续

- [ ] L5消息路由完整实现
  - [ ] 创建MessageRouterManager
  - [ ] 实现统一订阅模式
  - [ ] 实现设备类型矩阵判断
  - [ ] 实现距离过滤
- [ ] 敏感词过滤系统
- [ ] 信号强度可视化优化

### 圈地功能后续

- [ ] 多人碰撞检测实测（需要另一个用户的领地）
- [ ] 奖励系统实测
- [ ] 性能优化（大量领地时的检测效率）

---

## 相关文档

- 经验文档: `jingyan/20251201_realtime_collision_detection_experience.md`
- 经验文档: `jingyan/20251202_direct_chat_experience.md`
- 经验文档: `jingyan/20251203_building_system_experience.md`
- 经验文档: `jingyan/20251206_ai_checkin_postcard_experience.md`
- 教学文档: `jiaoxue/DAY4_CLAIMING_COLLISION_TUTORIAL.md`
- 教学文档: `jiaoxue/DAY7_DIRECT_CHAT_TUTORIAL.md`
- 教学文档: `jiaoxue/DAY8_BUILDING_SYSTEM_TUTORIAL.md`
- 教学文档: `jiaoxue/DAY10_AI_CHECKIN_POSTCARD_TUTORIAL.md`
- Git Worktree 经验: `jingyan/20251201_git_worktree_experience.md`
