//
//  WeatherService.swift
//  tuzi-fuke (地球新主复刻版)
//
//  天气服务 - 使用默认天气
//  Created by AI Assistant on 2025/12/05.
//

import Foundation
import SwiftUI
import Combine
import CoreLocation

// MARK: - 天气服务

@MainActor
class WeatherService: ObservableObject {
    static let shared = WeatherService()

    @Published var currentWeather: WeatherInfo?
    @Published var isLoading = false
    @Published var error: String?

    private init() {}

    // MARK: - 获取天气

    /// 获取指定位置的天气信息（直接返回默认天气）
    func fetchWeather(for location: CLLocation) async -> WeatherInfo? {
        isLoading = true
        error = nil

        // 直接返回默认天气
        let info = createDefaultWeather()
        self.currentWeather = info
        self.isLoading = false

        print("✅ [WeatherService] 使用默认天气: \(info.aiDescription)")
        return info
    }

    /// 获取指定坐标的天气信息
    func fetchWeather(latitude: Double, longitude: Double) async -> WeatherInfo? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        return await fetchWeather(for: location)
    }

    // MARK: - 默认天气

    private func createDefaultWeather() -> WeatherInfo {
        // 根据时间段返回不同的默认天气
        let timeOfDay = TimeOfDay.current()

        switch timeOfDay {
        case .dawn, .dusk:
            return WeatherInfo(
                condition: .cloudy,
                temperature: 18.0,
                humidity: 65.0,
                windSpeed: 5.0,
                description: "阴云密布"
            )
        case .morning, .afternoon:
            return WeatherInfo(
                condition: .cloudy,
                temperature: 22.0,
                humidity: 55.0,
                windSpeed: 3.0,
                description: "多云"
            )
        case .noon:
            return WeatherInfo(
                condition: .clear,
                temperature: 28.0,
                humidity: 45.0,
                windSpeed: 2.0,
                description: "晴朗"
            )
        case .night:
            return WeatherInfo(
                condition: .clear,
                temperature: 15.0,
                humidity: 70.0,
                windSpeed: 4.0,
                description: "夜空清朗"
            )
        }
    }
}

// MARK: - 预览支持

extension WeatherService {
    /// 创建预览用的天气信息
    static func previewWeather() -> WeatherInfo {
        return WeatherInfo(
            condition: .cloudy,
            temperature: 20.0,
            humidity: 60.0,
            windSpeed: 5.0,
            description: "阴天"
        )
    }
}
