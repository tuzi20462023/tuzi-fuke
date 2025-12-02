# Day 7 POI 探索发现系统教程 - MapKit 搜索与100米触发

**目标**: 实现 POI 探索发现功能，玩家走到真实商户附近时触发发现奖励
**时间**: 4-5小时
**开发模式**: AI辅助开发 - 通过AI提示词生成代码
**结果**: 玩家走到药店、超市等真实地点100米内时弹出发现提示

---

## 🤖 AI开发特点

本教程采用AI辅助开发模式：

- ✅ **提示词驱动**: 每个任务都提供完整的AI提示词
- ✅ **问题排查模板**: 遇到问题时如何向AI描述
- ✅ **原项目参考**: 让AI对比原项目实现优化代码
- ✅ **截图验证**: 用截图确认功能效果

---

## 🎯 学习目标

完成本教程后，你将掌握：

- [ ] MapKit 本地搜索 API 使用
- [ ] POI 数据库表设计（候选表+正式表+发现表）
- [ ] 坐标系转换（WGS-84 ↔ GCJ-02）
- [ ] 100米范围触发机制
- [ ] 防止重复弹窗的触发记录系统
- [ ] Swift 6 并发与 Supabase 集成

---

## 📋 前置准备

### 已完成的功能

- [x] Day 1-4 基础框架（地图、圈地、碰撞检测）
- [x] Supabase 认证和数据库
- [x] LocationManager 位置追踪
- [x] CoordinateConverter 坐标转换工具

### 本日新增功能

- [ ] MapKit POI 搜索
- [ ] POI 候选提交到数据库
- [ ] POI 发现触发机制
- [ ] 发现弹窗界面

---

## 🚀 任务1: 创建数据库表 (20分钟)

### 目标

创建 POI 候选表、正式 POI 表、用户发现记录表。

### 🤖 AI提示词 (Supabase SQL Editor)

```sql
-- ========================================
-- POI 探索发现系统数据库表
-- ========================================

-- 1. POI候选表（MapKit搜索结果暂存）
CREATE TABLE IF NOT EXISTS mapkit_poi_candidates (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    poi_type TEXT NOT NULL,
    address TEXT,
    phone TEXT,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    grid_key TEXT UNIQUE,
    mapkit_id TEXT,
    submitted_by UUID REFERENCES auth.users(id),
    processed BOOLEAN DEFAULT FALSE,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. 正式POI表（用于发现系统）
CREATE TABLE IF NOT EXISTS pois (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('hospital', 'supermarket', 'factory', 'restaurant', 'gas_station', 'school', 'park', 'other')),
    description TEXT,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    total_items INT DEFAULT 100,
    remaining_items INT DEFAULT 100,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. 用户发现记录表
CREATE TABLE IF NOT EXISTS user_poi_discoveries (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id TEXT NOT NULL,
    poi_id TEXT NOT NULL,
    poi_name TEXT,
    poi_type TEXT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    discovered_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, poi_id)
);

-- 4. 启用 RLS
ALTER TABLE mapkit_poi_candidates ENABLE ROW LEVEL SECURITY;
ALTER TABLE pois ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_poi_discoveries ENABLE ROW LEVEL SECURITY;

-- 5. RLS 策略
-- 候选表：认证用户可读写
CREATE POLICY "Authenticated can manage candidates" ON mapkit_poi_candidates
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- POI表：所有人可读
CREATE POLICY "Anyone can read pois" ON pois
    FOR SELECT USING (true);

-- 发现记录：用户只能管理自己的
CREATE POLICY "Users can manage own discoveries" ON user_poi_discoveries
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 6. 创建索引
CREATE INDEX IF NOT EXISTS idx_poi_candidates_location ON mapkit_poi_candidates(latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_poi_candidates_type ON mapkit_poi_candidates(poi_type);
CREATE INDEX IF NOT EXISTS idx_pois_location ON pois(latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_pois_type ON pois(type);
CREATE INDEX IF NOT EXISTS idx_discoveries_user ON user_poi_discoveries(user_id);
```

### ✅ 验证

在 Supabase Dashboard → Table Editor 确认三张表已创建。

---

## 🚀 任务2: 创建 POI 数据模型 (15分钟)

### 目标

创建 POI.swift 数据模型。

### 🤖 AI提示词

```
请帮我创建 POI.swift 文件，包含以下模型：

1. POIType 枚举：
   - hospital, supermarket, pharmacy, convenience_store, restaurant, gas_station, school, park, other
   - 每个类型有 displayName 计算属性（中文名称）
   - 每个类型有 icon 计算属性（SF Symbol 名称）

2. POI 结构体：
   - id: UUID
   - name: String
   - type: POIType
   - description: String?
   - latitude: Double
   - longitude: Double
   - isActive: Bool
   - totalItems: Int
   - remainingItems: Int

   计算属性：
   - coordinate: CLLocationCoordinate2D
   - hasLoot: Bool (remainingItems > 0)

3. POICandidate 结构体（用于MapKit搜索结果）：
   - id: UUID
   - name: String
   - poiType: String
   - address: String?
   - latitude: Double
   - longitude: Double
   - gridKey: String

所有模型实现 Codable, Identifiable, Sendable 协议。
使用 CodingKeys 映射 snake_case 字段名。

参考项目中 Territory.swift 的代码风格。
```

---

## 🚀 任务3: 创建 POIManager (60分钟)

### 目标

创建 POI 管理器处理搜索、缓存、发现逻辑。

### 🤖 AI提示词

```
请帮我创建 POIManager.swift，要求：

1. 使用 @MainActor + ObservableObject
2. 配置常量：
   - discoveryRange: 100米（发现范围）
   - cacheRadius: 1000米（缓存范围）
   - checkDistance: 30米（移动多少米后重新检查）
   - resetDistance: 200米（离开多远后重置触发状态）

3. Published 属性：
   - cachedPOIs: [POI] - 缓存的附近POI
   - discoveredPOIIds: Set<UUID> - 数据库中已发现的POI ID
   - lastDiscoveredPOI: POI? - 最近发现的POI（用于弹窗）
   - showDiscoveryAlert: Bool - 是否显示发现弹窗
   - isLoading: Bool

4. 私有属性：
   - triggeredPOIIds: Set<UUID> - 本次会话已触发弹窗的POI（防止重复）
   - lastCheckLocation: CLLocation? - 上次检查位置
   - lastCacheUpdateLocation: CLLocation? - 上次缓存更新位置

5. 公开方法：
   - onLocationReady(location: CLLocation, userId: UUID) async
     首次定位成功时调用，搜索MapKit并提交候选
   - searchNearbyPOIs(location: CLLocation) async
     更新POI缓存
   - checkNearbyPOIs(location: CLLocation, userId: UUID) async -> POI?
     检查是否有新的POI可发现（100米内）
   - resetForNewExploration()
     开始新探索时重置（但不清空triggeredPOIIds！）

6. 关键逻辑：
   a) MapKit搜索：
      - 搜索医院、药店、超市、便利店
      - 使用 MKLocalSearch
      - 搜索半径1000米
      - 提交结果到 mapkit_poi_candidates 表

   b) 触发机制（参考原项目 ExplorationManager）：
      - 100米内触发发现
      - 触发后记录到 triggeredPOIIds
      - 离开200米后从 triggeredPOIIds 移除（允许再次触发）
      - 发现后记录到数据库 user_poi_discoveries

   c) 防止首次弹窗：
      - onLocationReady 结束时调用 markNearbyPOIsAsTriggered
      - 把已在100米范围内的POI预先标记为已触发

7. 使用 REST API 调用 Supabase（避免 Swift 6 并发问题）

参考项目中 TerritoryManager.swift 和 ChatManager.swift 的代码风格。
```

### ⚠️ 关键代码段

**防止首次弹窗的预标记逻辑**:

```swift
/// 预先标记当前已在发现范围内的 POI
private func markNearbyPOIsAsTriggered(location: CLLocation) {
    let gcjCoord = CoordinateConverter.wgs84ToGcj02(location.coordinate)
    let currentLocation = CLLocation(latitude: gcjCoord.latitude, longitude: gcjCoord.longitude)

    for poi in cachedPOIs {
        if discoveredPOIIds.contains(poi.id) { continue }

        let poiLocation = CLLocation(latitude: poi.latitude, longitude: poi.longitude)
        let distance = currentLocation.distance(from: poiLocation)

        // 如果 POI 已经在发现范围内（100米），预先标记
        if distance <= discoveryRange {
            triggeredPOIIds.insert(poi.id)
        }
    }
}
```

**200米重置逻辑**:

```swift
/// 清理远离的已触发 POI（超过 200 米后允许再次触发）
private func cleanupDistantTriggeredPOIs(currentLocation: CLLocation) {
    var toRemove: Set<UUID> = []

    for poiId in triggeredPOIIds {
        guard let poi = cachedPOIs.first(where: { $0.id == poiId }) else {
            toRemove.insert(poiId)
            continue
        }

        let poiLocation = CLLocation(latitude: poi.latitude, longitude: poi.longitude)
        let distance = currentLocation.distance(from: poiLocation)

        if distance > resetDistance {  // 200米
            toRemove.insert(poiId)
        }
    }

    triggeredPOIIds.subtract(toRemove)
}
```

---

## 🚀 任务4: 候选数据迁移到正式POI表 (15分钟)

### 目标

将 mapkit_poi_candidates 的数据迁移到 pois 表。

### ⚠️ 类型映射问题

MapKit 返回的类型（如 `pharmacy`）可能不在 pois 表的约束中，需要映射：

```sql
-- 查看候选表有哪些类型
SELECT DISTINCT poi_type, COUNT(*) FROM mapkit_poi_candidates GROUP BY poi_type;

-- 迁移数据（带类型映射）
INSERT INTO pois (name, type, description, latitude, longitude, is_active, total_items, remaining_items)
SELECT
    name,
    CASE poi_type
        WHEN 'pharmacy' THEN 'hospital'
        WHEN 'convenience_store' THEN 'supermarket'
        WHEN 'drugstore' THEN 'hospital'
        ELSE poi_type
    END as type,
    address as description,
    latitude,
    longitude,
    TRUE as is_active,
    100 as total_items,
    100 as remaining_items
FROM mapkit_poi_candidates
WHERE NOT processed
ON CONFLICT DO NOTHING;

-- 标记为已处理
UPDATE mapkit_poi_candidates SET processed = TRUE WHERE NOT processed;
```

---

## 🚀 任务5: 集成到 SimpleMapView (30分钟)

### 目标

在地图界面中添加 POI 发现功能。

### 🤖 AI提示词

```
请修改 SimpleMapView.swift，添加 POI 发现功能：

1. 添加 @StateObject poiManager = POIManager()

2. 在 onAppear 或首次定位成功时：
   - 调用 poiManager.onLocationReady(location:userId:)

3. 在开始探索时：
   - 调用 poiManager.resetForNewExploration()
   - 启动 POI 检查定时器（每2秒）

4. POI检查定时器：
   - 每2秒调用 poiManager.checkNearbyPOIs(location:userId:)
   - 如果返回了 POI，弹窗已通过 poiManager.showDiscoveryAlert 自动触发

5. 添加发现弹窗：
   .alert("发现POI!", isPresented: $poiManager.showDiscoveryAlert) {
       Button("太棒了!", role: .cancel) {
           poiManager.clearDiscoveryAlert()
       }
   } message: {
       if let poi = poiManager.lastDiscoveredPOI {
           Text("🎉 你发现了【\(poi.name)】\n类型: \(poi.type.displayName)\n可获得资源: \(poi.remainingItems)个")
       }
   }

6. 停止探索时：
   - 停止 POI 检查定时器

参考现有的碰撞检测定时器实现。
```

---

## 🚀 任务6: 测试POI发现 (30分钟)

### 测试步骤

1. **启动应用**
   
   - 授权位置权限
   - 等待首次定位成功
   - 查看日志确认 POI 搜索完成

2. **检查数据库**
   
   ```sql
   -- 查看候选数量
   SELECT COUNT(*) FROM mapkit_poi_candidates;
   
   -- 查看正式POI数量
   SELECT COUNT(*) FROM pois WHERE is_active = TRUE;
   ```

3. **开始探索**
   
   - 点击开始探索
   - 走向附近的药店/超市
   - 进入100米范围时应弹出发现提示

4. **验证防重复机制**
   
   - 停止探索
   - 再次开始探索
   - 同一个POI不应立即弹出（因为还在100米内）
   - 离开200米后再回来，应该能再次触发

### 🤖 排查问题的AI提示词

**如果没有搜索到POI**:

```
帮我查一下：
1. mapkit_poi_candidates 表有数据吗？
2. 控制台有没有 "MapKit搜索" 相关的日志？
3. 位置权限是否正确授权？
```

**如果弹窗不出现**:

```
POI发现弹窗不出现，这是日志：
[粘贴控制台日志]

帮我检查：
1. pois 表有没有数据？
2. 距离计算是否正确（坐标系转换）？
3. triggeredPOIIds 是否把所有POI都标记了？
```

**如果每次开始探索都弹窗**:

```
每次开始探索都立即弹出附近POI，而不是走过去才弹。

预期行为：只有我走入100米范围时才弹窗
实际行为：一开始探索就弹出所有100米内的POI

请检查 triggeredPOIIds 的逻辑是否正确。
```

---

## 🚨 常见问题汇总

### Q1: POI候选提交失败

**错误信息**: `unexpectedDatabaseError("No data in response")`

**原因**: Supabase SDK 使用 `returning: .minimal` 时解码空响应失败

**解决**:

```swift
// 错误方式
try await supabase.database
    .from("table")
    .insert(data)
    .returning(.minimal)
    .execute()

// 正确方式
try await supabase.database
    .from("table")
    .insert([data])  // 数组形式
    .select()        // 返回数据
    .execute()
```

### Q2: pharmacy 类型插入失败

**错误信息**: `violates check constraint "pois_type_check"`

**原因**: pois 表有类型约束，不包含 pharmacy

**解决**: 迁移时映射类型

```sql
CASE poi_type
    WHEN 'pharmacy' THEN 'hospital'
    WHEN 'convenience_store' THEN 'supermarket'
    ELSE poi_type
END
```

### Q3: 距离计算不准确

**原因**: 坐标系不一致（GPS用WGS-84，地图用GCJ-02）

**解决**: 统一转换到 GCJ-02

```swift
let gcjCoord = CoordinateConverter.wgs84ToGcj02(location.coordinate)
let currentLocation = CLLocation(latitude: gcjCoord.latitude, longitude: gcjCoord.longitude)
```

### Q4: 每次开始探索都弹窗

**原因**: 没有预标记已在范围内的POI

**解决**: 在 `onLocationReady` 结束时调用 `markNearbyPOIsAsTriggered`

### Q5: POI永远不再触发

**原因**: 没有实现200米重置机制

**解决**: 在 `checkNearbyPOIs` 中先调用 `cleanupDistantTriggeredPOIs`

---

## 📊 本日学习总结

### 技术栈

| 技术                   | 用途              |
| -------------------- | --------------- |
| MapKit MKLocalSearch | 搜索附近真实商户        |
| Supabase Database    | POI数据存储         |
| CoreLocation         | 位置追踪和距离计算       |
| CoordinateConverter  | WGS-84/GCJ-02转换 |
| SwiftUI Alert        | 发现弹窗            |

### AI协作要点

1. **提供完整日志**: 错误码比描述更有价值
2. **描述预期vs实际**: "走过去才弹" vs "一开始就弹"
3. **让AI先分析再改**: "先不要写代码，看看有什么问题"
4. **对比原项目**: 让AI读原项目代码找到正确实现

### 核心经验

1. **双重检查机制**: `discoveredPOIIds`(数据库) + `triggeredPOIIds`(本地)
2. **200米重置**: 用户离开后才允许再次触发
3. **预标记机制**: 启动时标记已在范围内的POI
4. **坐标系统一**: 全部使用 GCJ-02 计算距离
5. **类型映射**: MapKit类型 → 数据库约束类型

---

## 🎯 扩展任务（可选）

完成基础功能后，可以继续实现：

### POI详情页

- 显示POI完整信息
- 可领取的资源列表
- 领取按钮

### 发现历史

- 用户发现过的POI列表
- 按时间/类型排序
- 可以导航到POI位置

### POI刷新机制

- 资源定时恢复
- 不同类型POI恢复速度不同

### 稀有POI

- 随机生成稀有POI
- 更高的资源奖励

---

**恭喜完成 Day 7！** 🎉

你已经掌握了 POI 探索发现系统的开发，包括：

- MapKit 本地搜索
- 100米触发机制
- 防重复弹窗的触发记录
- 坐标系转换
