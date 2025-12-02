# Day 8: 建筑系统开发提示词

**日期**: 2025年12月2日
**功能**: 建筑系统 - 模板定义、列表UI、放置、建造
**分支**: `feature/building-system`

---

## 开始前准备

### 1. 创建开发分支

```bash
cd /Users/mikeliu/Desktop/tuzi-fuke
git checkout -b feature/building-system
```

### 2. 确认当前项目状态

项目路径: `/Users/mikeliu/Desktop/tuzi-fuke`
源项目参考: `/Users/mikeliu/Desktop/tuzi-earthlord`

---

## AI 提示词（复制使用）

### 提示词 1: 项目分析和数据库建表

```
我正在开发一个 iOS 游戏的建筑系统。

项目路径: /Users/mikeliu/Desktop/tuzi-fuke
源项目参考: /Users/mikeliu/Desktop/tuzi-earthlord

请帮我完成以下任务：

1. 阅读源项目的建筑相关文件：
   - /Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/BuildingModels.swift
   - /Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/BuildingManager.swift

2. 在 Supabase 数据库中创建建筑系统所需的表：
   - building_templates（建筑模板表）
   - player_buildings（玩家建筑表）

   请参考源项目的数据模型设计表结构，并启用 RLS。

3. 列出需要创建的 Swift 文件清单。

当前项目已有的相关文件：
- tuzi-fuke/Building.swift（简化版，需要升级）
- tuzi-fuke/Territory.swift（领地系统，已完成）
```

---

### 提示词 2: 升级 Building 模型

```
继续建筑系统开发。

请帮我升级 /Users/mikeliu/Desktop/tuzi-fuke/tuzi-fuke/Building.swift：

1. 参考源项目 /Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/BuildingModels.swift

2. 需要包含以下模型：
   - BuildingTemplate（建筑模板，从数据库读取）
   - PlayerBuilding（玩家已建造的建筑）
   - BuildingCategory（建筑分类）
   - BuildingStatus（建筑状态）
   - BuildingConstructionRequest（建造请求）
   - BuildingConstructionResult（建造结果）

3. 确保 CodingKeys 与数据库字段名匹配（snake_case）

4. 保留现有的简化版 Building struct 以保持向后兼容
```

---

### 提示词 3: 创建 BuildingManager

```
继续建筑系统开发。

请帮我创建 /Users/mikeliu/Desktop/tuzi-fuke/tuzi-fuke/BuildingManager.swift：

1. 参考源项目 /Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/BuildingManager.swift

2. 需要实现的核心功能：
   - fetchBuildingTemplates() - 获取建筑模板列表
   - fetchPlayerBuildings(territoryId:) - 获取玩家在某领地的建筑
   - canBuild(template:territoryId:) - 检查是否可以建造
   - startConstruction(request:) - 开始建造
   - completeConstruction(buildingId:) - 完成建造

3. 使用 @MainActor 和 @Published 支持 SwiftUI

4. 使用项目现有的 SupabaseConfig.swift 中的 supabase 客户端

5. 简化版本：暂时不需要 Bundle 加载、Realtime 订阅等高级功能
```

---

### 提示词 4: 创建建筑列表 UI (L1)

```
继续建筑系统开发。

请帮我创建建筑列表界面 /Users/mikeliu/Desktop/tuzi-fuke/tuzi-fuke/BuildingListView.swift：

1. 参考源项目 /Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/BuildingBrowserView.swift

2. 界面需求：
   - 显示所有可建造的建筑模板
   - 按分类（survival/storage/production/energy/defense）分组显示
   - 每个建筑显示：图标、名称、描述、建造成本、建造时间
   - 点击建筑进入放置流程

3. 使用 SwiftUI，风格简洁

4. 需要传入 territoryId 参数（在哪个领地建造）
```

---

### 提示词 5: 创建建筑放置 UI (L2)

```
继续建筑系统开发。

请帮我创建建筑放置界面 /Users/mikeliu/Desktop/tuzi-fuke/tuzi-fuke/BuildingPlacementView.swift：

1. 参考源项目 /Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/BuildingPlacementView.swift

2. 界面需求：
   - 在地图上显示当前领地范围
   - 用户可以在领地内点击选择建造位置
   - 显示位置是否有效（不与其他建筑重叠）
   - 显示建造成本和确认按钮
   - 点击确认后调用 BuildingManager.startConstruction()

3. 位置验证：
   - 必须在领地范围内
   - 与其他建筑最小距离 20 米

4. 使用项目现有的 MapViewRepresentable 或 SimpleMapView
```

---

### 提示词 6: 领地建筑查询 (L4)

```
继续建筑系统开发。

请帮我创建领地建筑列表界面 /Users/mikeliu/Desktop/tuzi-fuke/tuzi-fuke/TerritoryBuildingsView.swift：

1. 界面需求：
   - 显示某个领地内所有已建造的建筑
   - 每个建筑显示：名称、等级、状态、建造进度（如果建造中）
   - 建造中的建筑显示倒计时
   - 点击建筑可查看详情

2. 从 BuildingManager.playerBuildings 获取数据

3. 支持下拉刷新
```

---

### 提示词 7: 地图显示建筑 (L4)

```
继续建筑系统开发。

请帮我修改 /Users/mikeliu/Desktop/tuzi-fuke/tuzi-fuke/SimpleMapView.swift：

1. 在地图上显示玩家的建筑物

2. 每个建筑显示为一个标注（Annotation）：
   - 使用建筑类型对应的 SF Symbol 图标
   - 显示建筑名称
   - 建造中的建筑使用不同颜色或样式

3. 点击建筑标注可弹出详情

4. 从 BuildingManager.playerBuildings 获取建筑数据
```

---

## 开发顺序建议

```
1. 数据库建表 (提示词 1)
      ↓
2. 升级 Building 模型 (提示词 2)
      ↓
3. 创建 BuildingManager (提示词 3)
      ↓
4. 建筑列表 UI (提示词 4)
      ↓
5. 建筑放置 UI (提示词 5)
      ↓
6. 领地建筑查询 (提示词 6)
      ↓
7. 地图显示建筑 (提示词 7)
      ↓
8. 测试 & 合并到 main
```

---

## 源项目关键文件参考

| 文件 | 路径 | 用途 |
|------|------|------|
| BuildingModels.swift | `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/BuildingModels.swift` | 数据模型定义 |
| BuildingManager.swift | `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/BuildingManager.swift` | 核心业务逻辑 |
| BuildingBrowserView.swift | `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/BuildingBrowserView.swift` | 建筑列表 UI |
| BuildingPlacementView.swift | `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/BuildingPlacementView.swift` | 放置 UI |
| BuildingDetailSheet.swift | `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/BuildingDetailSheet.swift` | 建筑详情 |
| TerritoryBuildingRow.swift | `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/TerritoryBuildingRow.swift` | 建筑行视图 |

---

## 数据库表结构参考

### building_templates 表

```sql
CREATE TABLE building_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id TEXT UNIQUE NOT NULL,      -- 如 "shelter_basic"
    name TEXT NOT NULL,
    tier INT DEFAULT 1,                     -- 1/2/3 级建筑
    category TEXT NOT NULL,                 -- survival/storage/production/energy/defense
    description TEXT,
    icon TEXT,                              -- SF Symbol 名称
    required_level INT DEFAULT 1,
    required_resources JSONB DEFAULT '{}',  -- {"wood": 10, "stone": 5}
    build_time_hours DOUBLE PRECISION DEFAULT 1.0,
    effects JSONB DEFAULT '{}',             -- {"storage_capacity": 50}
    max_per_territory INT DEFAULT 5,
    max_level INT DEFAULT 3,
    durability_max INT DEFAULT 100,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT now()
);
```

### player_buildings 表

```sql
CREATE TABLE player_buildings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) NOT NULL,
    territory_id UUID REFERENCES territories(id) NOT NULL,
    building_template_id UUID REFERENCES building_templates(id),
    building_name TEXT NOT NULL,
    building_template_key TEXT NOT NULL,   -- 如 "shelter_basic"
    location JSONB,                         -- {"type": "Point", "coordinates": [lng, lat]}
    status TEXT DEFAULT 'constructing',     -- constructing/active/damaged/inactive
    build_started_at TIMESTAMPTZ DEFAULT now(),
    build_completed_at TIMESTAMPTZ,
    build_time_hours DOUBLE PRECISION,
    level INT DEFAULT 1,
    durability INT DEFAULT 100,
    durability_max INT DEFAULT 100,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- RLS 策略
ALTER TABLE player_buildings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "用户可以查看所有建筑" ON player_buildings
    FOR SELECT USING (true);

CREATE POLICY "用户只能操作自己的建筑" ON player_buildings
    FOR ALL USING (auth.uid() = user_id);
```

---

## 完成后检查清单

- [ ] 数据库表创建成功
- [ ] Building.swift 模型升级完成
- [ ] BuildingManager.swift 创建完成
- [ ] 建筑列表 UI 可以显示模板
- [ ] 建筑放置 UI 可以选择位置
- [ ] 建造功能正常工作
- [ ] 领地建筑列表可以查看
- [ ] 地图上可以显示建筑
- [ ] 代码已提交到 feature/building-system 分支
- [ ] 合并到 main 分支

---

## 常见问题

### Q: 建筑模板列表为空？
A: 检查 building_templates 表是否有数据，需要先插入一些测试模板。

### Q: 建造失败提示资源不足？
A: 当前简化版可能没有对接资源系统，可以先注释掉资源检查。

### Q: 地图上看不到建筑？
A: 检查 player_buildings 表中的 location 字段是否有值。

---

## 相关文档

- 圈地功能教程: `jiaoxue/DAY4_CLAIMING_COLLISION_TUTORIAL.md`
- POI 发现教程: `jiaoxue/DAY7_POI_DISCOVERY_TUTORIAL.md`
- 开发进度: `guihua/development_progress.md`
