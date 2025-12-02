# POI 探索发现系统开发经验总结

**日期**: 2025年12月2日
**项目**: tuzi-fuke (地球新主复刻版)
**功能**: POI 发现系统 - MapKit 搜索、Supabase 存储、100米触发发现

---

## 背景

在完成圈地功能后，需要实现 POI（Point of Interest）探索发现功能：

- 使用 MapKit 搜索附近真实商户（药店、超市、医院等）
- 将搜索结果提交到 Supabase 数据库
- 玩家走到 100 米范围内时触发"发现"弹窗
- 记录玩家的发现历史

---

## 与AI对话的经验

### 1. 提供完整的错误日志

**错误示范**:

```
POI提交失败了
```

**正确示范**:

```
POI候选提交失败，日志如下：
[粘贴完整的控制台日志]
错误信息：unexpectedDatabaseError "No data in response"
```

**效果**: 完整日志让AI能看到具体错误码，快速定位是网络问题、解码问题还是数据库问题。

### 2. 明确区分"预期行为"和"实际行为"

**错误示范**:

```
POI弹窗有bug
```

**正确示范**:

```
POI发现弹窗的问题：
预期：我走到药店附近（100米）时弹出发现提示
实际：每次开始探索就立即弹出附近所有POI，不是我走过去才弹

我测试了3次：
1. 第一次开探索 → 立即弹出2个药房
2. 第二次开探索 → 又弹出美宜佳
3. 华润万家我路过了但没弹
```

**效果**: 清晰的测试步骤让AI理解问题的本质，而不是表面现象。

### 3. 让AI阅读原项目代码

**有效的提示词模式**:

```
请阅读原项目 /Users/mikeliu/Desktop/tuzi-earthlord 的以下文件：
- ExplorationManager.swift（100米触发机制）
- DiscoveryManager.swift（POI发现逻辑）

分析它是怎么处理"走入范围才触发"的，我们的实现哪里不对。
```

**效果**: AI对比两个实现后，发现原项目用 `triggeredTargets` Set 记录已触发的目标，离开 200 米后才重置。

### 4. 让AI先分析再改代码

**有效的提示词模式**:

```
先不要写代码，先看看源代码，看看这块还有什么问题
```

**效果**: AI会详细分析代码逻辑、列出所有潜在问题，而不是直接修改可能改错的地方。

### 5. 提供截图验证功能

**有效的提示词模式**:

```
[截图1: 发现POI弹窗]
[截图2: 第二个发现弹窗]

我回来了，功能是这样的：刚路过两个药房都弹了，
但华润万家没弹，帮我看看是怎么回事
```

**效果**: 截图让AI看到实际界面，确认功能确实在工作，只是行为逻辑需要调整。

---

## 技术实现经验

### 1. 数据库设计

**三张核心表**:

```sql
-- 1. POI候选表（MapKit搜索结果）
mapkit_poi_candidates (
    id UUID PRIMARY KEY,
    name TEXT,
    poi_type TEXT,  -- hospital, pharmacy, supermarket...
    address TEXT,
    latitude DOUBLE,
    longitude DOUBLE,
    grid_key TEXT UNIQUE,  -- 用于去重
    submitted_by UUID,
    processed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ
)

-- 2. 正式POI表（用于发现）
pois (
    id UUID PRIMARY KEY,
    name TEXT,
    type TEXT,  -- 注意：pois表有类型约束
    description TEXT,
    latitude DOUBLE,
    longitude DOUBLE,
    is_active BOOLEAN DEFAULT TRUE,
    total_items INT DEFAULT 100,
    remaining_items INT DEFAULT 100
)

-- 3. 用户发现记录表
user_poi_discoveries (
    id UUID PRIMARY KEY,
    user_id TEXT,
    poi_id TEXT,
    poi_name TEXT,
    poi_type TEXT,
    latitude DOUBLE,
    longitude DOUBLE,
    discovered_at TIMESTAMPTZ
)
```

**关键点**:

- `grid_key` 用于去重（名称+坐标3位小数）
- `pois` 表的 `type` 字段有约束，只允许特定值
- `processed` 字段标记候选是否已创建为正式POI

### 2. POI类型约束问题

**踩坑**: MapKit 搜索返回的 `pharmacy` 类型，插入 `pois` 表时失败

**原因**: `pois` 表有类型约束：

```sql
CHECK (type IN ('hospital', 'supermarket', 'factory', 'restaurant', 'gas_station', 'school', 'park', 'other'))
```

**解决方案**: 迁移数据时映射类型

```sql
-- 将 pharmacy 映射为 hospital（都是医疗相关）
-- 将 convenience_store 映射为 supermarket（都是零售）
INSERT INTO pois (...)
SELECT
    CASE poi_type
        WHEN 'pharmacy' THEN 'hospital'
        WHEN 'convenience_store' THEN 'supermarket'
        ELSE poi_type
    END as type,
    ...
FROM mapkit_poi_candidates
```

### 3. 100米触发机制（核心问题）

**原始问题**: 每次开始探索立即弹出附近所有POI

**根本原因**:

1. `resetForNewExploration()` 清空了 `lastCheckLocation`
2. 第一次检查时没有移动距离限制，直接通过
3. 立即检测100米范围内所有未发现的POI

**原项目的设计**（ExplorationManager.swift 第670-688行）:

```swift
// 使用 triggeredTargets Set 记录已触发的目标
private var triggeredTargets: Set<String> = []
private let resetDistance: Double = 200  // 离开200米后重置

// 100米内触发一次后，不会重复触发
if distance <= triggerDistance {
    let targetId = "poi_\(poi.id)"
    if !triggeredTargets.contains(targetId) {
        triggerTarget(.poi(poi, ...))
        triggeredTargets.insert(targetId)
    }
}

// 超过200米后清理（允许再次触发）
func cleanupDistantTargets(currentLocation: CLLocation) {
    for targetId in triggeredTargets {
        if distance > resetDistance {
            targetsToRemove.insert(targetId)
        }
    }
    triggeredTargets.subtract(targetsToRemove)
}
```

**我们的修复方案**:

```swift
// POIManager.swift

// 1. 新增触发记录集合
private var triggeredPOIIds: Set<UUID> = []
private let resetDistance: Double = 200

// 2. 检查时跳过已触发的
func checkNearbyPOIs(location: CLLocation, userId: UUID) async -> POI? {
    // 先清理远离的POI
    cleanupDistantTriggeredPOIs(currentLocation: currentLocation)

    for poi in cachedPOIs {
        // 跳过已发现的（数据库记录）
        if discoveredPOIIds.contains(poi.id) { continue }

        // 跳过已触发的（本次会话中已弹过）
        if triggeredPOIIds.contains(poi.id) { continue }

        if distance <= discoveryRange {
            triggeredPOIIds.insert(poi.id)  // 标记为已触发
            await markPOIDiscovered(poi: poi, userId: userId)
            return poi
        }
    }
    return nil
}

// 3. 应用启动时预标记已在范围内的POI
func markNearbyPOIsAsTriggered(location: CLLocation) {
    for poi in cachedPOIs where distance <= discoveryRange {
        triggeredPOIIds.insert(poi.id)
    }
}

// 4. 开始探索时不清空触发记录
func resetForNewExploration() {
    lastCheckLocation = nil
    // 不清空 triggeredPOIIds！
}
```

### 4. Swift 6 并发问题

**踩坑**: Supabase SDK 的 `insert().execute()` 返回空响应导致解码错误

**错误信息**:

```
unexpectedDatabaseError("No data in response")
```

**原因**: 使用 `returning: .minimal` 时，SDK 尝试解码空响应

**解决方案**: 使用数组插入 + select

```swift
// 错误方式
try await supabase.database
    .from("table")
    .insert(data)
    .returning(.minimal)  // 导致解码错误
    .execute()

// 正确方式（参考 PositionRepository）
try await supabase.database
    .from("table")
    .insert([data])  // 数组形式
    .select()        // 返回插入的数据
    .execute()
```

### 5. 坐标系转换

**问题**: GPS 返回 WGS-84 坐标，MapKit 和国内地图使用 GCJ-02 坐标

**解决方案**: 统一使用 GCJ-02

```swift
// 搜索POI时转换
let gcjCoord = CoordinateConverter.wgs84ToGcj02(location.coordinate)

// 检查距离时也要转换
let gcjCoord = CoordinateConverter.wgs84ToGcj02(location.coordinate)
let currentLocation = CLLocation(latitude: gcjCoord.latitude, longitude: gcjCoord.longitude)

// POI坐标已经是 GCJ-02（MapKit返回的）
let poiLocation = CLLocation(latitude: poi.latitude, longitude: poi.longitude)
let distance = currentLocation.distance(from: poiLocation)
```

---

## 遇到的问题清单

| 问题             | 原因                           | 解决方案                            |
| -------------- | ---------------------------- | ------------------------------- |
| POI候选提交失败      | `returning: .minimal` 导致解码错误 | 改用 `insert([data]).select()`    |
| pharmacy类型插入失败 | pois表有类型约束                   | 映射为 hospital 类型                 |
| 每次开始探索立即弹窗     | 没有触发记录机制                     | 新增 triggeredPOIIds Set          |
| 华润万家没弹         | 可能超出100米或坐标偏移                | 检查距离计算和坐标转换                     |
| 重复弹出同一个POI     | discoveredPOIIds 只检查数据库      | 增加 triggeredPOIIds 本地检查         |
| 首次定位就弹窗        | 没有预标记已在范围内的POI               | 启动时调用 markNearbyPOIsAsTriggered |

---

## 文件结构

```
tuzi-fuke/
├── POIManager.swift           # POI管理器（搜索/缓存/发现）
├── POI.swift                  # POI数据模型
├── CoordinateConverter.swift  # 坐标转换工具
└── SimpleMapView.swift        # 地图界面（POI发现弹窗）
```

---

## 开发工作流

### 1. 先让功能跑起来

不要追求完美，先实现基础流程：

- MapKit 能搜索到数据
- 数据能存到数据库
- 弹窗能显示

### 2. 用日志驱动调试

在关键位置打印日志：

```swift
appLog(.info, category: "POI", message: "📍 首次定位成功，开始搜索附近 POI...")
appLog(.success, category: "POI发现", message: "🎉 发现POI: \(poi.name), 距离: \(Int(distance))米")
appLog(.debug, category: "POI发现", message: "🔍 检查附近POI... 缓存: \(cachedPOIs.count)个, 已发现: \(discoveredPOIIds.count)个, 已触发: \(triggeredPOIIds.count)个")
```

### 3. 让AI查数据库验证

```
帮我查一下 Supabase 数据库：
1. mapkit_poi_candidates 表有多少条记录？
2. pois 表有多少条记录？
3. user_poi_discoveries 表有我的发现记录吗？
```

### 4. 对比原项目实现

遇到逻辑问题时，让AI阅读原项目代码：

```
请阅读原项目的 ExplorationManager.swift 和 DiscoveryManager.swift，
分析它的100米触发机制是怎么实现的，和我们的有什么区别。
```

---

## 核心经验总结

### 技术经验

1. **触发记录用 Set 而非只检查数据库**: 本地 `triggeredPOIIds` + 数据库 `discoveredPOIIds` 双重检查
2. **200米重置机制**: 用户离开200米后才允许再次触发，避免反复弹窗
3. **预标记已在范围内的POI**: 应用启动时标记，防止首次探索立即弹窗
4. **坐标系要统一**: GPS(WGS-84) → 地图(GCJ-02)，否则距离计算不准
5. **Supabase 插入用数组+select**: 避免 `returning: .minimal` 的解码问题

### 与AI协作经验

1. **提供完整日志**: 错误码比描述更有价值
2. **描述预期vs实际**: "应该走过去才弹" vs "一开始就弹"
3. **让AI先分析再改**: "先不要写代码，看看有什么问题"
4. **对比原项目**: AI读懂原项目后能给出更准确的方案
5. **用截图验证**: 让AI看到你看到的界面效果

---

## 待优化功能

- [ ] POI 类型图标显示
- [ ] 发现历史列表界面
- [ ] POI 详情页面（资源领取）
- [ ] 不同类型POI不同奖励
- [ ] POI 刷新机制（资源恢复）

---

## 参考文件

- `/Users/mikeliu/Desktop/tuzi-fuke/tuzi-fuke/POIManager.swift`
- `/Users/mikeliu/Desktop/tuzi-fuke/tuzi-fuke/SimpleMapView.swift`
- `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/ExplorationManager.swift`（原项目参考）
- `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/DiscoveryManager.swift`（原项目参考）
