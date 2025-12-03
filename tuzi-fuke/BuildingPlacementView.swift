//
//  BuildingPlacementView.swift
//  tuzi-fuke
//
//  DAY8: 建筑放置界面 - 在地图上选择建造位置
//  Created by AI Assistant on 2025/12/02.
//  Updated: 修复领地边界显示问题，使用完整 Territory 对象
//

import SwiftUI
import MapKit
import CoreLocation

struct BuildingPlacementView: View {
    let template: BuildingTemplate
    let territory: Territory  // 完整的领地对象

    @StateObject private var buildingManager = BuildingManager.shared
    @State private var selectedLocation: CLLocationCoordinate2D?
    @State private var isValidLocation = false
    @State private var isBuilding = false
    @State private var showResult = false
    @State private var resultMessage = ""
    @State private var buildSuccess = false

    @Environment(\.dismiss) private var dismiss

    // 地图区域
    @State private var region: MKCoordinateRegion

    init(template: BuildingTemplate, territory: Territory) {
        self.template = template
        self.territory = territory

        // 初始化地图区域，居中到领地中心
        // 数据库存储的是 WGS-84 坐标，需要转换为 GCJ-02 用于地图显示
        let wgs84Center = territory.centerLocation.coordinate
        let gcj02Center = CoordinateConverter.convertIfNeeded(wgs84Center)

        let radius = max(territory.radius, 50)  // 至少50米
        let span = MKCoordinateSpan(
            latitudeDelta: radius * 4 / 111000,
            longitudeDelta: radius * 4 / 111000
        )
        _region = State(initialValue: MKCoordinateRegion(center: gcj02Center, span: span))
    }

    var body: some View {
        NavigationView {
            ZStack {
                // 地图（使用 UIKit 包装以支持多边形绘制和点击）
                TerritoryMapView(
                    territory: territory,
                    region: $region,
                    selectedLocation: $selectedLocation,
                    isValidLocation: $isValidLocation,
                    buildingIcon: template.icon
                )

                // 底部信息面板
                VStack {
                    Spacer()
                    bottomPanel
                }
            }
            .navigationTitle("选择建造位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .alert(buildSuccess ? "建造成功" : "建造失败", isPresented: $showResult) {
                Button("确定") {
                    if buildSuccess {
                        dismiss()
                    }
                }
            } message: {
                Text(resultMessage)
            }
        }
    }

    // MARK: - 底部面板

    private var bottomPanel: some View {
        VStack(spacing: 16) {
            // 建筑信息
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 50, height: 50)
                    Image(systemName: template.icon)
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.headline)
                    Text("建造时间: \(template.formattedBuildTime)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // 位置状态
            if let location = selectedLocation {
                HStack {
                    Image(systemName: isValidLocation ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isValidLocation ? .green : .red)
                    Text(isValidLocation ? "位置有效" : "位置无效（需在领地内）")
                        .font(.subheadline)
                        .foregroundColor(isValidLocation ? .green : .red)
                    Spacer()
                    Text(String(format: "%.4f, %.4f", location.latitude, location.longitude))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack {
                    Image(systemName: "hand.tap")
                        .foregroundColor(.orange)
                    Text("点击绿色区域选择建造位置")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }

            // 建造按钮
            Button {
                Task {
                    await startBuilding()
                }
            } label: {
                HStack {
                    if isBuilding {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "hammer.fill")
                    }
                    Text(isBuilding ? "建造中..." : "确认建造")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canBuild ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!canBuild || isBuilding)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(radius: 10)
        )
        .padding()
    }

    // MARK: - 逻辑

    private var canBuild: Bool {
        selectedLocation != nil && isValidLocation
    }

    private func startBuilding() async {
        guard let gcj02Location = selectedLocation else { return }

        isBuilding = true

        // 直接保存 GCJ-02 坐标到数据库（与原项目保持一致）
        // 这样显示时不需要再转换，避免坐标偏移问题
        let request = BuildingConstructionRequest(
            templateId: template.templateId,
            territoryId: territory.id,
            location: gcj02Location,  // 直接保存 GCJ-02 坐标
            customName: nil
        )

        let result = await buildingManager.startConstruction(request: request)

        isBuilding = false
        buildSuccess = result.success
        resultMessage = result.message
        showResult = true
    }
}

// MARK: - 领地地图视图 (UIKit 包装)

struct TerritoryMapView: UIViewRepresentable {
    let territory: Territory
    @Binding var region: MKCoordinateRegion
    @Binding var selectedLocation: CLLocationCoordinate2D?
    @Binding var isValidLocation: Bool
    let buildingIcon: String

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.setRegion(region, animated: false)
        mapView.showsUserLocation = true
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.isRotateEnabled = false

        // 添加领地多边形
        addTerritoryPolygon(to: mapView)

        // 添加点击手势
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(context.coordinator.handleMapTap(_:))
        )
        mapView.addGestureRecognizer(tapGesture)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // 更新选中位置标注
        // 移除旧的标注
        let oldAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(oldAnnotations)

        // 添加选中位置标注
        if let selected = selectedLocation {
            let annotation = BuildingAnnotation(coordinate: selected, icon: buildingIcon, isValid: isValidLocation)
            mapView.addAnnotation(annotation)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - 添加领地多边形

    private func addTerritoryPolygon(to mapView: MKMapView) {
        // 获取领地边界坐标
        let coordinates: [CLLocationCoordinate2D]

        if territory.isPolygon, let path = territory.path, !path.isEmpty {
            // 多边形领地（行走圈地）
            // 领地 path 存储的是 WGS-84 坐标，需要转换为 GCJ-02 用于地图显示
            coordinates = path.compactMap { point in
                guard let lat = point["lat"], let lon = point["lon"] else { return nil }
                let wgs84 = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                return CoordinateConverter.convertIfNeeded(wgs84)
            }
            print("📍 [BuildingPlacement] 多边形领地，转换 \(path.count) 个点")
        } else {
            // 圆形领地，生成圆形近似多边形
            // center 也需要转换
            let wgs84Center = territory.centerLocation.coordinate
            let gcj02Center = CoordinateConverter.convertIfNeeded(wgs84Center)
            let radius = territory.radius
            coordinates = generateCircleCoordinates(center: gcj02Center, radius: radius, points: 36)
            print("📍 [BuildingPlacement] 圆形领地，中心: \(gcj02Center), 半径: \(radius)m")
        }

        guard coordinates.count >= 3 else {
            print("⚠️ [BuildingPlacement] 领地坐标点不足: \(coordinates.count)")
            return
        }

        print("✅ [BuildingPlacement] 绘制领地边界，点数: \(coordinates.count)")

        let polygon = MKPolygon(coordinates: coordinates, count: coordinates.count)
        polygon.title = "territory"
        mapView.addOverlay(polygon)
    }

    /// 生成圆形近似多边形坐标
    private func generateCircleCoordinates(center: CLLocationCoordinate2D, radius: Double, points: Int) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        let earthRadius = 6371000.0 // 地球半径（米）

        for i in 0..<points {
            let angle = (Double(i) / Double(points)) * 2 * .pi
            let latOffset = (radius / earthRadius) * cos(angle) * (180 / .pi)
            let lonOffset = (radius / earthRadius) * sin(angle) * (180 / .pi) / cos(center.latitude * .pi / 180)

            coordinates.append(CLLocationCoordinate2D(
                latitude: center.latitude + latOffset,
                longitude: center.longitude + lonOffset
            ))
        }

        return coordinates
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: TerritoryMapView

        init(_ parent: TerritoryMapView) {
            self.parent = parent
        }

        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }

            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)

            print("🗺️ [地图点击] 坐标: (\(coordinate.latitude), \(coordinate.longitude))")

            // 更新选中位置
            parent.selectedLocation = coordinate

            // 验证位置是否在领地内（直接使用地图坐标，不做转换）
            // 因为领地边界和点击坐标都来自同一个 MapKit 坐标系
            parent.isValidLocation = isLocationInTerritory(coordinate)

            print("📍 [位置验证] 在领地内: \(parent.isValidLocation)")
        }

        /// 判断位置是否在领地内
        /// coordinate 是地图上点击的 GCJ-02 坐标
        private func isLocationInTerritory(_ coordinate: CLLocationCoordinate2D) -> Bool {
            let territory = parent.territory

            if territory.isPolygon, let path = territory.path, path.count >= 3 {
                // 多边形领地：使用射线法判断
                // path 存储的是 WGS-84，需要转换为 GCJ-02 来与点击坐标比较
                let locations = path.compactMap { point -> CLLocation? in
                    guard let lat = point["lat"], let lon = point["lon"] else { return nil }
                    let wgs84 = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    let gcj02 = CoordinateConverter.convertIfNeeded(wgs84)
                    return CLLocation(latitude: gcj02.latitude, longitude: gcj02.longitude)
                }
                let testLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                return isPointInPolygon(point: testLocation, path: locations)
            } else {
                // 圆形领地：用距离判断
                // center 也需要转换为 GCJ-02
                let wgs84Center = territory.centerLocation.coordinate
                let gcj02Center = CoordinateConverter.convertIfNeeded(wgs84Center)
                let centerLocation = CLLocation(latitude: gcj02Center.latitude, longitude: gcj02Center.longitude)
                let testLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                let distance = testLocation.distance(from: centerLocation)
                return distance <= territory.radius
            }
        }

        /// 射线法判断点是否在多边形内
        private func isPointInPolygon(point: CLLocation, path: [CLLocation]) -> Bool {
            guard path.count >= 3 else { return false }

            let x = point.coordinate.longitude
            let y = point.coordinate.latitude
            var inside = false

            var j = path.count - 1
            for i in 0..<path.count {
                let xi = path[i].coordinate.longitude
                let yi = path[i].coordinate.latitude
                let xj = path[j].coordinate.longitude
                let yj = path[j].coordinate.latitude

                let intersect = ((yi > y) != (yj > y)) &&
                               (x < (xj - xi) * (y - yi) / (yj - yi) + xi)

                if intersect {
                    inside.toggle()
                }

                j = i
            }

            return inside
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor = UIColor.systemGreen.withAlphaComponent(0.25)
                renderer.strokeColor = UIColor.systemGreen
                renderer.lineWidth = 3.0
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            if let buildingAnnotation = annotation as? BuildingAnnotation {
                let identifier = "BuildingAnnotation"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)

                if view == nil {
                    view = MKAnnotationView(annotation: buildingAnnotation, reuseIdentifier: identifier)
                    view?.canShowCallout = false
                } else {
                    view?.annotation = buildingAnnotation
                }

                // 创建自定义图标
                let config = UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)
                let color = buildingAnnotation.isValid ? UIColor.systemGreen : UIColor.systemRed
                view?.image = UIImage(systemName: buildingAnnotation.icon, withConfiguration: config)?
                    .withTintColor(color, renderingMode: .alwaysOriginal)

                return view
            }

            return nil
        }
    }
}

// MARK: - 建筑标注

class BuildingAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let icon: String
    let isValid: Bool

    init(coordinate: CLLocationCoordinate2D, icon: String, isValid: Bool) {
        self.coordinate = coordinate
        self.icon = icon
        self.isValid = isValid
        super.init()
    }
}

// MARK: - Preview

#Preview {
    BuildingPlacementView(
        template: BuildingTemplate(
            id: UUID(),
            templateId: "shelter_basic",
            name: "基础庇护所",
            tier: 1,
            category: .survival,
            description: "提供基本的遮风挡雨功能",
            icon: "house.fill",
            requiredLevel: 1,
            requiredResources: ["wood": 10, "stone": 5],
            buildTimeHours: 0.5,
            effects: [:],
            maxPerTerritory: 1,
            maxLevel: 3,
            durabilityMax: 100,
            isActive: true,
            createdAt: Date()
        ),
        territory: Territory(
            id: UUID(),
            ownerId: UUID(),
            name: "测试领地",
            type: .circle,
            centerLatitude: 23.2005,
            centerLongitude: 114.4513,
            radius: 100
        )
    )
}
