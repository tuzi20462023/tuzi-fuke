import SwiftUI
import MapKit

/// UIKit MKMapView 的 SwiftUI 包装器
struct MapViewRepresentable: UIViewRepresentable {

    // MARK: - 绑定属性
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var territoryManager: TerritoryManager
    @ObservedObject var poiManager: POIManager
    @ObservedObject var buildingManager: BuildingManager
    @Binding var shouldCenterOnUser: Bool

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()

        // 基础配置
        mapView.mapType = .hybrid  // 混合卫星图
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true

        // 交互配置
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true

        // 设置代理
        mapView.delegate = context.coordinator

        // 添加长按手势（用于圈地）
        let longPressGesture = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPressGesture.minimumPressDuration = 0.5
        mapView.addGestureRecognizer(longPressGesture)

        // 保存引用到 Coordinator
        context.coordinator.territoryManager = territoryManager

        // 初始区域（如果有位置则使用，否则用默认）
        if let location = locationManager.currentLocation {
            let coordinate = CoordinateConverter.convertIfNeeded(location.coordinate)
            let region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            )
            mapView.setRegion(region, animated: false)
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // 居中到用户位置
        if shouldCenterOnUser, let location = locationManager.currentLocation {
            let coordinate = CoordinateConverter.convertIfNeeded(location.coordinate)
            let region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            )
            mapView.setRegion(region, animated: true)

            // 重置标志（在主线程异步执行避免 SwiftUI 警告）
            DispatchQueue.main.async {
                shouldCenterOnUser = false
            }
        }

        // 更新我的领地 Overlay
        context.coordinator.updateMyTerritories(
            on: mapView,
            territories: territoryManager.territories,
            currentUserId: AuthManager.shared.currentUser?.id
        )

        // 更新附近领地 Overlay（包括他人的）
        context.coordinator.updateNearbyTerritories(
            on: mapView,
            territories: territoryManager.nearbyTerritories,
            currentUserId: AuthManager.shared.currentUser?.id
        )

        // 更新选中位置预览
        context.coordinator.updateSelectedLocation(
            on: mapView,
            coordinate: territoryManager.selectedLocation,
            radius: territoryManager.defaultRadius
        )

        // 更新行走轨迹线（使用pathUpdateVersion触发更新）
        let _ = locationManager.pathUpdateVersion  // 订阅版本号变化
        context.coordinator.updateTrackingPath(
            on: mapView,
            coordinates: locationManager.pathCoordinates,
            isTracking: locationManager.isTracking,
            isClosed: locationManager.isPathClosed
        )

        // POI 隐藏机制：不在主地图显示 POI 标注
        // 玩家需要探索到 100 米范围内才会触发发现弹窗
        // 参考源项目 EarthLord 的设计：未发现的 POI 不显示在地图上

        // 更新建筑标记
        context.coordinator.updateBuildings(
            on: mapView,
            buildings: buildingManager.playerBuildings,
            templates: buildingManager.buildingTemplates
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {

        weak var territoryManager: TerritoryManager?

        // 领地 Overlay（支持圆形和多边形）
        private var myTerritoryOverlays: [UUID: MKOverlay] = [:]       // 我的领地
        private var nearbyTerritoryOverlays: [UUID: MKOverlay] = [:]   // 附近领地（含他人）
        private var selectedOverlay: MKCircle?

        // 轨迹追踪 Overlay
        private var trackingPolyline: MKPolyline?
        private var closedPolygon: MKPolygon?
        private var pathPointAnnotations: [MKPointAnnotation] = []  // 路径点标记

        // POI 标注
        private var poiAnnotations: [UUID: POIAnnotation] = [:]

        // 建筑标记
        private var buildingAnnotations: [UUID: BuildingMapAnnotation] = [:]

        // MARK: - 长按手势处理

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            guard let mapView = gesture.view as? MKMapView else { return }

            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)

            print("📍 [MapView] 长按位置: \(coordinate.latitude), \(coordinate.longitude)")

            // 通知 TerritoryManager
            Task { @MainActor in
                territoryManager?.selectLocation(coordinate)
            }
        }

        // MARK: - 我的领地 Overlay 更新

        func updateMyTerritories(on mapView: MKMapView, territories: [Territory], currentUserId: UUID?) {
            // 找出需要添加和删除的领地
            let currentIds = Set(myTerritoryOverlays.keys)
            let newIds = Set(territories.map { $0.id })

            // 删除不存在的
            let toRemove = currentIds.subtracting(newIds)
            for id in toRemove {
                if let overlay = myTerritoryOverlays[id] {
                    mapView.removeOverlay(overlay)
                    myTerritoryOverlays.removeValue(forKey: id)
                }
            }

            // 添加新的
            let toAdd = newIds.subtracting(currentIds)
            for territory in territories where toAdd.contains(territory.id) {
                let overlay = createOverlay(for: territory, isOwned: true)
                myTerritoryOverlays[territory.id] = overlay
                mapView.addOverlay(overlay)
                print("🗺️ [Coordinator] 添加我的领地: \(territory.displayName), 类型: \(territory.type.rawValue)")
            }
        }

        // MARK: - 附近领地 Overlay 更新

        func updateNearbyTerritories(on mapView: MKMapView, territories: [Territory], currentUserId: UUID?) {
            // 过滤掉自己的领地（避免重复渲染）
            let otherTerritories = territories.filter { territory in
                guard let userId = currentUserId else { return true }
                return territory.ownerId != userId
            }

            // 找出需要添加和删除的领地
            let currentIds = Set(nearbyTerritoryOverlays.keys)
            let newIds = Set(otherTerritories.map { $0.id })

            // 删除不存在的
            let toRemove = currentIds.subtracting(newIds)
            for id in toRemove {
                if let overlay = nearbyTerritoryOverlays[id] {
                    mapView.removeOverlay(overlay)
                    nearbyTerritoryOverlays.removeValue(forKey: id)
                }
            }

            // 添加新的
            let toAdd = newIds.subtracting(currentIds)
            for territory in otherTerritories where toAdd.contains(territory.id) {
                let overlay = createOverlay(for: territory, isOwned: false)
                nearbyTerritoryOverlays[territory.id] = overlay
                mapView.addOverlay(overlay)
                print("🗺️ [Coordinator] 添加他人领地: \(territory.displayName), 类型: \(territory.type.rawValue)")
            }
        }

        // MARK: - 创建领地 Overlay

        /// 根据领地类型创建对应的 Overlay（圆形或多边形）
        private func createOverlay(for territory: Territory, isOwned: Bool) -> MKOverlay {
            if territory.isPolygon {
                let coords = territory.toCoordinates()
                    .map { CoordinateConverter.convertIfNeeded($0) }
                if coords.count >= 3 {
                    let polygon = MKPolygon(coordinates: coords, count: coords.count)
                    polygon.title = isOwned ? "my_territory" : "other_territory"
                    polygon.subtitle = territory.id.uuidString
                    return polygon
                }
            }

            // 默认使用圆形覆盖层
            let rawCoordinate = CLLocationCoordinate2D(
                latitude: territory.centerLatitude,
                longitude: territory.centerLongitude
            )
            let displayCoordinate = CoordinateConverter.convertIfNeeded(rawCoordinate)
            let circle = MKCircle(center: displayCoordinate, radius: territory.radius)
            circle.title = isOwned ? "my_territory" : "other_territory"
            circle.subtitle = territory.id.uuidString
            return circle
        }

        // MARK: - 向后兼容的旧方法

        func updateTerritories(on mapView: MKMapView, territories: [Territory]) {
            updateMyTerritories(on: mapView, territories: territories, currentUserId: nil)
        }

        // MARK: - 选中位置预览

        func updateSelectedLocation(on mapView: MKMapView, coordinate: CLLocationCoordinate2D?, radius: Double) {
            // 移除旧的预览
            if let oldOverlay = selectedOverlay {
                mapView.removeOverlay(oldOverlay)
                selectedOverlay = nil
            }

            // 添加新的预览（不需要坐标转换）
            if let coord = coordinate {
                let circle = MKCircle(center: coord, radius: radius)
                selectedOverlay = circle
                mapView.addOverlay(circle)
            }
        }

        // MARK: - 行走轨迹更新

        /// 更新行走轨迹显示
        /// - 移除了 isTracking 限制：停止追踪后轨迹仍然保留显示
        /// - 参考原项目 EarthLord/MapViewRepresentable.swift 的 updatePath 方法
        func updateTrackingPath(on mapView: MKMapView, coordinates: [CLLocationCoordinate2D], isTracking: Bool, isClosed: Bool) {
            // 移除旧的轨迹线
            if let oldPolyline = trackingPolyline {
                mapView.removeOverlay(oldPolyline)
                trackingPolyline = nil
            }

            // 移除旧的闭合多边形
            if let oldPolygon = closedPolygon {
                mapView.removeOverlay(oldPolygon)
                closedPolygon = nil
            }

            // 将路径点转换到 MapKit 坐标系（中国大陆需要GCJ-02）
            let convertedCoords = coordinates.map { CoordinateConverter.convertIfNeeded($0) }

            // 更新路径点标记
            updatePathPointAnnotations(on: mapView, coordinates: convertedCoords, isTracking: isTracking)

            // 至少需要2个点才能画线（移除了 isTracking 限制，停止后仍显示轨迹）
            guard convertedCoords.count >= 2 else { return }

            // 始终绘制轨迹线（这样用户能看到走过的路径）
            let polyline = MKPolyline(coordinates: convertedCoords, count: convertedCoords.count)
            // 使用 title 标记轨迹类型，供 rendererFor 判断颜色
            polyline.title = isClosed ? "closed_path" : "tracking_path"
            trackingPolyline = polyline
            mapView.addOverlay(polyline)
            print("🗺️ [Coordinator] 更新轨迹线，\(coordinates.count) 个点，闭合: \(isClosed), 追踪中: \(isTracking)")

            // 如果路径已闭合，额外绘制半透明多边形填充
            if isClosed && convertedCoords.count >= 3 {
                let polygon = MKPolygon(coordinates: convertedCoords, count: convertedCoords.count)
                polygon.title = "closed_territory"
                closedPolygon = polygon
                mapView.addOverlay(polygon)
                print("🗺️ [Coordinator] 添加闭合多边形填充")
            }
        }

        // MARK: - 路径点标记更新

        private func updatePathPointAnnotations(on mapView: MKMapView, coordinates: [CLLocationCoordinate2D], isTracking: Bool) {
            // 如果停止追踪，清除所有标记
            if !isTracking {
                for annotation in pathPointAnnotations {
                    mapView.removeAnnotation(annotation)
                }
                pathPointAnnotations.removeAll()
                return
            }

            // 添加新的点（只添加新增的）
            let currentCount = pathPointAnnotations.count
            if coordinates.count > currentCount {
                for i in currentCount..<coordinates.count {
                    let annotation = MKPointAnnotation()
                    annotation.coordinate = coordinates[i]
                    annotation.title = i == 0 ? "起点" : "点\(i + 1)"
                    mapView.addAnnotation(annotation)
                    pathPointAnnotations.append(annotation)
                }
            }
        }

        // MARK: - POI 标注更新

        func updatePOIAnnotations(on mapView: MKMapView, pois: [POI], discoveredPOIs: Set<UUID>) {
            // 找出需要添加和删除的 POI
            let currentIds = Set(poiAnnotations.keys)
            let newIds = Set(pois.map { $0.id })

            // 删除不存在的
            let toRemove = currentIds.subtracting(newIds)
            for id in toRemove {
                if let annotation = poiAnnotations[id] {
                    mapView.removeAnnotation(annotation)
                    poiAnnotations.removeValue(forKey: id)
                }
            }

            // 添加新的
            let toAdd = newIds.subtracting(currentIds)
            for poi in pois where toAdd.contains(poi.id) {
                let annotation = POIAnnotation(poi: poi)
                poiAnnotations[poi.id] = annotation
                mapView.addAnnotation(annotation)
            }
        }

        // MARK: - 建筑标记更新

        func updateBuildings(on mapView: MKMapView, buildings: [PlayerBuilding], templates: [BuildingTemplate]) {
            // 创建模板字典方便查找
            let templateDict = Dictionary(uniqueKeysWithValues: templates.map { ($0.templateId, $0) })

            // 找出需要添加和删除的建筑
            let currentIds = Set(buildingAnnotations.keys)
            let newIds = Set(buildings.map { $0.id })

            // 删除不存在的
            let toRemove = currentIds.subtracting(newIds)
            for id in toRemove {
                if let annotation = buildingAnnotations[id] {
                    mapView.removeAnnotation(annotation)
                    buildingAnnotations.removeValue(forKey: id)
                }
            }

            // 添加或更新建筑
            for building in buildings {
                // 获取建筑坐标
                guard let location = building.location else { continue }

                // 数据库存储的已经是 GCJ-02 坐标，直接使用，不需要转换
                let gcj02Coord = CLLocationCoordinate2D(
                    latitude: location.coordinates[1],
                    longitude: location.coordinates[0]
                )

                // 获取建筑模板信息
                let template = templateDict[building.buildingTemplateKey]
                let icon = template?.icon ?? "building.2.fill"

                if let existingAnnotation = buildingAnnotations[building.id] {
                    // 更新现有标记的位置和状态
                    existingAnnotation.coordinate = gcj02Coord
                    existingAnnotation.status = building.status
                } else {
                    // 创建新标记
                    let annotation = BuildingMapAnnotation(
                        id: building.id,
                        coordinate: gcj02Coord,
                        name: building.buildingName,
                        icon: icon,
                        status: building.status
                    )
                    buildingAnnotations[building.id] = annotation
                    mapView.addAnnotation(annotation)
                    print("🏗️ [Coordinator] 添加建筑标记: \(building.buildingName) @ (\(gcj02Coord.latitude), \(gcj02Coord.longitude))")
                }
            }
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)

                // 判断是预览还是已确认的领地
                if circle === selectedOverlay {
                    // 预览样式（虚线、半透明）
                    renderer.strokeColor = UIColor.systemOrange
                    renderer.fillColor = UIColor.systemOrange.withAlphaComponent(0.2)
                    renderer.lineWidth = 3
                    renderer.lineDashPattern = [10, 5]
                } else if circle.title == "my_territory" {
                    // 我的领地：绿色
                    renderer.strokeColor = UIColor.systemGreen
                    renderer.fillColor = UIColor.systemGreen.withAlphaComponent(0.25)
                    renderer.lineWidth = 2
                } else if circle.title == "other_territory" {
                    // 他人领地：橙色
                    renderer.strokeColor = UIColor.systemOrange
                    renderer.fillColor = UIColor.systemOrange.withAlphaComponent(0.25)
                    renderer.lineWidth = 2
                } else {
                    // 默认领地样式
                    renderer.strokeColor = UIColor.systemGreen
                    renderer.fillColor = UIColor.systemGreen.withAlphaComponent(0.3)
                    renderer.lineWidth = 2
                }
                return renderer
            }

            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)

                // 根据轨迹类型设置颜色（参考原项目样式）
                if polyline.title == "closed_path" {
                    // 闭合轨迹：绿色，表示可以确认圈地
                    renderer.strokeColor = UIColor.systemGreen.withAlphaComponent(0.9)
                } else if polyline.title == "other_player" {
                    // 他人轨迹：红色
                    renderer.strokeColor = UIColor.systemRed.withAlphaComponent(0.85)
                    renderer.lineWidth = 4
                    renderer.lineCap = .round
                    renderer.lineJoin = .round
                    return renderer
                } else {
                    // 追踪中轨迹：青色
                    renderer.strokeColor = UIColor.systemCyan.withAlphaComponent(0.9)
                }

                renderer.lineWidth = 6
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }

            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)

                // 根据多边形类型设置样式
                if polygon.title == "closed_territory" || polygon === closedPolygon {
                    // 自己的闭合轨迹填充：绿色
                    renderer.strokeColor = UIColor.systemGreen
                    renderer.fillColor = UIColor.systemGreen.withAlphaComponent(0.25)
                    renderer.lineWidth = 2
                } else if polygon.title == "other_territory" || polygon.subtitle == "other_territory" {
                    // 他人领地：橙色
                    renderer.strokeColor = UIColor.systemOrange
                    renderer.fillColor = UIColor.systemOrange.withAlphaComponent(0.25)
                    renderer.lineWidth = 2
                } else if polygon.title == "my_territory" {
                    // 我的已确认领地：绿色
                    renderer.strokeColor = UIColor.systemGreen
                    renderer.fillColor = UIColor.systemGreen.withAlphaComponent(0.25)
                    renderer.lineWidth = 2
                } else {
                    // 默认多边形样式
                    renderer.strokeColor = UIColor.systemPurple
                    renderer.fillColor = UIColor.systemPurple.withAlphaComponent(0.2)
                    renderer.lineWidth = 2
                }
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }

        // MARK: - Annotation View

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // 跳过用户位置
            if annotation is MKUserLocation {
                return nil
            }

            // POI 标注
            if let poiAnnotation = annotation as? POIAnnotation {
                let identifier = "POIAnnotation"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView

                if annotationView == nil {
                    annotationView = MKMarkerAnnotationView(annotation: poiAnnotation, reuseIdentifier: identifier)
                    annotationView?.canShowCallout = true
                } else {
                    annotationView?.annotation = poiAnnotation
                }

                // 根据 POI 类型设置图标和颜色
                let poi = poiAnnotation.poi
                annotationView?.glyphImage = UIImage(systemName: poi.type.iconName)
                annotationView?.markerTintColor = UIColor(hex: poi.type.color)

                // 如果没有资源，显示为灰色
                if !poi.hasResources {
                    annotationView?.markerTintColor = UIColor.systemGray
                    annotationView?.alpha = 0.6
                } else {
                    annotationView?.alpha = 1.0
                }

                return annotationView
            }

            // 建筑标记
            if let buildingAnnotation = annotation as? BuildingMapAnnotation {
                let identifier = "BuildingMapAnnotation"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)

                if view == nil {
                    view = MKAnnotationView(annotation: buildingAnnotation, reuseIdentifier: identifier)
                    view?.canShowCallout = true
                } else {
                    view?.annotation = buildingAnnotation
                }

                // 创建建筑图标
                let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
                let color: UIColor = {
                    switch buildingAnnotation.status {
                    case .constructing: return .systemBlue
                    case .active: return .systemGreen
                    case .damaged: return .systemOrange
                    case .inactive: return .systemGray
                    }
                }()
                view?.image = UIImage(systemName: buildingAnnotation.icon, withConfiguration: config)?
                    .withTintColor(color, renderingMode: .alwaysOriginal)

                return view
            }

            // 路径点标记使用小圆点
            let identifier = "PathPoint"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)

            if annotationView == nil {
                annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = true

                // 创建圆点图片（更大更明显）
                let size: CGFloat = 16
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
                let image = renderer.image { context in
                    let rect = CGRect(x: 2, y: 2, width: size - 4, height: size - 4)
                    // 起点用绿色，其他点用橙色
                    if annotation.title == "起点" {
                        UIColor.systemGreen.setFill()
                    } else {
                        UIColor.systemOrange.setFill()
                    }
                    UIColor.white.setStroke()
                    context.cgContext.setLineWidth(2)
                    context.cgContext.fillEllipse(in: rect)
                    context.cgContext.strokeEllipse(in: rect)
                }
                annotationView?.image = image
                annotationView?.centerOffset = CGPoint(x: 0, y: 0)
            } else {
                annotationView?.annotation = annotation
            }

            return annotationView
        }
    }
}

// MARK: - 建筑地图标注

class BuildingMapAnnotation: NSObject, MKAnnotation {
    let id: UUID
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let name: String
    let icon: String
    var status: PlayerBuildingStatus

    init(id: UUID, coordinate: CLLocationCoordinate2D, name: String, icon: String, status: PlayerBuildingStatus) {
        self.id = id
        self.coordinate = coordinate
        self.name = name
        self.icon = icon
        self.status = status
        super.init()
    }

    var title: String? { name }

    var subtitle: String? {
        switch status {
        case .constructing: return "建造中..."
        case .active: return "运行中"
        case .damaged: return "需要维修"
        case .inactive: return "已停用"
        }
    }
}

// MARK: - UIColor 扩展

extension UIColor {
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}
