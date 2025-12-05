# Day 9: 建筑放置界面白屏问题修复教学

**日期**: 2025年12月5日
**功能**: 修复建筑放置界面(BuildingPlacementView)白屏1-2分钟的问题
**难度**: 中等（涉及 SwiftUI 导航架构理解）

---

## 学习目标

完成本教程后，学员将掌握：

1. 理解 `navigationDestination` vs `.sheet` 的区别
2. 诊断 SwiftUI 界面白屏问题
3. 通过描述"可复现的奇怪现象"帮助AI定位问题
4. 使用单例模式避免大数据传递

---

## 问题场景

学员遇到以下问题：

1. 点击"+"按钮选择建筑后，放置界面白屏1-2分钟
2. 但是先点击其他建筑（如"简易庇护所"），界面秒出
3. 然后再点击原来白屏的建筑，也能秒出了
4. 重启App后问题又出现

---

## 教学重点与提示词

### 提示词 1: 描述可复现的奇怪现象

当学员遇到白屏问题时，引导他们这样描述：

```
建筑放置界面白屏问题：

我点击右上角"+"按钮，选择篝火建筑，紫色放置界面白屏了1-2分钟。

奇怪的是：
1. 我回到建筑选择列表，选择"简易庇护所" → 紫色界面秒出
2. 再回去选择"篝火" → 也能秒出了
3. 退出App重启 → 第一次点还是白屏

请先分析问题，不要直接改代码。
```

**教学要点**:
- "可复现的奇怪现象"能帮助AI定位问题
- "先点其他建筑就秒出"说明是首次数据加载问题，不是导航问题
- 让AI先分析再改代码，避免盲目修改

### 提示词 2: 让AI参考原项目

```
请阅读原项目的领地详情页实现：
/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/TerritoryDetailView.swift

特别关注：
1. 它是怎么打开建筑列表和放置界面的？
2. 用的是 NavigationStack 还是 sheet？
3. 数据是怎么传递给子视图的？

对比我们的实现，找出区别。
```

**教学要点**:
- 原项目用 `.sheet` 而非 `navigationDestination`
- 原项目子视图通过 `BuildingManager.shared` 访问数据
- 这种架构避免了预创建视图时的数据加载阻塞

### 提示词 3: 请AI解释技术原理

```
请解释一下：
1. navigationDestination 和 .sheet 在视图创建时机上有什么区别？
2. 为什么 navigationDestination 会导致白屏？
3. 为什么 .sheet 不会有这个问题？

用简单的话解释，不需要代码。
```

**教学要点**:
- `navigationDestination` 会**预创建**目标视图
- 预创建时访问大数组会触发同步加载，阻塞主线程
- `.sheet` 是**延迟创建**，显示时才创建视图

### 提示词 4: 让AI修复问题

```
好的，请帮我修改 TerritoryBuildingsView.swift：

1. 把 NavigationStack + navigationDestination 改成 NavigationView + .sheet
2. 建筑列表用 .sheet(isPresented:) 打开
3. 建筑放置用 .sheet(item:) 打开
4. 子视图通过 BuildingManager.shared 访问数据，不要父视图传递

现有功能要保持正常，只改导航方式。
```

---

## 核心概念讲解

### NavigationStack vs .sheet 对比

| 特性 | NavigationStack + navigationDestination | NavigationView + .sheet |
|------|----------------------------------------|------------------------|
| 视图创建时机 | 预创建（导航前） | 延迟创建（显示时） |
| 数据传递方式 | 需要父视图传递参数 | 可通过单例直接访问 |
| 首次加载 | 可能阻塞主线程 | 不阻塞 |
| 动画效果 | Push 推入 | 从底部滑出 |
| 适用场景 | 简单数据、导航层级 | 复杂数据、弹窗操作 |

### 数据传递模式对比

**错误方式（传递大数组）**:

```swift
// ❌ 预创建时会同步加载这些数组
.navigationDestination(for: String.self) { destination in
    BuildingListView(
        templates: buildingManager.buildingTemplates,  // 大数组
        buildings: buildingManager.playerBuildings      // 大数组
    )
}
```

**正确方式（单例访问）**:

```swift
// ✅ 子视图内部通过单例访问
struct BuildingListView: View {
    @ObservedObject private var buildingManager = BuildingManager.shared

    var body: some View {
        // 使用 buildingManager.buildingTemplates
    }
}
```

---

## 开发步骤

### 步骤 1: 理解问题

1. 让学员复现问题
2. 记录"奇怪现象"（先点其他建筑就能秒出）
3. 向AI描述问题，让AI分析

### 步骤 2: 对比原项目

1. 让AI读取原项目代码
2. 找出架构差异
3. 理解原项目的设计决策

### 步骤 3: 修改代码

1. 将 `NavigationStack` 改为 `NavigationView`
2. 将 `navigationDestination` 改为 `.sheet`
3. 移除父视图传递数组的代码
4. 子视图改用 `BuildingManager.shared`

### 步骤 4: 测试验证

1. 重启App
2. 直接点击"篝火"建筑
3. 确认界面秒出，不再白屏

---

## 代码示例

### 修改前（有问题）

```swift
struct TerritoryBuildingsView: View {
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            // ...
        }
        .navigationDestination(for: String.self) { destination in
            if destination == "buildingList" {
                // ❌ 传递大数组
                BuildingListViewInline(
                    buildingTemplates: buildingManager.buildingTemplates,
                    playerBuildings: buildingManager.playerBuildings
                )
            }
        }
    }
}
```

### 修改后（正确）

```swift
struct TerritoryBuildingsView: View {
    @State private var showBuildingList = false
    @State private var selectedTemplate: BuildingTemplate?

    var body: some View {
        NavigationView {
            // ...
        }
        // ✅ 使用 .sheet 延迟创建
        .sheet(isPresented: $showBuildingList) {
            BuildingListView(territoryId: territory.id) { template in
                selectedTemplate = template
                showBuildingList = false
            }
        }
        .sheet(item: $selectedTemplate) { template in
            BuildingPlacementView(template: template, territory: territory)
        }
    }
}
```

---

## 教学检查点

### 检查点 1: 理解问题

```
✅ 学员能复现白屏问题
✅ 学员能描述"先点其他建筑就秒出"的现象
✅ 学员理解这是首次数据加载问题
```

### 检查点 2: 理解原理

```
✅ 学员能解释 navigationDestination 预创建视图的问题
✅ 学员能解释 .sheet 延迟创建的优点
✅ 学员能解释单例模式避免数据传递的好处
```

### 检查点 3: 修改代码

```
✅ 代码编译通过
✅ 建筑列表能正常打开
✅ 建筑放置界面能正常打开
✅ 不再白屏
```

---

## 常见问题 FAQ

### Q1: 为什么 NavigationStack 会预创建视图？

**A**: SwiftUI 的 `navigationDestination` 需要在导航发生前准备好目标视图的类型信息。虽然文档说是"延迟加载"，但实际上视图的初始化和一些属性访问会在导航前发生，特别是当传递 `@Published` 属性时。

### Q2: .sheet 有什么缺点吗？

**A**:
- 动画效果是从底部滑出，不是 push
- 不能形成导航层级（A → B → C）
- 适合弹窗操作，不适合深层导航

### Q3: 什么时候用 NavigationStack？

**A**:
- 数据简单，不会阻塞
- 需要导航层级（如设置页的多级菜单）
- 需要 push 动画效果

### Q4: 为什么用单例而不是传递参数？

**A**:
- 避免预创建时访问数据
- 数据在 Manager 中缓存，不需要重复加载
- 子视图可以独立刷新，不依赖父视图

---

## 额外知识点

### 诊断白屏问题的通用方法

1. **记录现象**: 什么操作会白屏？白屏多久？
2. **找规律**: 有没有"先做A操作，B就不白屏"的现象？
3. **分析**: 白屏期间是在等什么？（数据加载？网络请求？计算？）
4. **对比**: 原项目/其他正常页面是怎么做的？

### 云服务故障的排查

本次开发中还遇到了 Supabase 服务故障：

```
现象：所有数据都没了，登录失败
排查：
1. 用 MCP 查数据库 → 数据都在
2. 用 curl 测 API → 500 错误
3. 查 Dashboard → PostgREST、Auth 都是 Unhealthy
结论：云服务故障，不是代码问题
```

**教学要点**: 当"所有功能都坏了"时，先检查云服务状态。

---

## 参考文件

| 文件 | 用途 |
|------|------|
| TerritoryBuildingsView.swift | 修改后的领地建筑视图 |
| TerritoryTabView.swift | 新增的领地Tab |
| BuildingListView.swift | 建筑列表（通过单例访问数据） |
| BuildingPlacementView.swift | 建筑放置界面 |

---

## 教学总结

建筑放置白屏问题的核心是 **SwiftUI 导航架构选择**：

1. `navigationDestination` 预创建视图，传递大数组会阻塞
2. `.sheet` 延迟创建视图，不会阻塞
3. 子视图通过单例访问数据，不需要父视图传递

教学时引导学员：
1. 先描述"可复现的奇怪现象"
2. 让AI先分析再改代码
3. 参考原项目的架构设计
4. 理解不同导航方式的适用场景
