# Day 8: 建筑系统开发教学指南

**日期**: 2025年12月3日
**功能**: 建筑系统 - 模板管理、建造流程、地图显示
**难度**: 中等（涉及坐标转换）

---

## 学习目标

完成本教程后，学员将掌握：

1. 建筑模板数据库设计与查询
2. SwiftUI + MapKit 实现建筑放置界面
3. 坐标系转换（WGS-84 vs GCJ-02）
4. 建造倒计时和状态管理
5. 地图标注（Annotation）显示建筑

---

## 教学重点与常见坑点

### 坑点 1: 坐标系混淆（最重要！）

**现象**: 建筑显示位置偏移几百米

**原因**: 混淆了 WGS-84（GPS）和 GCJ-02（中国地图）坐标系

**正确做法**:

```
领地数据: GPS采集(WGS-84) → 存储(WGS-84) → 显示转换(GCJ-02)
建筑数据: 地图点击(GCJ-02) → 存储(GCJ-02) → 显示直接用(GCJ-02)
```

**教学提示**: 让学员先理解两种坐标系的区别，再动手写代码。

### 坑点 2: Any 类型的字符串插值

**现象**: UI 显示 `+AnyCodableValue(value: 50)` 而不是 `+50`

**原因**: Swift 的 `Any` 类型直接插值会显示类型信息

**解决方案**: 添加 `displayString` 计算属性

```swift
var displayString: String {
    if let intVal = value as? Int {
        return "\(intVal)"
    }
    // ...
}
```

### 坑点 3: 领地边界验证坐标不一致

**现象**: 点击领地内的位置，但验证结果显示"不在领地内"

**原因**: 领地 path 是 WGS-84，点击坐标是 GCJ-02，直接比较会不匹配

**解决方案**: 验证时统一坐标系

---

## AI 提示词模板

### 提示词 1: 建筑效果显示问题

当学员遇到效果显示格式问题时使用：

```
我的建筑详情页效果显示有问题：

[截图: 显示 +AnyCodableValue(value: 50)]

预期显示: +50
实际显示: +AnyCodableValue(value: 50)

请帮我修复这个问题。代码在 BuildingDetailView.swift。
```

---

### 提示词 2: 建筑位置偏移问题

当学员遇到建筑位置不对时使用：

```
建筑显示位置有问题：

[截图: 主地图上建筑位置]

我在领地内点击位置建造，但建筑显示在很远的地方。

控制台日志：
[粘贴相关日志]

请检查坐标转换逻辑是否有问题。相关文件：
- BuildingPlacementView.swift（建造）
- MapViewRepresentable.swift（显示）
```

---

### 提示词 3: 让AI参考原项目

当遇到复杂问题时使用：

```
请阅读原项目的建筑相关代码：
/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/BuildingModels.swift

特别关注：
1. location 字段的解码逻辑
2. 坐标是 WGS-84 还是 GCJ-02
3. 显示时是否有转换

然后对比我们的实现，找出问题。
```

---

### 提示词 4: 领地边界不显示

当建造界面没有显示领地边界时使用：

```
建造界面没有显示领地边界：

[截图: 空白地图]

控制台日志：
📍 [BuildingPlacement] 多边形领地，转换 X 个点
✅ [BuildingPlacement] 绘制领地边界，点数: X

请检查 BuildingPlacementView.swift 中的：
1. addTerritoryPolygon 方法
2. MKMapViewDelegate 的 rendererFor 方法
```

---

### 提示词 5: 删除测试数据重新测试

当需要清理错误数据时使用：

```
请帮我删除数据库中的测试建筑数据，我需要重新测试。

先查询一下 player_buildings 表有哪些数据，然后删除它们。
```

---

### 提示词 6: 确认功能正常

测试完成后确认功能时使用：

```
我测试了建筑功能，请帮我确认控制台日志是否正常：

[粘贴完整控制台日志]

特别确认：
1. 领地边界是否正确绘制
2. 位置验证是否通过
3. 建造是否成功开始
4. 建筑是否在正确位置显示
```

---

## 开发步骤

### 步骤 1: 数据库准备

1. 确认 `building_templates` 表有数据
2. 确认 `player_buildings` 表 RLS 策略正确

```sql
-- 检查模板数据
SELECT template_id, name, tier, category FROM building_templates;

-- 检查 RLS
SELECT * FROM pg_policies WHERE tablename = 'player_buildings';
```

### 步骤 2: 建筑列表界面

创建 `BuildingListView.swift`：

- 从 BuildingManager 获取模板列表
- 按分类分组显示
- 点击进入放置流程

### 步骤 3: 建筑放置界面

创建 `BuildingPlacementView.swift`：

- 显示领地边界（MKPolygon）
- 处理地图点击事件
- 验证点击位置是否在领地内
- 确认建造

**关键代码结构**:

```swift
struct BuildingPlacementView: View {
    let template: BuildingTemplate
    let territory: Territory
    @State private var selectedLocation: CLLocationCoordinate2D?
    @State private var isValidLocation = false

    var body: some View {
        ZStack {
            TerritoryMapView(...)  // 地图
            bottomPanel             // 底部信息面板
        }
    }
}
```

### 步骤 4: 地图显示建筑

修改 `MapViewRepresentable.swift`：

- 添加建筑标注（BuildingMapAnnotation）
- 处理标注点击事件
- 区分建造中/已完成状态

### 步骤 5: 建筑详情页

创建 `BuildingDetailView.swift`：

- 显示建筑状态
- 显示建造进度/完成时间
- 显示建筑效果

---

## 教学检查点

### 检查点 1: 数据加载

```
✅ 建筑模板列表能正常加载
✅ 控制台显示: ✅ [BuildingManager] 加载了 X 个建筑模板
```

### 检查点 2: 领地边界显示

```
✅ 建造界面显示绿色领地边界
✅ 控制台显示: ✅ [BuildingPlacement] 绘制领地边界，点数: X
```

### 检查点 3: 位置验证

```
✅ 点击领地内显示"在领地内: true"
✅ 点击领地外显示"在领地内: false"
```

### 检查点 4: 建造流程

```
✅ 点击确认建造后开始倒计时
✅ 倒计时结束后状态变为 active
✅ 建筑在主地图正确位置显示
```

### 检查点 5: 建筑详情

```
✅ 效果显示为 +50 而不是 +AnyCodableValue(...)
✅ 状态正确显示（建造中/运行中）
```

---

## 常见问题 FAQ

### Q1: 建筑模板列表为空？

**A**: 检查数据库 `building_templates` 表是否有数据。如果没有，需要先插入测试数据。

```sql
INSERT INTO building_templates (template_id, name, tier, category, ...)
VALUES ('storage_small', '小型仓库', 1, 'storage', ...);
```

### Q2: 领地边界不显示？

**A**: 检查以下几点：

1. `MKMapViewDelegate` 是否正确设置
2. `rendererFor overlay` 方法是否返回 `MKPolygonRenderer`
3. 坐标是否正确转换为 GCJ-02

### Q3: 建筑位置偏移几百米？

**A**: 坐标转换问题。确保：

1. 保存时不转换（直接存地图点击坐标）
2. 显示时不转换（直接用存储坐标）
3. 验证时统一坐标系

### Q4: 位置验证总是失败？

**A**: 领地 path 是 WGS-84，点击坐标是 GCJ-02。验证时需要：

```swift
// 将领地 path 转换为 GCJ-02 再比较
let gcj02 = CoordinateConverter.convertIfNeeded(wgs84)
```

### Q5: 建造完成后状态没更新？

**A**: 检查 BuildingManager 的定时器是否正常运行，以及 `completeConstruction` 方法是否被调用。

---

## 扩展学习

### 进阶功能

1. **升级系统**: 建筑等级提升
2. **维修系统**: 耐久度恢复
3. **拆除功能**: 移除建筑
4. **资源消耗**: 对接资源系统

### 相关知识点

- MapKit 自定义标注
- CoreLocation 坐标系
- SwiftUI 与 UIKit 混合使用
- Supabase 实时订阅（Realtime）

---

## 参考文件

| 文件 | 用途 |
|------|------|
| Building.swift | 数据模型（含 AnyCodableValue） |
| BuildingManager.swift | 业务逻辑 |
| BuildingListView.swift | 建筑列表 |
| BuildingPlacementView.swift | 放置界面 |
| BuildingDetailView.swift | 详情页 |
| MapViewRepresentable.swift | 地图显示 |
| CoordinateConverter.swift | 坐标转换 |

---

## 教学总结

建筑系统开发的核心难点是**坐标系理解**。建议教学时：

1. 先讲解 WGS-84 和 GCJ-02 的区别
2. 画出数据流图，标注每个环节的坐标系
3. 让学员自己推导应该在哪里转换
4. 用具体数值（如"偏了900米"）帮助理解问题

其他功能相对简单，主要是 SwiftUI + MapKit 的常规用法。
