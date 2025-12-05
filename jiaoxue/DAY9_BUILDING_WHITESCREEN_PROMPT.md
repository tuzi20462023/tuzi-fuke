# Day 9: 建筑放置白屏问题修复提示词

**日期**: 2025年12月5日
**功能**: 修复建筑放置界面白屏问题
**分支**: `feature/building-system`

---

## 开始前准备

### 确认问题存在

1. 打开App，进入领地详情
2. 点击右上角"+"按钮
3. 选择任意建筑（如篝火）
4. 观察是否白屏1-2分钟

---

## AI 提示词（复制使用）

### 提示词 1: 描述问题现象

```
建筑放置界面白屏问题：

项目路径: /Users/mikeliu/Desktop/tuzi-fuke-building
相关文件: tuzi-fuke/TerritoryBuildingsView.swift

问题现象：
1. 点击"+"按钮，选择"篝火"建筑
2. 紫色放置界面白屏1-2分钟才出现
3. 但是：如果先点击"简易庇护所"，秒出
4. 然后再点"篝火"，也能秒出了
5. 重启App后第一次点还是白屏

请先分析问题原因，不要直接改代码。
```

---

### 提示词 2: 让AI对比原项目

```
请阅读原项目的领地详情实现：
/Users/mikeliu/Desktop/tuzi-earthlord/earthlord/EarthLord/TerritoryDetailView.swift

对比我们的实现：
/Users/mikeliu/Desktop/tuzi-fuke-building/tuzi-fuke/TerritoryBuildingsView.swift

分析以下问题：
1. 原项目用什么方式打开建筑列表和放置界面？
2. 我们用什么方式？
3. 数据传递方式有什么区别？
4. 这些区别会导致什么问题？

先不要写代码。
```

---

### 提示词 3: 理解技术原理

```
请用简单的话解释：

1. NavigationStack + navigationDestination 的视图创建时机是什么？
2. NavigationView + .sheet 的视图创建时机是什么？
3. 为什么前者可能导致白屏，后者不会？
4. 传递大数组参数 vs 通过单例访问，哪个更好？为什么？

不需要代码，用通俗语言解释。
```

---

### 提示词 4: 修复问题

```
好的，请帮我修改 TerritoryBuildingsView.swift：

1. 把 NavigationStack 改成 NavigationView
2. 把 navigationDestination 改成 .sheet
3. 建筑列表用 .sheet(isPresented:) 打开
4. 建筑放置用 .sheet(item:) 打开
5. 子视图通过 BuildingManager.shared 访问数据
6. 删除不需要的 Inline 视图文件

保持现有功能正常，只改导航方式。
```

---

### 提示词 5: 如果需要新增领地Tab

```
为了完全避免 MapKit 页面的白屏问题，请帮我新增一个"领地"Tab：

1. 创建 TerritoryTabView.swift
2. 显示我的领地列表
3. 点击领地打开 TerritoryBuildingsView（用 .sheet）
4. 这样从非MapKit页面管理建筑，不会有白屏问题

在 ContentView.swift 中添加这个Tab入口。
```

---

### 提示词 6: 验证修复

```
我修改后测试了：
1. 重启App
2. 直接点击"篝火"建筑
3. [描述结果：秒出/还是白屏]

[如果还有问题，粘贴控制台日志]

请帮我确认修复是否成功。
```

---

### 提示词 7: 云服务故障排查

如果修改后发现"所有数据都没了"：

```
修复白屏后，发现App里所有数据都没了：
- 领地不显示
- POI不显示
- 登录失败

请帮我检查：
1. 用 Supabase MCP 查询数据库，数据还在吗？
2. 如果数据在，可能是什么问题？
3. 是不是 Supabase 服务故障？
```

---

## 开发顺序建议

```
1. 描述问题现象 (提示词 1)
      ↓
2. 对比原项目 (提示词 2)
      ↓
3. 理解技术原理 (提示词 3)
      ↓
4. 修复问题 (提示词 4)
      ↓
5. [可选] 新增领地Tab (提示词 5)
      ↓
6. 验证修复 (提示词 6)
      ↓
7. [如遇到] 云服务故障排查 (提示词 7)
```

---

## 关键代码参考

### 修改前（有问题的代码）

```swift
struct TerritoryBuildingsView: View {
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            // ...
        }
        // ❌ navigationDestination 预创建视图
        .navigationDestination(for: String.self) { destination in
            if destination == "buildingList" {
                BuildingListViewInline(
                    // ❌ 传递大数组
                    buildingTemplates: buildingManager.buildingTemplates,
                    playerBuildings: buildingManager.playerBuildings
                )
            }
        }
    }
}
```

### 修改后（正确的代码）

```swift
struct TerritoryBuildingsView: View {
    @State private var showBuildingList = false
    @State private var selectedTemplate: BuildingTemplate?

    var body: some View {
        NavigationView {
            // ...
        }
        // ✅ .sheet 延迟创建
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

// ✅ 子视图通过单例访问数据
struct BuildingListView: View {
    @ObservedObject private var buildingManager = BuildingManager.shared
    // 不需要父视图传递 buildingTemplates
}
```

---

## 完成后检查清单

- [ ] 理解 navigationDestination 预创建的问题
- [ ] 理解 .sheet 延迟创建的优点
- [ ] TerritoryBuildingsView 改用 .sheet 方式
- [ ] 子视图通过单例访问数据
- [ ] 删除不需要的 Inline 视图文件
- [ ] 测试：直接点击建筑不再白屏
- [ ] [可选] 新增领地Tab
- [ ] 代码提交到 feature/building-system 分支

---

## 常见问题

### Q: 改完后还是白屏？

A: 检查以下几点：
1. 是否真的改成了 `.sheet`？
2. 子视图是否还在通过参数接收大数组？
3. 完全退出App重新启动测试

### Q: 改完后数据都没了？

A: 可能是 Supabase 服务故障：
1. 用 MCP 查数据库确认数据是否存在
2. 检查 Supabase Dashboard 服务状态
3. 等待服务恢复后重试

### Q: .sheet 和 NavigationLink 哪个好？

A: 看场景：
- 需要导航层级（A→B→C）：用 NavigationLink
- 弹窗操作、复杂数据：用 .sheet
- 数据加载可能阻塞：用 .sheet

---

## 相关文档

- 经验总结: `jingyan/20251205_building_placement_whitescreen_fix.md`
- 建筑系统教程: `jiaoxue/DAY8_BUILDING_SYSTEM_TUTORIAL.md`
- 建筑系统提示词: `jiaoxue/DAY8_BUILDING_SYSTEM_PROMPT.md`
