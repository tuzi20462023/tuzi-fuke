//
//  BuildingPlacementView.swift
//  tuzi-fuke
//
//  DAY8: 建筑放置界面 - 在地图上选择建造位置
//  Created by AI Assistant on 2025/12/02.
//

import SwiftUI
import MapKit
import CoreLocation

struct BuildingPlacementView: View {
    let template: BuildingTemplate
    let territoryId: UUID
    let territoryCenter: CLLocationCoordinate2D
    let territoryRadius: Double  // 米

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

    init(template: BuildingTemplate, territoryId: UUID, territoryCenter: CLLocationCoordinate2D, territoryRadius: Double) {
        self.template = template
        self.territoryId = territoryId
        self.territoryCenter = territoryCenter
        self.territoryRadius = territoryRadius

        // 初始化地图区域
        let span = MKCoordinateSpan(
            latitudeDelta: territoryRadius * 3 / 111000,
            longitudeDelta: territoryRadius * 3 / 111000
        )
        _region = State(initialValue: MKCoordinateRegion(center: territoryCenter, span: span))
    }

    var body: some View {
        NavigationView {
            ZStack {
                // 地图
                mapView

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

    // MARK: - 地图视图

    private var mapView: some View {
        Map(coordinateRegion: $region, interactionModes: .all, annotationItems: annotations) { item in
            MapAnnotation(coordinate: item.coordinate) {
                if item.isSelected {
                    // 选中的位置
                    VStack {
                        Image(systemName: template.icon)
                            .font(.system(size: 30))
                            .foregroundColor(isValidLocation ? .green : .red)
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 12))
                            .foregroundColor(isValidLocation ? .green : .red)
                    }
                } else {
                    // 领地中心
                    Circle()
                        .fill(.blue.opacity(0.3))
                        .frame(width: 20, height: 20)
                }
            }
        }
        .onTapGesture { location in
            // 将屏幕坐标转换为地图坐标 (简化处理)
            // 注意：这里使用领地中心附近的随机偏移作为示例
            let randomOffset = Double.random(in: -0.0005...0.0005)
            let tappedLocation = CLLocationCoordinate2D(
                latitude: region.center.latitude + randomOffset,
                longitude: region.center.longitude + randomOffset
            )
            selectLocation(tappedLocation)
        }
        .overlay(
            // 领地范围圆圈提示
            Circle()
                .stroke(.blue.opacity(0.5), lineWidth: 2)
                .frame(width: 100, height: 100)
                .allowsHitTesting(false)
        )
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
                    Text("点击地图选择建造位置")
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

    // MARK: - 标注数据

    private var annotations: [PlacementAnnotation] {
        var items: [PlacementAnnotation] = [
            PlacementAnnotation(id: "center", coordinate: territoryCenter, isSelected: false)
        ]

        if let selected = selectedLocation {
            items.append(PlacementAnnotation(id: "selected", coordinate: selected, isSelected: true))
        }

        return items
    }

    // MARK: - 逻辑

    private var canBuild: Bool {
        selectedLocation != nil && isValidLocation
    }

    private func selectLocation(_ coordinate: CLLocationCoordinate2D) {
        selectedLocation = coordinate

        // 验证位置是否在领地内
        let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: territoryCenter.latitude, longitude: territoryCenter.longitude))

        isValidLocation = distance <= territoryRadius
    }

    private func startBuilding() async {
        guard let location = selectedLocation else { return }

        isBuilding = true

        let request = BuildingConstructionRequest(
            templateId: template.templateId,
            territoryId: territoryId,
            location: location,
            customName: nil
        )

        let result = await buildingManager.startConstruction(request: request)

        isBuilding = false
        buildSuccess = result.success
        resultMessage = result.message
        showResult = true
    }
}

// MARK: - 标注模型

struct PlacementAnnotation: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let isSelected: Bool
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
        territoryId: UUID(),
        territoryCenter: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
        territoryRadius: 100
    )
}
