import CoreLocation

/// 坐标转换器 - 处理 GCJ-02（国测局坐标）与 WGS-84（标准GPS）之间的转换
/// 中国大陆地区使用 GCJ-02 坐标系，需要进行偏移校正
struct CoordinateConverter {

    // MARK: - 常量
    private static let a = 6378245.0  // 长半轴
    private static let ee = 0.00669342162296594323  // 偏心率平方

    // MARK: - 公开方法

    /// 根据需要转换坐标（如果在中国大陆范围内则转换）
    /// - Parameter coordinate: 原始 WGS-84 坐标
    /// - Returns: 转换后的坐标（中国大陆返回 GCJ-02，其他地区返回原坐标）
    static func convertIfNeeded(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        if isInChina(coordinate) {
            return wgs84ToGcj02(coordinate)
        }
        return coordinate
    }

    /// WGS-84 转 GCJ-02
    /// - Parameter wgs: WGS-84 坐标
    /// - Returns: GCJ-02 坐标
    static func wgs84ToGcj02(_ wgs: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        if isOutOfChina(wgs) {
            return wgs
        }

        var dLat = transformLat(wgs.longitude - 105.0, wgs.latitude - 35.0)
        var dLon = transformLon(wgs.longitude - 105.0, wgs.latitude - 35.0)

        let radLat = wgs.latitude / 180.0 * .pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)

        dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
        dLon = (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * .pi)

        return CLLocationCoordinate2D(
            latitude: wgs.latitude + dLat,
            longitude: wgs.longitude + dLon
        )
    }

    /// GCJ-02 转 WGS-84（逆向转换，精度略低）
    /// - Parameter gcj: GCJ-02 坐标
    /// - Returns: WGS-84 坐标
    static func gcj02ToWgs84(_ gcj: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        if isOutOfChina(gcj) {
            return gcj
        }

        let converted = wgs84ToGcj02(gcj)
        return CLLocationCoordinate2D(
            latitude: gcj.latitude * 2 - converted.latitude,
            longitude: gcj.longitude * 2 - converted.longitude
        )
    }

    // MARK: - 私有方法

    /// 判断坐标是否在中国范围内
    private static func isInChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        return !isOutOfChina(coordinate)
    }

    /// 判断坐标是否在中国范围外
    private static func isOutOfChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        if coordinate.longitude < 72.004 || coordinate.longitude > 137.8347 {
            return true
        }
        if coordinate.latitude < 0.8293 || coordinate.latitude > 55.8271 {
            return true
        }
        return false
    }

    /// 纬度转换
    private static func transformLat(_ x: Double, _ y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * .pi) + 320 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    /// 经度转换
    private static func transformLon(_ x: Double, _ y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return ret
    }
}
