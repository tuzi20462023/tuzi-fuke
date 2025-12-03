# POI 探索发现系统开发经验总结

**开发时间**: 2025年12月2日 - 12月3日
**开发模式**: AI 辅助开发（Claude Code + Supabase MCP）
**功能**: 实现 POI 探索发现，玩家走到真实商户附近时触发发现弹窗

---

## 一、与 AI 对话的经验

### 1.1 明确告诉 AI 工作目录和分支

**重要**: 使用 Git Worktree 时，必须明确告诉 AI 当前工作环境：

```
我的工作目录是 /Users/mikeliu/Desktop/tuzi-fuke-explore，对应 feature/explore 分支。

这是一个 Git Worktree，跟主仓库 /Users/mikeliu/Desktop/tuzi-fuke (main 分支) 共享 Git 历史。

请在这个目录继续开发探索功能。不要切换分支，不要操作其他 worktree 目录。
```

**原因**: AI 容易搞混多个目录，导致在错误的分支上操作。

### 1.2 让 AI 先分析原项目再写代码

**错误做法**:
```
帮我实现 POI 发现功能
```

**正确做法**:
```
请先阅读原项目 tuzi-earthlord 的 POIManager.swift 和 DiscoveryManager.swift：
- 原项目的 POI 数据从哪里来？
- 触发距离是多少米？
- 防止重复弹窗用什么机制？

先不要写代码，分析清楚再说。
```

**效果**: 避免 AI 自己发明一套逻辑，而是参考成熟实现。

### 1.3 用日志和截图定位问题

**关键**: 测试时截图 + 复制日志，一起发给 AI：

```
这是日志 [粘贴日志文件]
这是截图 [截图1] [截图2]

问题：同一个 POI 弹了两次弹窗，看看是什么原因？
```

**AI 能做的**:
- 分析日志找异常
- 用 Supabase MCP 查数据库
- 定位是前端问题还是数据问题

### 1.4 让 AI 使用 MCP 工具查数据库

**关键对话**:
```
你可以看看数据库的东西，开 supabase mcp，是不是历史数据缓存？
```

**AI 执行的操作**:
```sql
-- 查询重复的 POI
SELECT name, COUNT(*) FROM pois GROUP BY name HAVING COUNT(*) > 1;

-- 删除重复数据
DELETE FROM pois WHERE poi_key IS NULL;
```

**优势**: 不需要自己去 Supabase Dashboard 操作，AI 直接帮你查和改。

---

## 二、遇到的 Bug 和解决方案

### Bug 1: POI 不触发弹窗

**现象**:
- 走到商店附近，没有弹窗
- 日志显示 "缓存 33 个 POI"

**原因**:
客户端的 `generatePOIFromCandidates` 方法限制每种类型最多 1 个，总共最多 5 个 POI。

```swift
// 原来的错误代码
for candidate in candidates {
    if createdTypes.contains(candidate.poi_type) {
        continue  // 跳过重复类型
    }
    // ...
    if createdCount >= 5 {
        break  // 最多创建5个
    }
}
```

**分析过程**:
1. 让 AI 阅读原项目代码
2. 发现原项目用 PostGIS 后端查询，不是客户端生成
3. 决定重构为后端模式

**解决方案**:
1. 启用 PostGIS 扩展
2. 创建 RPC 函数 `get_pois_within_radius`
3. 将 1237 个候选 POI 迁移到 pois 表
4. 客户端改为纯查询模式

### Bug 2: 同一个 POI 弹两次弹窗

**现象**:
- 「百姓缘大药房(浅山小筑店)」弹了两次
- 第一次显示 "资源 139 个"，第二次显示 "资源 100 个"

**原因**:
数据库有重复数据：
- 12月2日创建的旧数据（poi_key 为 null）
- 12月3日迁移的新数据（poi_key 不为 null）
- 同一个店名有多条不同坐标的记录

**查询验证**:
```sql
SELECT name, COUNT(*) FROM pois GROUP BY name HAVING COUNT(*) > 1;
-- 结果：沙县小吃 16条，百姓缘大药房 4条...
```

**解决方案**:
```sql
-- 1. 删除没有 poi_key 的旧数据
DELETE FROM pois WHERE poi_key IS NULL;

-- 2. 对同名 POI 去重，只保留一条
DELETE FROM pois
WHERE id NOT IN (
    SELECT DISTINCT ON (name) id
    FROM pois
    ORDER BY name, created_at ASC
);
```

**结果**: 从 1762 条减少到 608 条唯一 POI。

### Bug 3: feature/explore 分支缺少 triggeredPOIIds 修复

**现象**:
- main 分支的 POI 能正常触发
- feature/explore 分支的 POI 不触发

**原因**:
- 之前在 main 分支修复了 `triggeredPOIIds` 机制
- feature/explore 分支是从旧代码创建的，没有这个修复

**解决方案**:
```bash
# 从 main 分支同步 POIManager.swift
git checkout main -- tuzi-fuke/POIManager.swift
git checkout main -- tuzi-fuke/POI.swift
```

### Bug 4: POIType 缺少成员

**现象**:
构建错误：`Type 'POIType' has no member 'pharmacy'`

**原因**:
- main 分支的 POI.swift 添加了新类型（pharmacy, convenienceStore, bank）
- feature/explore 分支的 POI.swift 没有这些类型

**解决方案**:
同步 POI.swift 文件，添加缺失的枚举成员和 color 属性。

### Bug 5: MapKit import 位置错误

**现象**:
构建错误：`Cannot find type 'MKAnnotation' in scope`

**原因**:
`import MapKit` 被放在了文件中间，而不是顶部。

**解决方案**:
将 `import MapKit` 移到文件顶部。

---

## 三、架构重构经验

### 3.1 从客户端生成改为后端查询

**原来的架构**（有问题）:
```
MapKit搜索 → 提交候选表 → 客户端生成POI → 本地缓存 → 触发弹窗
```

**问题**:
- 客户端生成逻辑限制了 POI 数量
- 每次启动都要搜索 MapKit，浪费资源
- 坐标转换容易出错

**新架构**:
```
MapKit搜索 → 提交候选表 → Edge Function处理 → PostGIS存储
                                                    ↓
客户端定位 → PostGIS RPC查询 → 本地缓存 → 触发弹窗
```

**优势**:
- 后端处理去重和类型映射
- PostGIS 支持高效的空间查询
- 客户端逻辑简化为纯查询

### 3.2 PostGIS RPC 函数

```sql
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

### 3.3 Edge Function 处理候选

```typescript
// process-poi-candidates Edge Function
// 自动将候选表的数据迁移到 pois 表
// 处理类型映射：pharmacy → hospital, convenience_store → supermarket
// 生成 poi_key 用于去重
```

---

## 四、关键代码片段

### 4.1 PostGIS RPC 查询（客户端）

```swift
func updatePOICacheWithRPC(location: CLLocation) async {
    // 转换为 GCJ-02 坐标
    let gcjCoord = CoordinateConverter.wgs84ToGcj02(location.coordinate)

    // 调用 PostGIS RPC
    let response = try await supabase.database
        .rpc("get_pois_within_radius", params: [
            "p_lat": gcjCoord.latitude,
            "p_lon": gcjCoord.longitude,
            "p_radius_km": 1.0
        ])
        .execute()

    // 解析结果
    let rpcPOIs = try decoder.decode([RPCPOIModel].self, from: response.data)
    cachedPOIs = rpcPOIs.map { ... }
}
```

### 4.2 防止重复弹窗的双重检查

```swift
// 1. discoveredPOIIds: 数据库中已发现的（永久）
if discoveredPOIIds.contains(poi.id) { continue }

// 2. triggeredPOIIds: 本次会话已触发的（临时）
if triggeredPOIIds.contains(poi.id) { continue }

// 触发后记录
triggeredPOIIds.insert(poi.id)
await markPOIDiscovered(poi: poi, userId: userId)
```

### 4.3 200米重置机制

```swift
private func cleanupDistantTriggeredPOIs(currentLocation: CLLocation) {
    for poiId in triggeredPOIIds {
        guard let poi = cachedPOIs.first(where: { $0.id == poiId }) else {
            toRemove.insert(poiId)
            continue
        }

        let distance = currentLocation.distance(from: poiLocation)
        if distance > 200 {  // 离开200米后允许再次触发
            toRemove.insert(poiId)
        }
    }
    triggeredPOIIds.subtract(toRemove)
}
```

---

## 五、总结

### 开发效率

| 任务 | 预估时间 | 实际时间 | 备注 |
|------|----------|----------|------|
| 基础 POI 发现 | 4小时 | 2小时 | AI 快速生成代码 |
| 调试触发问题 | - | 3小时 | 数据重复问题花了很多时间 |
| PostGIS 重构 | 2小时 | 1小时 | Supabase MCP 提高效率 |
| 数据清理 | - | 30分钟 | AI 直接操作数据库 |

### AI 协作要点

1. **明确工作环境**: 告诉 AI 目录、分支、不要做什么
2. **先分析后写码**: 让 AI 读原项目，理解设计意图
3. **用工具验证**: 让 AI 用 MCP 查数据库，用日志分析问题
4. **截图+日志**: 问题描述越具体，AI 定位越准确
5. **让 AI 清理数据**: 重复数据、测试数据，AI 可以直接用 SQL 处理

### 避坑指南

1. **不要让 AI 自己发明架构** - 参考原项目
2. **注意分支同步** - Worktree 容易遗漏修复
3. **数据要去重** - MapKit 返回多个坐标点
4. **坐标系要统一** - 全部用 GCJ-02 计算距离
5. **测试要清理** - 测试数据会影响后续开发
