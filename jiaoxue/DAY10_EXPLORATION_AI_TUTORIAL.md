# Day 10: 探索系统与AI集成教学指南

**日期**: 2025年12月6日
**功能**: POI探索系统、Edge Function处理、AI叙事生成
**难度**: 中等（涉及后端Edge Function和PostGIS）

---

## 学习目标

完成本教程后，学员将掌握：

1. MapKit POI搜索与候选提交
2. Supabase Edge Function处理候选数据
3. PostGIS空间查询（距离排序）
4. 通义千问AI叙事生成
5. 探索历史记录展示

---

## 教学重点与常见坑点

### 坑点 1: PostGIS location字段为NULL

**现象**: RPC查询返回0个POI，但数据库有记录

**原因**: 只写入了latitude/longitude，没写入PostGIS的geography字段

**正确做法**:

```typescript
// Edge Function插入时同时写入location
const { error } = await supabase.from("pois").insert({
  latitude: candidate.latitude,
  longitude: candidate.longitude,
  // ★ 必须写入这个字段！
  location: `SRID=4326;POINT(${candidate.longitude} ${candidate.latitude})`,
});
```

**教学提示**: 强调PostGIS需要专门的geography类型字段，普通的latitude/longitude不能用于空间查询。

### 坑点 2: Edge Function只处理部分候选

**现象**: 候选表有500条，只生成了100个POI

**原因**: Edge Function默认limit(100)，且没有按距离排序

**正确做法**:

```typescript
// 使用RPC函数按距离查询
const { data } = await supabase.rpc("get_nearby_poi_candidates", {
  p_lat: userLat,
  p_lon: userLon,
  p_radius_meters: 5000,
  p_limit: 200  // 增加处理数量
});
```

### 坑点 3: 功能重复

**现象**: 主地图和探索Tab都显示"附近POI"

**原因**: 没理清原项目架构

**正确做法**:

| 位置 | 功能 | 数据来源 |
|------|------|----------|
| 主地图 | 附近待发现POI | pois表 + PostGIS |
| 探索Tab | 已发现历史 | user_poi_discoveries表 |

---

## AI 提示词模板

### 提示词 1: 分析原项目架构

在开始开发前，让AI先分析原项目：

```
请分析原项目 /Users/mikeliu/Desktop/tuzi-earthlord 的POI系统：

1. MapKit搜索是在哪里触发的？
2. 候选表是怎么填充的？
3. Edge Function什么时候调用？
4. POI是怎么出现在地图上的？

先分析不要写代码。
```

---

### 提示词 2: POI查询返回空

当PostGIS查询返回0个结果时使用：

```
POI查询有问题：

控制台日志：
✅ [POI] PostGIS 查询完成，共 0 个 POI

但数据库里明明有100条POI记录。

请检查：
1. pois表的location字段是否有值
2. RPC函数 get_pois_within_radius 的逻辑

先查数据库看看location字段。
```

---

### 提示词 3: Edge Function处理不完全

当只有部分POI类型出现时使用：

```
POI列表只有咖啡和书店，没有餐厅：

候选表有485条记录（包含餐厅）
Edge Function日志显示只处理了100条

请检查：
1. Edge Function的处理数量限制
2. 是否按距离排序
3. 餐厅候选是不是还没被处理

先分析问题再给方案。
```

---

### 提示词 4: 理清功能架构

当不确定功能边界时使用：

```
我现在有两个地方显示POI：
- 主地图里的POI列表
- 探索Tab里的"附近地点"

这两个是不是重复了？
原项目的资源Tab里的"POI探索"显示的是什么？

帮我理清架构，先不要代码。
```

---

### 提示词 5: 修改POI类型风格

将末日风格改为旅行风格：

```
请把POI类型从末日风格改为旅行风格：

原类型：hospital, gas_station, supermarket, pharmacy, factory
新类型：cafe, bookstore, restaurant, park, attraction, mall

需要修改：
1. POI.swift 的 POIType 枚举
2. Edge Function 的类型映射
3. 搜索关键词（咖啡、书店、餐厅等）

参考需求文档：/Users/mikeliu/Desktop/tuzi-fuke/guihua/tuzi-旅行版本-产品需求文档.md
```

---

### 提示词 6: 配置AI叙事生成

添加通义千问AI叙事功能：

```
探索结束时需要生成AI叙事：

数据：
- 行走距离：500米
- 探索面积：2500平方米
- 发现POI：3个咖啡店
- 探索时长：10分钟

请调用通义千问API，生成一段旅行风格的叙述文字。

参考原项目的AI调用方式。
```

---

## 开发步骤

### 步骤 1: 理解数据流

```
MapKit搜索 → 候选表 → Edge Function → 正式POI表 → PostGIS查询 → 地图显示
```

### 步骤 2: 修改POI类型定义

修改 `POI.swift`：

```swift
enum POIType: String, Codable, CaseIterable {
    case cafe = "cafe"
    case bookstore = "bookstore"
    case restaurant = "restaurant"
    case park = "park"
    case attraction = "attraction"
    case mall = "mall"
    case convenience_store = "convenience_store"
    case gym = "gym"
    case other = "other"

    var displayName: String {
        switch self {
        case .cafe: return "咖啡店"
        case .restaurant: return "餐厅"
        // ...
        }
    }
}
```

### 步骤 3: 配置MapKit搜索关键词

修改搜索配置：

```swift
let searchConfigs: [(type: String, keywords: [String], radius: Double)] = [
    ("cafe", ["咖啡", "咖啡店", "星巴克", "瑞幸"], 1000),
    ("bookstore", ["书店", "书城", "新华书店"], 1500),
    ("restaurant", ["餐厅", "美食", "网红店"], 1000),
    ("park", ["公园", "广场", "花园"], 2000),
    // ...
]
```

### 步骤 4: 更新Edge Function

部署 `process-poi-candidates` v8：

- 按距离排序处理
- 增加处理数量
- 旅行风格类型映射
- 写入PostGIS location字段

### 步骤 5: 修改探索Tab

将"附近地点"改为"已发现"：

```swift
// 从 user_poi_discoveries 表加载
let response = try await supabase.database
    .from("user_poi_discoveries")
    .select("*")
    .eq("user_id", value: userId.uuidString)
    .order("discovered_at", ascending: false)
    .execute()
```

### 步骤 6: 配置AI叙事

在Edge Function或客户端调用通义千问：

```typescript
const response = await fetch('https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${QWEN_API_KEY}`,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    model: 'qwen-plus',
    messages: [{ role: 'user', content: prompt }]
  })
});
```

---

## 教学检查点

### 检查点 1: MapKit搜索

```
✅ 控制台显示搜索日志
✅ 各类型关键词都有搜索结果
✅ 候选成功提交到数据库
```

### 检查点 2: Edge Function处理

```
✅ 候选被标记为已处理
✅ 正式POI表有数据
✅ location字段不为NULL
✅ 各POI类型都有（咖啡、餐厅、书店等）
```

### 检查点 3: PostGIS查询

```
✅ RPC函数返回附近POI
✅ 按距离排序正确
✅ 地图上显示POI标记
```

### 检查点 4: 发现机制

```
✅ 走近POI 100米内触发弹窗
✅ 发现记录保存到数据库
✅ 探索Tab显示已发现历史
```

### 检查点 5: AI叙事

```
✅ 探索结束时调用AI
✅ 生成旅行风格叙述
✅ 氛围标签正确（peaceful/adventurous等）
```

---

## 常见问题 FAQ

### Q1: POI查询返回空？

**A**: 检查以下几点：

1. pois表的location字段是否有值
2. 坐标顺序是否正确（POINT(经度 纬度)）
3. RPC函数的半径参数是否合理

```sql
-- 检查location字段
SELECT id, name, location FROM pois LIMIT 5;

-- 手动修复
UPDATE pois
SET location = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography
WHERE location IS NULL;
```

### Q2: 只有部分POI类型出现？

**A**: Edge Function的处理顺序问题：

1. 检查候选表中各类型的数量
2. 确认Edge Function按距离排序
3. 增加单次处理数量

```sql
-- 查看候选类型分布
SELECT poi_type, COUNT(*) FROM mapkit_poi_candidates GROUP BY poi_type;
```

### Q3: 探索Tab和主地图重复？

**A**: 需要区分功能：

- 主地图：附近待发现POI（pois表）
- 探索Tab："已发现"历史（user_poi_discoveries表）

修改ExploreTabView，从发现历史表加载数据。

### Q4: AI叙事没有生成？

**A**: 检查以下几点：

1. QWEN_API_KEY是否配置
2. 探索数据是否正确传递
3. API调用是否成功

```swift
// 添加调试日志
appLog(.info, category: "AI", message: "开始调用通义千问 API...")
appLog(.info, category: "AI", message: "探索数据: 距离=\(distance)米")
```

---

## 扩展学习

### 进阶功能

1. **POI评分系统**: 用户对POI打分
2. **收藏功能**: 标记喜欢的地点
3. **分享功能**: 分享探索记录
4. **成就系统**: 探索里程碑

### 相关知识点

- PostGIS空间查询
- Supabase Edge Function
- 通义千问API
- MapKit MKLocalSearch

---

## 参考文件

| 文件 | 用途 |
|------|------|
| POI.swift | POI数据模型（旅行风格类型） |
| POIManager.swift | POI业务逻辑 |
| ExploreTabView.swift | 探索Tab界面 |
| process-poi-candidates (Edge Function) | 候选处理 |
| get_pois_within_radius (RPC) | 空间查询 |

---

## 教学总结

探索系统开发的核心难点：

1. **PostGIS理解**: geography类型字段是空间查询的关键
2. **数据流理清**: 候选 → 正式POI → 发现历史
3. **功能边界**: 主地图负责发现，Tab负责历史

建议教学时：

1. 先讲解完整数据流
2. 演示PostGIS空间查询原理
3. 让学员自己判断"附近地点"应该放哪里
4. 用具体日志帮助定位问题
