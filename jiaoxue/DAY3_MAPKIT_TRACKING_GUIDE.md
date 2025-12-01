# Day3：地图轨迹调试与真机崩溃日志经验

## 背景回顾

- 目标：把 `tuzi-fuke` 的行走圈地恢复到原项目的“实时轨迹 + 闭环多边形 + Supabase 领地”体验。
- 症状：地图上只有蓝点，没有轨迹；圈地失败后残留的线条无法清理；真机在室内走动时偶尔闪退但看不到控制台日志。
- 过程：我在室内边走边截图，实时把“点数、距离、面积”面板和控制台日志发给 AI，逐步定位问题。

## 轨迹不显示 → 如何定位并解决

1. **症状确认**
   - 真机截图中只有蓝点，偶尔能看到淡淡的线段，但永远和蓝点偏移。
   - 控制台刷出了大量 `A non-zero alpha color is required...` 的 MapKit 报错。
2. **对比原项目**
   - 查阅 `/Users/mikeliu/Desktop/tuzi-earthlord/EarthLord/EarthLord/MapViewRepresentable.swift`，确认原版在 `updatePath` 里会根据 `LocationManager.isInMainlandChina` 把每个路径点先转成 GCJ-02，再传给 `MKPolyline`。
   - 我的版本在 `tuzi-fuke/MapViewRepresentable.swift` 中直接把 WGS-84 坐标扔给 `MKPolyline`，导致 MapKit 与蓝点坐标系不一致（差 300~500 米，看上去像“没有轨迹”）。
3. **根因**
   - 地图视图已经在 `makeUIView/updateUIView` 中通过 `CoordinateConverter.convertIfNeeded` 使用 GCJ-02 居中。
   - 但轨迹 overlay、闭环 polygon、领地 overlay 仍旧使用原始 WGS-84。
4. **解决动作**
   - 在 `updateTrackingPath` 中把 `coordinates.map { CoordinateConverter.convertIfNeeded($0) }` 后再创建 `MKPolyline`/`MKPolygon`，同样在 `createOverlay(for:)` 中对领地中心点和多边形顶点做转换。
   - 重新运行，轨迹与蓝点对齐，闭环后绿色多边形也能留在地图上。

## 轨迹残留 → 何时清理

1. **现象**：取消圈地或圈地失败后，地图上仍保留上一段的轨迹。
2. **原因**：`updateTrackingPath` 故意移除了 “isTracking 才画线” 的限制，以便用户回顾路径；但如果想要“失败后清除”，需要在 `locationManager.clearPath()` 里发通知让 MapView 刷新。
3. **实践**：
   - 在 SimpleMapView 的“取消圈地”按钮或错误弹窗中调用 `locationManager.clearPath()` 并把 `shouldCenterOnUser = true`，即可清理掉残留线路。

## 真机崩溃日志如何获取（带电脑/不带电脑两种情况）

### 情况A：可以带电脑跑

1. Xcode 连接 iPhone，正常 `Run`。
2. 一旦崩溃，Xcode 控制台立即打印堆栈，用 `⌘L` 可跳到崩溃行，保存日志即可。

### 情况B：手机断开后才崩（最常见）

1. **先正常运行**，不需要电脑在身边；崩溃发生时 iOS 会自动生成 crash log。
2. 回到电脑前，打开 Xcode → `Window > Devices and Simulators`。
3. 左侧选中自己的 iPhone → 点击右侧中部的 `Open Console`（如果版本较新，还会有 “Open Recent Logs” 按钮）。
4. 在 Console 窗口或 “Recent Logs” 面板中，左下角搜索 `tuzi-fuke`，即可看到最新的 `.crash` 记录，双击即可查看/复制。
5. 若仍找不到，可以：
   - 打开 Finder → `~/Library/Logs/CrashReporter/MobileDevice/<你的iPhone>/`；
   - 或在手机上进入 `设置 > 隐私与安全性 > 分析与改进 > 分析数据`，找到 `tuzi-fuke` 的崩溃条目，分享给自己。

> 提示：只有连接过的设备才会在 Devices 面板里显示 Crash Logs。如果按钮灰色，先点击 `Open Console` 再切换到 “Action” 菜单里的 `Open System Log…`，就能看到最近的 crash 列表。

## 和 AI 协作的实战经验

- **提供上下文**：遇到轨迹问题时，我先贴控制台输出和真机截图，说明“地点、点数、距离”。AI 才能判断这是坐标系问题而不是绘图逻辑。
- **对比原仓库**：每次修 bug 前都会指定原仓库里对应的文件（例如 `MapViewRepresentable.swift` 的第几段），这样 AI 可以精确对照。
- **现场实验 + 反馈**：在屋里走动时，我把状态面板和控制台的点数/距离对齐，让 AI 明白“GPS 精度不足”导致的抖动，避免错判为算法错误。
- **崩溃排查流程**：无法带电脑出门时，先随便跑到崩溃，再回来用 `Devices and Simulators > Open Console` 把 crash 日志导出给 AI。

## 下一步

1. 带着已经修好的轨迹系统到室外完成一圈，确认闭环成功、Supabase 写入与 `validate-territory` 校验无误。
2. 圈地成功后接入 `BuildingManager`，实现在领地内放置建筑。
3. 把上面的经验整理成课堂 Demo：演示“如何发现轨迹偏移”“如何提取 crash log”“如何与 AI 对话定位问题”。

---

以上内容是我在 Day3 调试 MapKit 轨迹、处理崩溃日志时的真实流程，可直接作为教学引用或复盘资料。
