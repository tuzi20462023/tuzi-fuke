# 实时碰撞检测实现经验

日期: 2025-12-01

## 问题背景

在圈地功能开发过程中，发现碰撞检测只在确认圈地时执行，而不是实时进行。这导致用户可能走了很长一段路径后，才在确认时发现与他人领地冲突，体验很差。

### 原有问题

- 碰撞检测只在用户点击"确认圈地"时执行一次
- 用户无法在圈地过程中实时知道是否即将进入他人领地
- 缺少距离预警机制，无法提前提示用户调整路线

## 解决过程

### 参考源项目

参考了源项目 `/Users/mikeliu/Desktop/tuzi-earthlord/EarthLord` 的实现，发现其具有完整的实时碰撞检测系统：

1. **TerritoryManager** 中的 `checkPathCollisionComprehensive` 方法
2. **SimpleMapView** 中的定时器机制（每5秒检查一次）
3. 分级预警系统（安全→注意→警告→危险→违规）
4. 触觉反馈（震动提示）

### 实现步骤

#### 第一步：在 TerritoryManager 中实现综合碰撞检测

```swift
// TerritoryManager.swift
func checkPathCollisionComprehensive(
    path: [CLLocation],
    currentUserId: UUID,
    locationManager: LocationManager
) -> RealtimeCollisionResult {
    // 1. 检查自相交
    if locationManager.hasPathSelfIntersection() {
        return RealtimeCollisionResult(
            hasCollision: true,
            collisionType: .selfIntersection,
            message: "轨迹不能自己交叉！",
            closestDistance: 0,
            warningLevel: .violation,
            conflictTerritoryName: nil
        )
    }

    // 2. 检查与他人领地的碰撞
    let allTerritories = territories + nearbyTerritories
    let otherTerritories = allTerritories.filter { $0.ownerId != currentUserId }

    // ... 检查点在领地内、路径穿越领地等

    // 3. 计算距离并返回预警级别
    // ...
}
```

#### 第二步：在 SimpleMapView 中添加定时器

```swift
// SimpleMapView.swift
@State private var collisionCheckTimer: Timer?
private let collisionCheckInterval: TimeInterval = 5.0  // 每5秒检查一次

private func startCollisionMonitoring() {
    // 立即检查一次
    checkPathCollisionComprehensive(userId: userId)

    // 启动定时器
    collisionCheckTimer = Timer.scheduledTimer(
        withTimeInterval: collisionCheckInterval,
        repeats: true
    ) { _ in
        Task { @MainActor in
            self.checkPathCollisionComprehensive(userId: userId)
        }
    }
}
```

## 关键代码修改

### 1. TerritoryManager.swift - checkPathCollisionComprehensive 方法

该方法是核心碰撞检测逻辑，包含以下几个关键部分：

**分离他人领地和自己领地的检测逻辑：**

```swift
let allTerritories = territories + nearbyTerritories
// 关键：排除自己的领地（允许穿过自己的领地）
let otherTerritories = allTerritories.filter { $0.ownerId != currentUserId }
```

**多层次检查：**

1. 自相交检查 - 防止路径自己交叉
2. 点在领地内检查 - 检查路径点是否进入他人领地
3. 路径穿越检查 - 检查路径是否穿越他人领地边界
4. 距离预警 - 计算到最近领地的距离，提供分级预警

**预警级别分级：**

```swift
let warningLevel: WarningLevel
if minDistance > 100 {
    warningLevel = .safe      // 安全（>100m）
} else if minDistance > 50 {
    warningLevel = .caution   // 注意（50-100m）
} else if minDistance > 25 {
    warningLevel = .warning   // 警告（25-50m）
} else {
    warningLevel = .danger    // 危险（<25m）
}
```

### 2. SimpleMapView.swift - 定时器实现

**启动和停止机制：**

```swift
.onChange(of: locationManager.isTracking) { _, isTracking in
    if isTracking {
        startCollisionMonitoring()   // 开始圈地时启动
    } else {
        stopCollisionMonitoring()    // 停止圈地时停止
    }
}

.onDisappear {
    stopCollisionMonitoring()        // 视图消失时停止
}
```

**碰撞处理逻辑：**

```swift
private func checkPathCollisionComprehensive(userId: UUID) {
    let result = territoryManager.checkPathCollisionComprehensive(
        path: currentPath,
        currentUserId: userId,
        locationManager: locationManager
    )

    // 处理碰撞违规（立即终止圈地）
    if result.hasCollision {
        locationManager.stopPathTracking()
        locationManager.clearPath()
        showCollisionAlert = true
        return
    }

    // 处理距离预警（不终止，仅提醒）
    locationManager.updateCollisionWarning(result.message, level: result.warningLevel)
    triggerHapticFeedback(level: result.warningLevel)
}
```

### 3. 触觉反馈系统

根据预警级别提供不同强度的震动反馈：

```swift
private func triggerHapticFeedback(level: WarningLevel) {
    switch level {
    case .caution:
        notificationFeedback.notificationOccurred(.warning)  // 轻微震动1次
    case .warning:
        // 中等震动2次
        impactFeedback.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.impactFeedback.impactOccurred()
        }
    case .danger:
        // 强烈震动3次
    case .violation:
        notificationFeedback.notificationOccurred(.error)  // 错误震动
    case .safe:
        break  // 无震动
    }
}
```

## 遇到的坑

### 坑1：otherTerritories 过滤逻辑导致自己领地被排除

**问题描述：**
最初在碰撞检测中使用了 `allTerritories`，但这会导致用户无法在自己已圈好的领地附近再圈新领地。

**错误代码：**

```swift
let allTerritories = territories + nearbyTerritories
// 直接对所有领地进行碰撞检测
for territory in allTerritories {
    if territory.contains(location) {
        return collision
    }
}
```

**解决方案：**
需要排除当前用户自己的领地，只检查他人领地：

```swift
let otherTerritories = allTerritories.filter { $0.ownerId != currentUserId }
```

**关键要点：**

- 允许用户穿过自己的领地（但不能和他人领地重叠）
- 这符合游戏逻辑：玩家可以在自己的领地群中继续扩张
- 必须传入 `currentUserId` 参数才能正确过滤

### 坑2：nearbyTerritories 为空的问题

**问题描述：**
在开发过程中发现 `nearbyTerritories` 一直为空数组，导致碰撞检测不生效。

**排查过程：**

1. 检查 `queryNearbyTerritories` 是否被调用 - ✓ 已调用
2. 检查 Supabase 查询是否成功 - ✓ 查询成功
3. 检查领地数据是否包含他人领地 - ✗ 只查询到自己的领地

**根本原因：**
`queryNearbyTerritories` 方法查询了附近所有领地，但需要在合适的时机调用，确保能获取到他人的领地数据。

**解决方案：**

```swift
.onAppear {
    Task {
        try? await locationManager.startLocationUpdates()

        // 首次定位后查询附近领地
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            shouldCenterOnUser = true
            Task {
                if let location = locationManager.currentLocation {
                    await territoryManager.refreshTerritories(at: location)
                }
            }
        }
    }
}
```

**关键要点：**

- 需要等待定位成功后再查询附近领地
- 使用 `refreshTerritories` 同时查询自己的和附近的领地
- 确认圈地成功后也要刷新领地数据

### 坑3：定时器的生命周期管理

**问题描述：**
定时器可能在视图销毁后仍在运行，导致内存泄漏或崩溃。

**解决方案：**
在多个位置确保定时器被正确停止：

```swift
.onChange(of: locationManager.isTracking) { _, isTracking in
    if isTracking {
        startCollisionMonitoring()
    } else {
        stopCollisionMonitoring()  // 停止圈地时停止
    }
}

.onDisappear {
    stopCollisionMonitoring()      // 视图消失时停止
}

private func stopCollisionMonitoring() {
    collisionCheckTimer?.invalidate()
    collisionCheckTimer = nil
    locationManager.updateCollisionWarning(nil, level: .safe)
}
```

## 最终解决方案

实现了完整的实时碰撞检测系统，包括：

### 1. 核心功能

- 每5秒自动检查路径与领地的碰撞
- 自相交检测（防止路径自己交叉）
- 点在领地内检测
- 路径穿越领地检测
- 距离预警系统

### 2. 用户体验增强

- 分级预警：安全(>100m) → 注意(50-100m) → 警告(25-50m) → 危险(<25m) → 违规(0m)
- 视觉反馈：不同颜色的警告卡片
- 触觉反馈：根据预警级别震动提示（1-3次不等）
- 碰撞违规时立即停止圈地，防止用户继续浪费时间

### 3. 性能优化

- 使用边界框快速过滤（避免检查所有领地）
- 只检查他人领地（过滤掉自己的领地）
- 定时检查而非实时检查（降低CPU负担）
- 使用 `@MainActor` 确保UI更新在主线程

### 4. 调试和日志

```swift
appLog(.info, category: "碰撞监控", message: "🚀 启动实时碰撞检测")
appLog(.debug, category: "碰撞监控", message: "预警: 距离最近领地 \(Int(minDistance))m")
appLog(.error, category: "碰撞监控", message: "❌ 检测到碰撞违规")
```

## 测试要点

1. **自己的领地测试**
   
   - 在自己已有领地附近圈地
   - 路径穿过自己的领地
   - 确认不会触发碰撞警告

2. **他人领地测试**
   
   - 接近他人领地（测试预警分级）
   - 进入他人领地（应立即停止圈地）
   - 路径穿越他人领地边界

3. **自相交测试**
   
   - 路径自己交叉（应提示违规）
   - 闭环时路径边缘接触（不应算自相交）

4. **性能测试**
   
   - 附近有大量领地时的检测性能
   - 长时间圈地时的内存占用
   - 定时器是否正确停止

## 经验总结

1. **分离关注点**：将碰撞检测逻辑放在 TerritoryManager，UI 反馈放在 SimpleMapView
2. **过滤自己的领地**：允许用户在自己的领地群中扩张，只检查他人领地
3. **定时而非实时**：每5秒检查一次，平衡性能和体验
4. **分级预警**：提前提示用户，而不是只在违规时才报错
5. **多重反馈**：视觉（颜色）+ 触觉（震动）+ 文字（提示）
6. **生命周期管理**：确保定时器在视图销毁时被正确清理

## 参考文件

- `/Users/mikeliu/Desktop/tuzi-fuke/tuzi-fuke/TerritoryManager.swift`
- `/Users/mikeliu/Desktop/tuzi-fuke/tuzi-fuke/SimpleMapView.swift`
- `/Users/mikeliu/Desktop/tuzi-earthlord/EarthLord/EarthLord/TerritoryManager.swift`（源项目参考）
