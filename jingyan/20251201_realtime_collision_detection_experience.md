# 实时碰撞检测经验总结

**日期**: 2025年12月1日
**项目**: tuzi-fuke (地球新主复刻版)
**功能**: 圈地实时碰撞检测

---

## 背景

在实现圈地功能时，发现碰撞检测只在**确认圈地时**触发，而不是在**行走过程中实时检测**。这导致用户走到别人领地里才发现问题，体验很差。

**期望行为**（参考源项目）：

- 每隔几秒检测一次碰撞
- 接近他人领地时有距离预警（100m/50m/25m）
- 进入领地时立即终止圈地并弹窗提示
- 触觉反馈（震动）

---

## 问题排查过程

### 第一次测试：没有碰撞检测日志

**现象**：启动碰撞监控后，日志只显示 `🚀 启动实时碰撞检测`，但没有任何检测结果

**原因**：`checkPathCollisionComprehensive` 方法只在路径点 >= 2 时才执行

**解决**：添加更多调试日志，确认定时器在正常运行

### 第二次测试：距离始终为 -1.0m

**现象**：

```
检测结果: 碰撞=false, 预警=safe, 距离=-1.0m
```

**分析**：`距离=-1.0m` 表示 `closestDistance` 为 nil，说明没有找到任何领地进行检测

**根因**：原代码过滤逻辑有问题

```swift
// 错误的逻辑：只检测他人领地，自己的领地被过滤掉了
let otherTerritories = allTerritories.filter { $0.ownerId != currentUserId }
```

**关键发现**：用户测试时走的是**自己的领地**（绿色区域），而代码只检测**他人领地**

---

## 源项目分析

查看源项目 `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/TerritoryManager.swift`：

```swift
// 源项目的 checkPathCrossTerritories 方法
private func checkPathCrossTerritories(
    path: [CLLocation],
    currentUserId: UUID
) async -> CollisionResult {
    // 分离他人领地和自己的其他领地
    let otherTerritories = nearbyTerritories.filter { territory in
        guard let territoryUserId = territory.userId else { return false }
        return territoryUserId.uuidString.lowercased() != currentUserId.uuidString.lowercased()
    }

    let ownTerritories = myTerritories

    // 检查与他人领地的碰撞
    for territory in otherTerritories {
        if doesPathIntersectTerritory(path: path, territory: territory) {
            return CollisionResult(
                hasCollision: true,
                collisionType: .pathCrossTerritory,
                message: "轨迹不能穿越他人的领地！",
                ...
            )
        }
    }

    // 检查与自己其他领地的碰撞
    for territory in ownTerritories {
        if doesPathIntersectTerritory(path: path, territory: territory) {
            return CollisionResult(
                hasCollision: true,
                collisionType: .crossOwnTerritory,
                message: "轨迹不能穿越你的其他领地！",
                ...
            )
        }
    }
    ...
}
```

**关键点**：源项目检测**两种碰撞**：

1. 他人领地（`otherTerritories`）
2. 自己的其他领地（`ownTerritories`）

---

## 最终解决方案

### 修改 TerritoryManager.swift

```swift
func checkPathCollisionComprehensive(
    path: [CLLocation],
    currentUserId: UUID,
    locationManager: LocationManager
) -> RealtimeCollisionResult {
    // 1. 检查自相交
    if locationManager.hasPathSelfIntersection() {
        return RealtimeCollisionResult(hasCollision: true, ...)
    }

    // 2. 分离他人领地和自己的领地
    appLog(.debug, category: "实时碰撞", message: "📊 领地统计: 我的=\(territories.count), 附近=\(nearbyTerritories.count)")

    let otherTerritories = nearbyTerritories.filter { $0.ownerId != currentUserId }
    let ownTerritories = territories

    appLog(.debug, category: "实时碰撞", message: "📊 他人领地: \(otherTerritories.count), 自己领地: \(ownTerritories.count)")

    // 3. 检查与他人领地的碰撞
    for territory in otherTerritories {
        for location in path {
            if territory.contains(location) {
                return RealtimeCollisionResult(
                    hasCollision: true,
                    message: "已进入他人领地「\(territory.displayName)」！",
                    ...
                )
            }
        }
    }

    // 4. 检查与自己其他领地的碰撞
    for territory in ownTerritories {
        for location in path {
            if territory.contains(location) {
                return RealtimeCollisionResult(
                    hasCollision: true,
                    message: "轨迹不能穿越你的其他领地！",
                    ...
                )
            }
        }
    }

    // 5. 计算距离预警
    // 6. 返回结果
}
```

### 修改 SimpleMapView.swift

添加定时器实现实时检测：

```swift
@State private var collisionCheckTimer: Timer?
private let collisionCheckInterval: TimeInterval = 5.0  // 每5秒检查一次

private func startCollisionMonitoring() {
    // 立即检查一次
    checkPathCollisionComprehensive(userId: userId)

    // 启动定时器
    collisionCheckTimer = Timer.scheduledTimer(withTimeInterval: collisionCheckInterval, repeats: true) { _ in
        Task { @MainActor in
            self.checkPathCollisionComprehensive(userId: userId)
        }
    }
}
```

---

## 关键经验总结

### 1. 日志是定位问题的关键

添加详细日志后，问题一目了然：

```
📊 领地统计: 我的=1, 附近=1
📊 他人领地: 0, 自己领地: 1
❌ 路径进入自己的领地「领地 #1」
```

### 2. 对比源项目是最快的解决方式

遇到功能不符合预期时，直接查看源项目代码：

```bash
# 搜索相关函数
grep -r "checkPathCollision" /Users/mikeliu/Desktop/tuzi-earthlord/
```

### 3. 领地数据来源要搞清楚

- `territories` - 我的领地（本地数组）
- `nearbyTerritories` - 附近所有领地（从 Supabase 查询）
- 两者需要分开处理，不能简单合并

### 4. 碰撞检测的两个层次

| 层次   | 检测对象                 | 提示语             |
| ---- | -------------------- | --------------- |
| 他人领地 | nearbyTerritories 过滤 | "轨迹不能穿越他人的领地！"  |
| 自己领地 | territories          | "轨迹不能穿越你的其他领地！" |

---

## 最终效果

```
17:14:06.141 📊 领地统计: 我的=1, 附近=1
17:14:06.141 📊 他人领地: 0, 自己领地: 1
17:14:06.141 ❌ 路径进入自己的领地「领地 #1」
17:14:06.141 检测结果: 碰撞=true, 预警=violation, 距离=0.0m
17:14:06.141 ❌ 检测到碰撞违规，立即终止圈地
17:14:06.142 🛑 停止圈地
17:14:06.142 🗑️ 路径已清除
```

- 实时检测正常工作
- 进入自己领地时立即触发违规
- 自动终止圈地并弹窗提示
- 触觉反馈正常

---

## 相关文件

- `TerritoryManager.swift` - 碰撞检测核心逻辑
- `SimpleMapView.swift` - 定时器和UI层
- `LocationManager.swift` - 自相交检测、预警状态

---

## 一句话总结

**碰撞检测要分两类：他人领地和自己领地，不能只检测一类！**
