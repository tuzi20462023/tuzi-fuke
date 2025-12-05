# 建筑放置界面白屏问题修复经验

**日期**: 2025年12月5日
**项目**: tuzi-fuke (地球新主复刻版)
**问题**: 点击"+"选择建筑后，紫色放置界面(BuildingPlacementView)白屏1-2分钟

---

## 问题现象

1. 在领地详情页点击右上角"+"按钮
2. 选择一个建筑模板（如"篝火"）
3. 紫色的建筑放置界面白屏1-2分钟才出现
4. 奇怪的是：先点击其他建筑（如"简易庇护所"），紫色界面秒出，再回去点"篝火"也能秒出

---

## 与AI对话的关键经验

### 1. 描述"可复现的奇怪现象"帮助定位问题

**有效的描述方式**:

```
第二次打开出现紫色界面前全部都打不开了。。。。白屏很久，
我试了回到选择建筑界面选择比如简易庇护所，紫色界面打开了，
再回到篝火也能打开，我退出app重启，发现其实紫色能打开的，
我跳到下面的简易庇护所紫色就秒出
```

**AI分析**: 这个"先点其他建筑就能秒出"的现象说明不是导航嵌套问题，而是**首次数据加载**的问题。某个建筑被点击时触发了数据预加载，后续就都快了。

### 2. 让AI先分析问题再改代码

**有效的提示词**:

```
你觉得哪个更好先理清楚先不要代码
```

**效果**: AI会先分析问题根因，而不是盲目修改代码。最终定位到问题是 `navigationDestination` 预创建视图时传递大数组导致的阻塞。

### 3. 让AI参考原项目架构

**有效的提示词**:

```
也可以参考下源文件：/Users/mikeliu/Desktop/tuzi-earthlord，问题是什么？？
```

**效果**: AI发现原项目使用 `.sheet` 方式而非 `navigationDestination`，这是解决白屏的关键。

---

## 问题根因分析

### 原代码架构（有问题）

```swift
// TerritoryBuildingsView.swift - 原实现
NavigationStack(path: $navigationPath) {
    // ...
}
.navigationDestination(for: String.self) { destination in
    if destination == "buildingList" {
        // ❌ 这里创建视图时传递了大数组
        BuildingListViewInline(
            territoryId: territory.id,
            buildingTemplates: buildingManager.buildingTemplates,  // 大数组
            playerBuildings: buildingManager.playerBuildings,       // 大数组
            onSelectTemplate: { ... }
        )
    } else if destination == "placement" {
        BuildingPlacementViewInline(...)
    }
}
```

**问题**:
1. `navigationDestination` 会在导航发生前**预创建**目标视图
2. 传递 `buildingTemplates` 和 `playerBuildings` 数组时，首次访问这些数据会触发同步加载
3. 主线程被阻塞，导致白屏

### 原项目架构（正确）

```swift
// tuzi-earthlord/TerritoryDetailView.swift - 原项目
NavigationView {
    // ...
}
.sheet(isPresented: $showBuildingList) {
    BuildingBrowserView(...)
}
.sheet(item: $selectedTemplateForPlacement) { template in
    BuildingPlacementView(...)
}
```

**优点**:
1. `.sheet` 是**延迟创建**的，只有真正显示时才创建视图
2. 子视图通过 `BuildingManager.shared` 单例访问数据，不需要父视图传递
3. 数据加载在子视图内部异步进行，不阻塞主线程

---

## 解决方案

### 修改 TerritoryBuildingsView.swift

```swift
// 修改后
struct TerritoryBuildingsView: View {
    let territory: Territory

    @ObservedObject private var buildingManager = BuildingManager.shared

    // ✅ 使用 .sheet 方式，避免预创建视图
    @State private var showBuildingList = false
    @State private var selectedTemplateForPlacement: BuildingTemplate?

    var body: some View {
        NavigationView {  // ✅ 改用 NavigationView
            VStack {
                // ... 建筑列表内容
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showBuildingList = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
        }
        // ✅ 使用 .sheet 打开建筑列表
        .sheet(isPresented: $showBuildingList) {
            BuildingListView(territoryId: territory.id) { template in
                selectedTemplateForPlacement = template
                showBuildingList = false
            }
        }
        // ✅ 选择建筑后打开放置界面
        .sheet(item: $selectedTemplateForPlacement) { template in
            BuildingPlacementView(
                template: template,
                territory: territory
            )
        }
    }
}
```

### 新增 TerritoryTabView.swift

为了完全避免 MapKit 页面的白屏问题，新增了一个独立的"领地"Tab：

```swift
struct TerritoryTabView: View {
    @ObservedObject private var territoryManager = TerritoryManager.shared
    @State private var selectedTerritory: Territory?

    var body: some View {
        NavigationView {
            // 领地列表
            List {
                ForEach(territoryManager.territories) { territory in
                    TerritoryCard(territory: territory, buildingCount: ...)
                        .onTapGesture {
                            selectedTerritory = territory
                        }
                }
            }
        }
        // ✅ 从非MapKit页面弹出 sheet，完全不会白屏
        .sheet(item: $selectedTerritory) { territory in
            TerritoryBuildingsView(territory: territory)
        }
    }
}
```

### 删除的文件

- `BuildingListViewInline.swift` - 不再需要内联版本
- `BuildingPlacementViewInline.swift` - 不再需要内联版本

---

## 意外发现：Supabase 服务故障

修复白屏问题后，用户报告"所有数据都没了"，登录也失败。

**排查过程**:

1. 用 Supabase MCP 查询数据库 → 数据都在（领地2个、POI 608个）
2. 用 curl 测试 API → 返回 500 Internal Server Error
3. 用户截图显示 Supabase Dashboard 的 PostgREST、Auth、Edge Functions 都是 **Unhealthy**

**结论**: 这是 Supabase 云服务临时故障，不是代码问题。等待服务恢复后一切正常。

**经验**: 当"所有功能都坏了"时，先检查云服务状态，不要急于改代码。

---

## 核心经验总结

### 技术经验

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| Sheet 白屏 | `navigationDestination` 预创建视图 | 改用 `.sheet` 延迟创建 |
| 数据加载阻塞 | 父视图传递大数组 | 子视图通过单例访问 |
| 首次慢后续快 | 数据首次加载触发同步操作 | 异步加载 + 单例缓存 |

### 与AI协作经验

1. **描述可复现的奇怪现象**: "先点其他建筑就能秒出" 这种现象帮助AI定位是数据加载问题
2. **让AI先分析再改代码**: 避免盲目修改，先理清问题根因
3. **参考原项目架构**: 原项目的设计决策往往是经过验证的
4. **云服务故障要先排查**: 当"所有功能都坏了"时，先检查服务状态

### NavigationStack vs NavigationView + Sheet

| 特性 | NavigationStack + navigationDestination | NavigationView + .sheet |
|------|----------------------------------------|------------------------|
| 视图创建时机 | 预创建（导航前） | 延迟创建（显示时） |
| 数据传递 | 需要父视图传递 | 可通过单例访问 |
| 首次加载 | 可能阻塞主线程 | 不阻塞 |
| 适用场景 | 简单数据、小列表 | 复杂数据、大列表 |

---

## 修改文件清单

| 文件 | 修改内容 |
|------|----------|
| TerritoryBuildingsView.swift | 改用 .sheet 方式打开建筑列表和放置界面 |
| TerritoryTabView.swift | 新增领地Tab，从非MapKit页面管理建筑 |
| ContentView.swift | 添加领地Tab入口 |
| BuildingManager.swift | 添加 fetchAllPlayerBuildings 方法 |
| TerritoryManager.swift | 添加 refreshTerritories 方法 |

---

## 参考文件

- `/Users/mikeliu/Desktop/tuzi-fuke-building/tuzi-fuke/TerritoryBuildingsView.swift`
- `/Users/mikeliu/Desktop/tuzi-fuke-building/tuzi-fuke/TerritoryTabView.swift`
- `/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/TerritoryDetailView.swift`（原项目参考）
