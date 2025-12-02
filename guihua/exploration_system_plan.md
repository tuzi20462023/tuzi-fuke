# 探索系统开发规划

**最后更新**: 2025年12月2日
**开发目录**: `/Users/mikeliu/Desktop/tuzi-fuke-explore`
**源代码参考**: `/Users/mikeliu/Desktop/tuzi-earthlord`
**当前状态**: 🚧 开发中（L1 部分完成）

---

## 一、当前进展

### 已完成功能

| 功能 | 文件 | 状态 | 说明 |
|------|------|------|------|
| MapKit搜索附近POI | `POIManager.swift` | ✅ | 搜索医院、药店、超市等 |
| POI候选提交到数据库 | `POIManager.swift` | ✅ | 存入 `mapkit_poi_candidates` 表 |
| POI类型定义(11类) | `POI.swift` | ✅ | 超过需求的8类 |
| 100米发现触发 | `POIManager.swift` | ✅ | 走入范围时弹窗 |
| 防重复弹窗机制 | `POIManager.swift` | ✅ | `triggeredPOIIds` + 200米重置 |
| 发现记录保存 | `POIManager.swift` | ✅ | 存入 `user_poi_discoveries` 表 |
| 坐标系转换 | `CoordinateConverter.swift` | ✅ | WGS-84 ↔ GCJ-02 |

### 相关文档

- **经验文档**: `jingyan/20251202_poi_discovery_experience.md`
- **教学文档**: `jiaoxue/DAY7_POI_DISCOVERY_TUTORIAL.md`

---

## 二、待开发功能清单

根据功能表整理，按优先级排序：

### 高优先级（基础线）

| 序号 | 层级 | 功能 | 原项目参考文件 | 预计工时 |
|------|------|------|---------------|---------|
| 1 | L1 | POI显示在地图上 | `MapViewRepresentable.swift` | 2小时 |
| 2 | L2 | 开始/结束探索 | `ExplorationManager.swift` | 2小时 |
| 3 | L2 | 探索距离统计 | `ExplorationManager.swift` | 1小时 |
| 4 | L3 | 系统随机生成物品 | `LocalExplorationRewardCalculator.swift` | 2小时 |
| 5 | L3 | 掉落结果展示UI | `ExplorationResultView.swift` | 2小时 |

### 中优先级（进阶线）

| 序号 | 层级 | 功能 | 原项目参考文件 | 预计工时 |
|------|------|------|---------------|---------|
| 6 | L5 | POI搜刮功能 | `POIDetailView.swift` | 3小时 |
| 7 | L5 | 搜刮冷却时间 | `POIManager.swift` | 1小时 |
| 8 | L4 | AI根据POI类型生成物品 | `POIManager.swift` (Edge Function) | 3小时 |
| 9 | L4 | Edge Function调用千问 | Supabase Edge Functions | 2小时 |

### 低优先级（高级线）

| 序号 | 层级 | 功能 | 原项目参考文件 | 预计工时 |
|------|------|------|---------------|---------|
| 10 | L6 | 网格探索统计 | `ExplorationManager.swift` | 2小时 |
| 11 | L6 | 热量计算 | `ExplorationManager.swift` | 1小时 |
| 12 | L6 | 探索排行榜 | `LeaderboardManager.swift` | 3小时 |

---

## 三、详细实现方案

### 1. POI显示在地图上 (L1)

**目标**: 在地图上用图标标注附近的POI位置

**参考文件**:
- `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/MapViewRepresentable.swift`

**实现步骤**:

1. 创建 `POIAnnotation` 类继承 `MKPointAnnotation`
   ```swift
   class POIAnnotation: MKPointAnnotation {
       let poi: POI
       init(poi: POI) {
           self.poi = poi
           super.init()
           self.coordinate = poi.coordinate
           self.title = poi.name
       }
   }
   ```

2. 修改 `MapViewRepresentable.swift`，添加 POI 标注逻辑
   - 监听 `poiManager.cachedPOIs` 变化
   - 添加/移除标注点
   - 自定义标注视图（不同类型不同图标）

3. 实现 `MKMapViewDelegate.viewFor(annotation:)` 方法
   - 根据 POI 类型返回不同颜色/图标的标注

**AI提示词**:
```
请修改 MapViewRepresentable.swift，在地图上显示 POI 标注：

1. 创建 POIAnnotation 类，包含 poi: POI 属性
2. 在 updateUIView 中根据 poiManager.cachedPOIs 添加标注
3. 实现 mapView(_:viewFor:) 返回自定义标注视图
4. 不同 POI 类型用不同颜色（医院红色、超市蓝色等）
5. 点击标注显示 POI 名称

参考原项目 MapViewRepresentable.swift 的实现。
```

---

### 2. 开始/结束探索 (L2)

**目标**: 独立的探索模式（与圈地模式分开）

**参考文件**:
- `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/ExplorationManager.swift`

**数据库表** (已存在或需创建):
```sql
-- 探索会话表
CREATE TABLE IF NOT EXISTS exploration_sessions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id),
    started_at TIMESTAMPTZ DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    start_location JSONB,
    end_location JSONB,
    route_points JSONB DEFAULT '[]',
    total_distance DOUBLE PRECISION DEFAULT 0,
    total_area DOUBLE PRECISION DEFAULT 0,
    duration_seconds INT DEFAULT 0,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'completed', 'cancelled'))
);
```

**实现步骤**:

1. 创建 `ExplorationManager.swift`
   ```swift
   @MainActor
   class ExplorationManager: ObservableObject {
       @Published var isExploring = false
       @Published var currentSession: ExplorationSession?
       @Published var routePoints: [CLLocationCoordinate2D] = []
       @Published var totalDistance: Double = 0
       @Published var totalArea: Double = 0
       @Published var explorationResult: ExplorationResult?

       func startExploration(userId: UUID) async
       func endExploration(userId: UUID) async -> ExplorationResult?
       func trackLocation(_ location: CLLocation) async
   }
   ```

2. 修改 `SimpleMapView.swift`
   - 添加"开始探索"/"结束探索"按钮
   - 探索中显示统计信息（距离、时长）
   - 结束时显示 `ExplorationResultView`

**AI提示词**:
```
请创建 ExplorationManager.swift，实现探索会话管理：

1. 使用 @MainActor + ObservableObject
2. Published 属性：isExploring, currentSession, routePoints, totalDistance, totalArea
3. 方法：
   - startExploration(userId:) - 开始探索，记录起点
   - endExploration(userId:) - 结束探索，计算奖励
   - trackLocation(_:) - 追踪位置，累计距离
4. 距离计算：累加相邻点距离
5. 使用 REST API 与 Supabase 交互

参考原项目 ExplorationManager.swift 第 83-154 行。
```

---

### 3. 探索距离统计 (L2)

**目标**: 实时显示探索距离、时长、热量

**参考文件**:
- `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/ExplorationManager.swift` 第 428-480 行

**实现步骤**:

1. 在 `ExplorationManager` 中添加统计逻辑
   ```swift
   func trackLocation(_ location: CLLocation, userId: UUID) async -> Bool {
       // 速度检测（防作弊）
       if let lastLoc = lastLocation {
           let speed = distance / timeInterval * 3.6  // km/h
           if speed > 15 { return false }  // 超速
       }

       // 累计距离
       if let lastLoc = lastLocation {
           let distance = location.distance(from: lastLoc)
           if distance > 0 && distance < 100 {
               totalDistance += distance
           }
       }

       lastLocation = location
       return true
   }
   ```

2. 在 UI 中显示统计
   - 距离：米/公里
   - 时长：分:秒
   - 热量：卡路里（可选）

---

### 4. 系统随机生成物品 (L3)

**目标**: 探索结束时根据距离/面积生成掉落物品

**参考文件**:
- `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/LocalInventory/LocalExplorationRewardCalculator.swift`

**实现步骤**:

1. 创建 `LocalExplorationRewardCalculator.swift`
   ```swift
   @MainActor
   final class LocalExplorationRewardCalculator {
       static let shared = LocalExplorationRewardCalculator()

       /// 每500米一次掉落机会
       private let metersPerDropOpportunity: Double = 500

       /// 基础掉落概率
       private let baseDropChance: Double = 0.6

       /// 通用掉落池
       private let commonDrops: [(itemId: String, weight: Double)] = [
           ("wood", 1.5),
           ("stone", 1.2),
           ("scrap", 1.0),
           ("cloth", 0.8),
           ("rope", 0.6)
       ]

       func calculateRewards(
           distanceWalked: Double,
           areaExplored: Double,
           durationSeconds: Int,
           regionType: String
       ) -> [RewardItem]
   }
   ```

2. 定义物品模型
   ```swift
   struct RewardItem: Codable, Identifiable {
       let itemId: String
       let quantity: Int
       var id: String { itemId }
   }
   ```

---

### 5. 掉落结果展示UI (L3)

**目标**: 探索结束时显示获得的物品

**参考文件**:
- `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/ExplorationResultView.swift`

**实现步骤**:

1. 创建 `ExplorationResultView.swift`
   ```swift
   struct ExplorationResultView: View {
       let result: ExplorationResult

       var body: some View {
           VStack {
               // 探索统计
               StatisticsSection(result: result)

               // 奖励物品列表
               RewardItemsSection(items: result.rewardItems)

               // 领取按钮
               ClaimButton(...)
           }
       }
   }
   ```

2. 统计展示
   - 行走距离（本次/累计）
   - 探索面积（本次/累计）
   - 探索时长

3. 物品展示
   - 物品图标
   - 物品名称
   - 数量

---

### 6. POI搜刮功能 (L5)

**目标**: 进入POI范围后可以搜刮获取资源

**参考文件**:
- `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/POIDetailView.swift`
- `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/POIManager.swift`

**数据库表**:
```sql
-- POI 物品清单表
CREATE TABLE IF NOT EXISTS poi_loot_tables (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    poi_id UUID NOT NULL REFERENCES pois(id),
    loot_data JSONB NOT NULL,  -- [{item_id, quantity, quality}]
    total_items INT DEFAULT 0,
    generated_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ
);

-- 用户搜刮记录
CREATE TABLE IF NOT EXISTS user_poi_scavenges (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL,
    poi_id UUID NOT NULL,
    items_collected JSONB,
    scavenged_at TIMESTAMPTZ DEFAULT NOW()
);
```

**实现步骤**:

1. 创建 `POIDetailView.swift`
   - 显示 POI 信息（名称、类型、图标）
   - 显示可搜刮物品列表
   - 选择要领取的物品
   - 搜刮按钮

2. 在 `POIManager` 中添加搜刮逻辑
   ```swift
   func scavengePOI(poi: POI, selectedItems: [String: Int], userId: UUID) async -> Bool
   func loadPOILootTable(poi: POI) async
   ```

3. 物品生成逻辑
   - 根据 POI 类型生成不同物品
   - 药店 → 药品、绷带
   - 超市 → 食物、水
   - 工厂 → 金属、零件

---

### 7. 搜刮冷却时间 (L5)

**目标**: 搜刮后需要等待一段时间才能再次搜刮

**实现步骤**:

1. 在 `user_poi_scavenges` 表中记录搜刮时间
2. 查询时检查冷却
   ```swift
   func canScavengePOI(poi: POI, userId: UUID) async -> (canScavenge: Bool, cooldownRemaining: Int?)
   ```
3. 冷却时间配置
   - 默认冷却：4小时
   - 不同 POI 类型可以有不同冷却时间

---

## 四、数据库完整设计

### 需要创建的表

```sql
-- 1. 探索会话表
CREATE TABLE IF NOT EXISTS exploration_sessions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id),
    started_at TIMESTAMPTZ DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    start_location JSONB,
    end_location JSONB,
    route_points JSONB DEFAULT '[]',
    total_distance DOUBLE PRECISION DEFAULT 0,
    total_area DOUBLE PRECISION DEFAULT 0,
    duration_seconds INT DEFAULT 0,
    status TEXT DEFAULT 'active'
);

-- 2. 用户探索统计表
CREATE TABLE IF NOT EXISTS user_exploration_stats (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) UNIQUE,
    total_explored_area DOUBLE PRECISION DEFAULT 0,
    total_distance DOUBLE PRECISION DEFAULT 0,
    total_sessions INT DEFAULT 0,
    explored_cells JSONB DEFAULT '[]',
    last_updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. POI 物品清单表
CREATE TABLE IF NOT EXISTS poi_loot_tables (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    poi_id UUID NOT NULL REFERENCES pois(id),
    loot_data JSONB NOT NULL,
    total_items INT DEFAULT 0,
    generated_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ
);

-- 4. 用户搜刮记录
CREATE TABLE IF NOT EXISTS user_poi_scavenges (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL,
    poi_id UUID NOT NULL,
    items_collected JSONB,
    scavenged_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. 物品定义表（如果没有）
CREATE TABLE IF NOT EXISTS item_definitions (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    category TEXT,
    icon TEXT,
    rarity TEXT DEFAULT 'common',
    max_stack INT DEFAULT 99
);

-- 6. 用户背包表（如果没有）
CREATE TABLE IF NOT EXISTS player_inventory (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id),
    item_id TEXT NOT NULL,
    quantity INT DEFAULT 1,
    quality DOUBLE PRECISION DEFAULT 1.0,
    location TEXT DEFAULT 'backpack',
    acquired_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, item_id, location)
);
```

---

## 五、开发顺序建议

### 第一阶段：基础功能 (Day 8)

1. **POI显示在地图上** - 2小时
2. **开始/结束探索** - 2小时
3. **探索距离统计** - 1小时

### 第二阶段：掉落系统 (Day 9)

4. **系统随机生成物品** - 2小时
5. **掉落结果展示UI** - 2小时
6. **物品定义数据** - 1小时

### 第三阶段：搜刮系统 (Day 10)

7. **POI搜刮功能** - 3小时
8. **搜刮冷却时间** - 1小时

### 第四阶段：高级功能 (可选)

9. AI物品生成
10. 网格探索统计
11. 探索排行榜

---

## 六、测试要点

### L1-L2 测试

- [ ] 地图上能看到 POI 图标
- [ ] 点击图标显示 POI 名称
- [ ] 开始探索按钮正常工作
- [ ] 结束探索显示统计

### L3 测试

- [ ] 探索结束有物品掉落
- [ ] 掉落数量与距离相关
- [ ] 物品能正确添加到背包

### L5 测试

- [ ] POI详情页正常显示
- [ ] 可以选择搜刮物品
- [ ] 搜刮后冷却时间生效
- [ ] 冷却结束后可再次搜刮

---

## 七、相关文件清单

### 需要创建的文件

| 文件 | 用途 |
|------|------|
| `ExplorationManager.swift` | 探索会话管理 |
| `ExplorationResultView.swift` | 探索结果展示 |
| `LocalExplorationRewardCalculator.swift` | 本地奖励计算 |
| `POIDetailView.swift` | POI详情和搜刮 |
| `POIAnnotation.swift` | 地图POI标注 |
| `ItemDefinition.swift` | 物品定义模型 |
| `PlayerInventory.swift` | 玩家背包模型 |

### 需要修改的文件

| 文件 | 修改内容 |
|------|---------|
| `MapViewRepresentable.swift` | 添加POI标注显示 |
| `SimpleMapView.swift` | 添加探索按钮和UI |
| `POIManager.swift` | 添加搜刮逻辑 |

---

## 八、参考资料

### 原项目关键文件

| 功能 | 文件路径 |
|------|---------|
| 探索管理 | `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/ExplorationManager.swift` |
| 探索结果UI | `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/ExplorationResultView.swift` |
| POI管理 | `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/POIManager.swift` |
| POI详情 | `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/POIDetailView.swift` |
| 发现管理 | `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/DiscoveryManager.swift` |
| 本地奖励计算 | `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/LocalInventory/LocalExplorationRewardCalculator.swift` |
| 本地背包 | `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/LocalInventory/LocalInventoryManager.swift` |
| 地图标注 | `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/MapViewRepresentable.swift` |

### 已完成的文档

- `jingyan/20251202_poi_discovery_experience.md` - POI发现开发经验
- `jiaoxue/DAY7_POI_DISCOVERY_TUTORIAL.md` - POI发现教学文档
