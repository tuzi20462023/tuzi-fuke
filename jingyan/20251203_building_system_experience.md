# 建筑系统开发经验总结

**日期**: 2025年12月3日
**项目**: tuzi-fuke (地球新主复刻版)
**功能**: 建筑系统 - 模板管理、建造流程、地图显示、坐标转换

---

## 背景

在完成 POI 探索功能后，开始实现建筑系统：

- 从 Supabase 加载建筑模板
- 在领地内选择位置放置建筑
- 建造倒计时和完成通知
- 在主地图上显示已建造的建筑

---

## 与AI对话的经验

### 1. 让AI阅读原项目代码作为参考

**有效的提示词模式**:

```
请阅读原项目 /Users/mikeliu/Desktop/tuzi-earthlord 的以下文件：
- BuildingModels.swift（数据模型）
- BuildingManager.swift（业务逻辑）

分析它是怎么处理建筑坐标存储和显示的。
```

**效果**: AI 发现原项目有关键注释 `// 数据库存储的就是GCJ-02坐标，直接使用，不需要转换`，这帮助定位了坐标偏移问题的根因。

### 2. 提供截图 + 具体数值让问题可量化

**错误示范**:

```
建筑显示位置不对
```

**正确示范**:

```
[截图1: 地图上建筑位置]
[截图2: 建筑详情页]

我测试了一下，建筑放置在领地内，但在主地图上显示偏了很远：
- 我的位置: 114.441392
- 建筑位置: 114.450445
- 偏差约 900 米！

控制台日志：
🏗️ [Coordinator] 添加建筑标记: 小型仓库 @ (23.200576, 114.450445)
```

**效果**: 900 米这个具体数值让 AI 立即意识到这不是正常的 GPS 误差，而是坐标转换出了问题。

### 3. 让AI检查控制台日志中的坐标转换

**有效的提示词模式**:

```
控制台日志如下，帮我看看坐标转换是不是有问题：

🗺️ [地图点击] GCJ-02坐标: (23.200570, 114.45051)
🗺️ [坐标转换] WGS-84坐标: (23.20308, 114.44560)

纬度变化了 0.002511（约280米），这正常吗？
```

**效果**: AI 分析后发现转换逻辑有问题，不应该双重转换。

### 4. 让AI直接删除数据库测试数据

**有效的提示词模式**:

```
好的删除旧的建筑吧重新做一个
```

**效果**: AI 直接用 Supabase MCP 工具删除了错误坐标的旧数据，方便重新测试。

### 5. 提供完整控制台日志确认功能正常

**有效的提示词模式**:

```
好了，在地图上显示了，这个控制台也没问题吧？？
[粘贴完整控制台日志]
```

**效果**: AI 确认关键日志都正常：
- `📍 [BuildingPlacement] 多边形领地，转换 15 个点`
- `📍 [位置验证] 在领地内: true`
- `🏗️ [BuildingManager] 开始建造: storage_small`
- `🎉 [BuildingManager] 建筑完成: 小型仓库`

---

## 遇到的核心 Bug 及解决方案

### Bug 1: 建筑效果显示格式错误

**问题现象**:

建筑详情页的"建筑效果"显示为：
```
+AnyCodableValue(value: 50)
```
而不是期望的：
```
+50
```

**问题分析**:

```swift
// 错误代码
if let value = template.effects[key] {
    Text("+\(value)")  // 直接插值 AnyCodableValue 对象
}
```

`template.effects[key]` 返回的是 `AnyCodableValue` 类型，直接字符串插值会显示类型信息。

**解决方案**:

1. 在 `AnyCodableValue` 结构体中添加 `displayString` 属性：

```swift
struct AnyCodableValue: Codable {
    let value: Any

    /// 用于 UI 显示的字符串
    var displayString: String {
        if let intVal = value as? Int {
            return "\(intVal)"
        } else if let doubleVal = value as? Double {
            return String(format: "%.1f", doubleVal)
        } else if let stringVal = value as? String {
            return stringVal
        } else if let boolVal = value as? Bool {
            return boolVal ? "是" : "否"
        }
        return "\(value)"
    }
}
```

2. 使用新属性：

```swift
if let effect = template.effects[key] {
    Text("+\(effect.displayString)")  // 显示: +50
}
```

---

### Bug 2: 建筑显示位置偏移约 900 米

**问题现象**:

- 在建造界面点击领地内的位置建造建筑
- 建造成功后，主地图上建筑显示在错误的位置
- 偏差约 900 米（经度差 0.009°）

**问题分析**:

坐标转换链出了问题：

```
地图点击 (GCJ-02)
    ↓ gcj02ToWgs84() 转换
存储到数据库 (WGS-84)
    ↓ wgs84ToGcj02() 转换
地图显示 (GCJ-02)
```

但实际上每次转换都有误差，双重转换导致误差累积。

**原项目的做法**（关键发现）:

```swift
// BuildingModels.swift 第311行注释
// 数据库存储的就是GCJ-02坐标，直接使用，不需要转换
```

原项目直接存储地图坐标（GCJ-02），显示时也不转换。

**解决方案**:

1. **放置建筑时** - 直接保存地图点击坐标，不转换：

```swift
// BuildingPlacementView.swift
private func startBuilding() async {
    guard let gcj02Location = selectedLocation else { return }

    // 直接保存 GCJ-02 坐标到数据库（与原项目保持一致）
    let request = BuildingConstructionRequest(
        templateId: template.templateId,
        territoryId: territory.id,
        location: gcj02Location,  // 不转换！
        customName: nil
    )
    // ...
}
```

2. **显示建筑时** - 直接使用存储的坐标：

```swift
// MapViewRepresentable.swift
for building in buildings {
    guard let location = building.location else { continue }

    // 数据库存储的已经是 GCJ-02 坐标，直接使用
    let gcj02Coord = CLLocationCoordinate2D(
        latitude: location.coordinates[1],
        longitude: location.coordinates[0]
    )
    // 不再调用 CoordinateConverter.convertIfNeeded()
}
```

3. **位置验证时** - 领地边界转换为 GCJ-02 后再与点击坐标比较：

```swift
// BuildingPlacementView.swift - isLocationInTerritory()
// path 存储的是 WGS-84，需要转换为 GCJ-02 来与点击坐标比较
let locations = path.compactMap { point -> CLLocation? in
    guard let lat = point["lat"], let lon = point["lon"] else { return nil }
    let wgs84 = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    let gcj02 = CoordinateConverter.convertIfNeeded(wgs84)  // 转换！
    return CLLocation(latitude: gcj02.latitude, longitude: gcj02.longitude)
}
```

---

### Bug 3: 建造界面没有显示领地边界

**问题现象**:

打开建造界面时，地图上没有显示绿色的领地边界多边形。

**问题分析**:

之前修复坐标问题时，错误地移除了领地边界的坐标转换：

```swift
// 错误：直接使用 WGS-84 坐标
coordinates = path.compactMap { point in
    guard let lat = point["lat"], let lon = point["lon"] else { return nil }
    return CLLocationCoordinate2D(latitude: lat, longitude: lon)  // WGS-84
}
```

但领地数据存储的是 WGS-84 坐标，地图显示需要 GCJ-02 坐标。

**解决方案**:

领地边界绘制时需要转换坐标：

```swift
// BuildingPlacementView.swift - addTerritoryPolygon()
if territory.isPolygon, let path = territory.path, !path.isEmpty {
    // 领地 path 存储的是 WGS-84 坐标，需要转换为 GCJ-02 用于地图显示
    coordinates = path.compactMap { point in
        guard let lat = point["lat"], let lon = point["lon"] else { return nil }
        let wgs84 = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        return CoordinateConverter.convertIfNeeded(wgs84)  // 转换为 GCJ-02
    }
}
```

---

### Bug 4: 启动时白屏（POI 阻塞 UI）

**问题现象**:

应用启动后白屏约 10 秒，控制台显示大量 POI 搜索日志。

**问题分析**:

POI 搜索是在主线程同步执行的，阻塞了 UI 渲染。

**解决方案**:

将 POI 初始化改为异步：

```swift
// ContentView.swift
.task {
    // POI 异步初始化，不阻塞 UI
    Task.detached(priority: .background) {
        await POIManager.shared.initializeAsync()
    }
}
```

---

## 坐标系统经验总结

### 核心原则

| 场景 | 坐标系 | 说明 |
|------|--------|------|
| GPS 原始数据 | WGS-84 | iOS CLLocationManager 返回 |
| 数据库存储（领地） | WGS-84 | GPS 路径直接存储 |
| 数据库存储（建筑） | GCJ-02 | 地图点击坐标直接存储 |
| 地图显示 | GCJ-02 | MapKit 在中国使用 |
| 距离计算 | 统一坐标系 | 两个点必须是同一坐标系 |

### 转换时机

```
领地数据流:
GPS采集(WGS-84) → 存储(WGS-84) → 显示时转换(GCJ-02)

建筑数据流:
地图点击(GCJ-02) → 存储(GCJ-02) → 显示时直接用(GCJ-02)
```

### 关键教训

1. **不要双重转换**: 每次转换都有误差，累积后会导致几百米偏差
2. **统一坐标系再比较**: 验证位置时，确保两个坐标是同一坐标系
3. **参考原项目注释**: 原项目的注释往往包含关键决策说明

---

## 问题排查流程

### 坐标问题排查

1. **打印转换前后坐标**:

```swift
print("🗺️ [地图点击] 坐标: (\(coordinate.latitude), \(coordinate.longitude))")
print("🗺️ [存储坐标]: (\(savedLat), \(savedLon))")
print("🗺️ [显示坐标]: (\(displayLat), \(displayLon))")
```

2. **计算偏差距离**:

```
纬度 1° ≈ 111 公里
经度 1° ≈ 111 * cos(纬度) 公里

偏差 0.009° 经度 ≈ 900 米
```

3. **对比原项目实现**:

```
让AI阅读原项目代码，找到关键注释
```

### 数据问题排查

1. **查询数据库**:

```sql
SELECT id, building_name, location, status
FROM player_buildings
ORDER BY created_at DESC LIMIT 5;
```

2. **删除测试数据重新测试**:

```sql
DELETE FROM player_buildings WHERE id = 'xxx';
```

---

## 文件修改清单

| 文件 | 修改内容 |
|------|----------|
| Building.swift | 添加 `AnyCodableValue.displayString` 属性 |
| BuildingDetailView.swift | 使用 `effect.displayString` 显示效果值 |
| BuildingPlacementView.swift | 移除保存时的坐标转换，修复位置验证 |
| MapViewRepresentable.swift | 移除显示时的坐标转换 |
| ContentView.swift | POI 异步初始化 |

---

## 核心经验总结

### 技术经验

1. **坐标系理解是关键**: GPS(WGS-84) vs 地图(GCJ-02) 的区别必须搞清楚
2. **避免双重转换**: 存储什么坐标，显示时就用什么坐标
3. **Any 类型需要特殊处理**: `AnyCodableValue` 显示时要提取实际值
4. **异步初始化避免阻塞**: 耗时操作放后台，先让 UI 显示

### 与AI协作经验

1. **提供具体数值**: "偏了900米" 比 "位置不对" 有用得多
2. **让AI读原项目**: 原项目注释包含重要决策信息
3. **让AI操作数据库**: 直接删除错误数据，快速重新测试
4. **提供完整日志确认**: 让 AI 确认所有关键步骤都正确执行

---

## 参考文件

- `/Users/mikeliu/Desktop/tuzi-fuke-building/tuzi-fuke/Building.swift`
- `/Users/mikeliu/Desktop/tuzi-fuke-building/tuzi-fuke/BuildingDetailView.swift`
- `/Users/mikeliu/Desktop/tuzi-fuke-building/tuzi-fuke/BuildingPlacementView.swift`
- `/Users/mikeliu/Desktop/tuzi-fuke-building/tuzi-fuke/MapViewRepresentable.swift`
- `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/BuildingModels.swift`（原项目参考）
