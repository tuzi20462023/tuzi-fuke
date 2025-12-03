# Day 7 POI 探索发现系统教程 V2 - PostGIS 后端查询版

**目标**: 实现 POI 探索发现功能，玩家走到真实商户附近时触发发现弹窗
**时间**: 3-4小时
**开发模式**: AI 辅助开发（Claude Code + Supabase MCP）
**结果**: 玩家走到药店、超市等真实地点 100 米内时弹出发现提示

---

## 与 V1 版本的区别

| 对比项 | V1（客户端生成） | V2（后端查询） |
|--------|------------------|----------------|
| POI 数据来源 | 客户端 MapKit 搜索后生成 | 后端 PostGIS 查询 |
| POI 数量 | 每种类型最多1个，共5个 | 1km 范围内所有 POI |
| 去重机制 | 无 | poi_key 唯一约束 |
| 查询效率 | 边界框查询 | PostGIS 空间索引 |
| 数据同步 | 每次启动搜索 | 后端 Edge Function 处理 |

**推荐使用 V2 版本**，架构更清晰，POI 数量更多。

---

## 🎯 学习目标

完成本教程后，你将掌握：

- [x] PostGIS 空间扩展的使用
- [x] RPC 函数实现空间查询
- [x] Edge Function 处理 POI 候选
- [x] 100 米范围触发机制
- [x] 防止重复弹窗的双重检查
- [x] 坐标系转换（WGS-84 ↔ GCJ-02）

---

## 📋 前置准备

### 已完成的功能

- [x] Day 1-4 基础框架（地图、圈地、碰撞检测）
- [x] Supabase 认证和数据库
- [x] LocationManager 位置追踪
- [x] CoordinateConverter 坐标转换工具

### 本日任务清单

- [ ] 任务1: 启用 PostGIS 扩展和创建表
- [ ] 任务2: 创建 PostGIS RPC 函数
- [ ] 任务3: 部署 Edge Function 处理候选
- [ ] 任务4: 创建 POI 数据模型
- [ ] 任务5: 创建 POIManager（纯查询模式）
- [ ] 任务6: 集成到 SimpleMapView
- [ ] 任务7: 测试和数据清理

---

## 🚀 任务1: 启用 PostGIS 和创建数据库表 (20分钟)

### 🤖 AI 提示词

```
请帮我在 Supabase 执行以下 SQL，创建 POI 探索系统的数据库表：

1. 启用 PostGIS 扩展
2. 创建 mapkit_poi_candidates 表（MapKit 搜索结果暂存）
3. 创建 pois 表，包含：
   - 基础字段：id, name, type, description, latitude, longitude
   - PostGIS 字段：location geography(Point, 4326)
   - 游戏字段：total_items, remaining_items, is_active
   - 去重字段：poi_key（唯一约束）
   - 来源字段：source（mapkit/manual）
4. 创建 user_poi_discoveries 表（用户发现记录）
5. 启用 RLS 并设置策略
6. 创建空间索引

使用 Supabase MCP 的 apply_migration 工具执行。
```

### SQL 参考

```sql
-- 启用 PostGIS
CREATE EXTENSION IF NOT EXISTS postgis;

-- POI 候选表
CREATE TABLE IF NOT EXISTS mapkit_poi_candidates (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    poi_type TEXT NOT NULL,
    address TEXT,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    mapkit_id TEXT,
    submitted_by UUID,
    processed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 正式 POI 表（带 PostGIS）
CREATE TABLE IF NOT EXISTS pois (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    description TEXT,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    location geography(Point, 4326),
    poi_key TEXT UNIQUE,
    source TEXT DEFAULT 'mapkit',
    is_active BOOLEAN DEFAULT TRUE,
    total_items INT DEFAULT 100,
    remaining_items INT DEFAULT 100,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 用户发现记录表
CREATE TABLE IF NOT EXISTS user_poi_discoveries (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id TEXT NOT NULL,
    poi_id UUID REFERENCES pois(id),
    poi_name TEXT,
    poi_type TEXT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    discovered_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, poi_id)
);

-- 创建空间索引
CREATE INDEX IF NOT EXISTS idx_pois_location ON pois USING GIST (location);

-- 更新 location 字段的触发器
CREATE OR REPLACE FUNCTION update_poi_location()
RETURNS TRIGGER AS $$
BEGIN
    NEW.location = ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326)::geography;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_poi_location
BEFORE INSERT OR UPDATE ON pois
FOR EACH ROW EXECUTE FUNCTION update_poi_location();
```

---

## 🚀 任务2: 创建 PostGIS RPC 函数 (15分钟)

### 🤖 AI 提示词

```
请帮我创建两个 PostGIS RPC 函数：

1. get_pois_within_radius(p_lat, p_lon, p_radius_km)
   - 返回指定范围内的所有活跃 POI
   - 按距离排序
   - 返回字段：id, name, type, description, latitude, longitude, total_items, remaining_items, distance_meters

2. get_nearby_undiscovered_pois(p_user_id, p_lat, p_lon, p_radius_meters)
   - 返回指定范围内用户未发现的 POI
   - 用于触发发现检查

使用 Supabase MCP 的 apply_migration 工具执行。
```

### SQL 参考

```sql
-- 查询范围内的 POI
CREATE OR REPLACE FUNCTION get_pois_within_radius(
    p_lat DOUBLE PRECISION,
    p_lon DOUBLE PRECISION,
    p_radius_km DOUBLE PRECISION DEFAULT 1.0
) RETURNS TABLE (
    id UUID,
    name TEXT,
    type TEXT,
    description TEXT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    total_items INT,
    remaining_items INT,
    distance_meters DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id, p.name, p.type, p.description,
        p.latitude, p.longitude,
        p.total_items, p.remaining_items,
        ST_Distance(
            p.location::geography,
            ST_MakePoint(p_lon, p_lat)::geography
        ) as distance_meters
    FROM pois p
    WHERE p.is_active = TRUE
      AND ST_DWithin(
          p.location::geography,
          ST_MakePoint(p_lon, p_lat)::geography,
          p_radius_km * 1000
      )
    ORDER BY distance_meters;
END;
$$ LANGUAGE plpgsql;
```

---

## 🚀 任务3: 部署 Edge Function 处理候选 (20分钟)

### 🤖 AI 提示词

```
请帮我部署一个 Edge Function: process-poi-candidates

功能：
1. 从 mapkit_poi_candidates 表获取未处理的候选（processed = false）
2. 类型映射：pharmacy → hospital, convenience_store → supermarket
3. 生成 poi_key 用于去重：{name}_{lat.toFixed(3)}_{lon.toFixed(3)}
4. 插入到 pois 表（ON CONFLICT DO NOTHING）
5. 标记候选为已处理

使用 Supabase MCP 的 deploy_edge_function 工具部署。
```

### Edge Function 代码参考

```typescript
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const POI_TYPE_MAPPING: Record<string, string> = {
  pharmacy: "hospital",
  convenience_store: "supermarket",
  bank: "other",
  atm: "other",
  cafe: "restaurant",
};

Deno.serve(async (req: Request) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  // 获取未处理的候选
  const { data: candidates } = await supabase
    .from("mapkit_poi_candidates")
    .select("*")
    .eq("processed", false)
    .limit(100);

  let processedCount = 0;

  for (const candidate of candidates || []) {
    // 类型映射
    let mappedType = candidate.poi_type;
    if (POI_TYPE_MAPPING[mappedType]) {
      mappedType = POI_TYPE_MAPPING[mappedType];
    }

    // 生成 poi_key
    const poiKey = `${candidate.name}_${candidate.latitude.toFixed(3)}_${candidate.longitude.toFixed(3)}`;

    // 插入 POI
    await supabase.from("pois").insert({
      name: candidate.name,
      type: mappedType,
      description: candidate.address,
      latitude: candidate.latitude,
      longitude: candidate.longitude,
      poi_key: poiKey,
      source: "mapkit",
    }).single();

    // 标记已处理
    await supabase
      .from("mapkit_poi_candidates")
      .update({ processed: true })
      .eq("id", candidate.id);

    processedCount++;
  }

  return new Response(JSON.stringify({ processed: processedCount }));
});
```

---

## 🚀 任务4: 创建 POI 数据模型 (15分钟)

### 🤖 AI 提示词

```
请帮我创建 POI.swift 文件：

1. POIType 枚举：
   - 类型：hospital, supermarket, restaurant, school, park, gasStation, factory, convenienceStore, bank, pharmacy, other
   - 属性：displayName（中文）, iconName（SF Symbol）, color（十六进制颜色）

2. POI 结构体：
   - 字段：id, name, type, latitude, longitude, totalItems, remainingItems, createdAt
   - 计算属性：coordinate, hasResources

3. RPCPOIModel 结构体（RPC 返回数据）：
   - 额外字段：distance_meters

4. POIAnnotation 类（地图标注）：
   - 继承 MKAnnotation
   - 属性：poi, coordinate, title, subtitle

参考项目中 Territory.swift 的代码风格。
```

---

## 🚀 任务5: 创建 POIManager（纯查询模式）(45分钟)

### 🤖 AI 提示词

```
请帮我创建 POIManager.swift，要求：

1. @MainActor + ObservableObject + 单例模式

2. 配置常量：
   - discoveryRange = 100  // 发现距离（米）
   - resetDistance = 200   // 重置距离（米）
   - checkDistance = 30    // 检查间隔（米）
   - cacheRadius = 1000    // 缓存范围（米）

3. Published 属性：
   - cachedPOIs: [POI]
   - discoveredPOIIds: Set<UUID>
   - filteredPOIs: [POI]  // 筛选后的 POI
   - lastDiscoveredPOI: POI?
   - showDiscoveryAlert: Bool
   - isLoading: Bool
   - selectedTypes: Set<POIType>  // 筛选的类型

4. 私有属性：
   - triggeredPOIIds: Set<UUID>  // 已触发弹窗的
   - lastCheckLocation: CLLocation?
   - lastCacheUpdateLocation: CLLocation?

5. 核心方法：
   a) onLocationReady(location:userId:) async
      - 使用 PostGIS RPC 查询附近 POI
      - 加载用户已发现记录
      - 预标记 100 米内的 POI
      - 异步提交 MapKit 候选

   b) updatePOICacheWithRPC(location:) async
      - 调用 get_pois_within_radius RPC
      - 转换坐标系（GPS → GCJ-02）
      - 有降级机制（RPC 失败用边界框查询）

   c) checkNearbyPOIs(location:userId:) async -> POI?
      - 检查 100 米内未发现的 POI
      - 先清理 200 米外的触发记录
      - 发现后记录到数据库

   d) markNearbyPOIsAsTriggered(location:)
      - 预标记已在范围内的 POI
      - 防止启动时立即弹窗

6. 关键点：
   - 使用 RPC 调用：supabase.database.rpc("get_pois_within_radius", params: [...])
   - 坐标转换：CoordinateConverter.wgs84ToGcj02()
   - 双重检查：discoveredPOIIds + triggeredPOIIds

参考原项目 ExplorationManager 的触发机制。
```

### 关键代码段

**PostGIS RPC 调用**:

```swift
func updatePOICacheWithRPC(location: CLLocation) async {
    let gcjCoord = CoordinateConverter.wgs84ToGcj02(location.coordinate)

    do {
        let response = try await supabase.database
            .rpc("get_pois_within_radius", params: [
                "p_lat": gcjCoord.latitude,
                "p_lon": gcjCoord.longitude,
                "p_radius_km": cacheRadius / 1000.0
            ])
            .execute()

        let decoder = JSONDecoder()
        let rpcPOIs = try decoder.decode([RPCPOIModel].self, from: response.data)

        cachedPOIs = rpcPOIs.map { rpcPOI in
            POI(
                id: rpcPOI.id,
                name: rpcPOI.name,
                type: POIType(rawValue: rpcPOI.type) ?? .other,
                latitude: rpcPOI.latitude,
                longitude: rpcPOI.longitude,
                totalItems: rpcPOI.total_items ?? 100,
                remainingItems: rpcPOI.remaining_items ?? 100,
                createdAt: nil
            )
        }
    } catch {
        // 降级到普通查询
        await updatePOICacheFallback(location: location)
    }
}
```

**100 米触发 + 200 米重置**:

```swift
func checkNearbyPOIs(location: CLLocation, userId: UUID) async -> POI? {
    let gcjCoord = CoordinateConverter.wgs84ToGcj02(location.coordinate)
    let currentLocation = CLLocation(latitude: gcjCoord.latitude, longitude: gcjCoord.longitude)

    // 先清理远离的触发记录
    cleanupDistantTriggeredPOIs(currentLocation: currentLocation)

    for poi in cachedPOIs {
        // 跳过已发现的（数据库记录）
        if discoveredPOIIds.contains(poi.id) { continue }

        // 跳过已触发的（本次会话）
        if triggeredPOIIds.contains(poi.id) { continue }

        let poiLocation = CLLocation(latitude: poi.latitude, longitude: poi.longitude)
        let distance = currentLocation.distance(from: poiLocation)

        if distance <= discoveryRange {  // 100米
            triggeredPOIIds.insert(poi.id)
            await markPOIDiscovered(poi: poi, userId: userId)
            lastDiscoveredPOI = poi
            showDiscoveryAlert = true
            return poi
        }
    }
    return nil
}

private func cleanupDistantTriggeredPOIs(currentLocation: CLLocation) {
    var toRemove: Set<UUID> = []
    for poiId in triggeredPOIIds {
        guard let poi = cachedPOIs.first(where: { $0.id == poiId }) else {
            toRemove.insert(poiId)
            continue
        }
        let distance = currentLocation.distance(from: CLLocation(latitude: poi.latitude, longitude: poi.longitude))
        if distance > resetDistance {  // 200米
            toRemove.insert(poiId)
        }
    }
    triggeredPOIIds.subtract(toRemove)
}
```

---

## 🚀 任务6: 集成到 SimpleMapView (30分钟)

### 🤖 AI 提示词

```
请修改 SimpleMapView.swift，添加 POI 发现功能：

1. 添加 POIManager:
   @StateObject private var poiManager = POIManager.shared

2. 添加 POI 检查定时器:
   @State private var poiCheckTimer: Timer?
   private let poiCheckInterval: TimeInterval = 2.0

3. 在 onAppear 首次定位成功时:
   - 调用 poiManager.onLocationReady(location:userId:)

4. 开始探索/圈地时:
   - 启动 POI 检查定时器
   - 每 2 秒调用 poiManager.checkNearbyPOIs()

5. 结束探索/圈地时:
   - 停止 POI 检查定时器

6. 添加 POI 发现弹窗（自定义样式）:
   - 显示 POI 图标、名称、类型
   - 显示可获得资源数量
   - "太棒了!" 按钮关闭

7. 在 MapViewRepresentable 中显示 POI 标注

参考现有的碰撞检测定时器实现。
```

---

## 🚀 任务7: 测试和数据清理 (30分钟)

### 测试步骤

1. **启动应用，检查日志**
   ```
   ✅ PostGIS 查询完成，共 XXX 个 POI
   ✅ 缓存 XXX 个 POI，预标记 X 个已在范围内
   ```

2. **开始探索，走向附近商店**
   - 进入 100 米时应弹出发现弹窗
   - 弹窗显示 POI 名称、类型、资源数

3. **验证防重复机制**
   - 同一个 POI 不应重复弹窗
   - 离开 200 米后再回来，应该能再次触发（如果未记录到数据库）

### 🤖 数据清理提示词

如果发现重复数据，让 AI 帮你清理：

```
数据库有重复的 POI 数据，帮我清理：

1. 查看有多少重复（按名字分组）
2. 删除没有 poi_key 的旧数据
3. 对同名 POI 去重，只保留一条
4. 确认最终数量

使用 Supabase MCP 执行。
```

### 清理 SQL 参考

```sql
-- 查看重复数据
SELECT name, COUNT(*) FROM pois GROUP BY name HAVING COUNT(*) > 1;

-- 删除旧数据（没有 poi_key）
DELETE FROM pois WHERE poi_key IS NULL;

-- 同名去重（保留最早的）
DELETE FROM pois
WHERE id NOT IN (
    SELECT DISTINCT ON (name) id
    FROM pois
    ORDER BY name, created_at ASC
);
```

---

## 🚨 常见问题

### Q1: POI 查询返回空

**可能原因**:
- PostGIS 扩展未启用
- location 字段为空
- RPC 函数有语法错误

**排查命令**:
```sql
SELECT COUNT(*) FROM pois WHERE location IS NOT NULL;
SELECT * FROM get_pois_within_radius(23.2, 114.4, 1.0);
```

### Q2: 同一个 POI 弹两次

**原因**: 数据库有重复数据（同名不同坐标）

**解决**: 使用上面的清理 SQL

### Q3: 距离计算不准

**原因**: 坐标系不一致

**解决**: 确保查询时用 GCJ-02 坐标

```swift
let gcjCoord = CoordinateConverter.wgs84ToGcj02(location.coordinate)
```

### Q4: 启动时立即弹窗

**原因**: 没有预标记已在范围内的 POI

**解决**: 在 `onLocationReady` 结束时调用 `markNearbyPOIsAsTriggered`

---

## 📊 功能完成度

| 层级 | 功能点 | 状态 |
|------|--------|------|
| L1 POI发现 | MapKit搜索附近POI | ✅ |
| L1 POI发现 | POI显示在地图上 | ✅ |
| L1 POI发现 | POI类型筛选(8类) | ✅ |
| L2 探索会话 | 开始/结束探索 | ✅ |
| L2 探索会话 | 探索距离统计 | ✅ |
| L3 物品掉落 | 系统随机生成物品 | ⏳ |
| L3 物品掉落 | 掉落结果展示UI | ⏳ |
| L5 搜刮 | POI搜刮(进入范围触发) | ⏳ |
| L6 高级 | 网格探索统计 | ✅ |
| L6 高级 | 热量计算 | ✅ |

---

## 🎯 下一步

完成 POI 发现后，可以继续实现：

1. **L3 物品掉落**: 发现 POI 时随机掉落物品
2. **L5 搜刮**: 进入 POI 范围后主动搜刮获取资源
3. **探索排行榜**: 按发现数量/距离排名

---

**恭喜完成 Day 7 V2！** 🎉

你已经掌握了 PostGIS 后端查询模式的 POI 发现系统。
