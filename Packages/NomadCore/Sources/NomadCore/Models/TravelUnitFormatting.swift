import Foundation

public enum TravelUnitFormatting {
    /// 8-point compass label for a meteorological bearing in degrees (any real value is normalized to 0..<360).
    public static func compassDirection(_ degrees: Double) -> String {
        let normalized = degrees.truncatingRemainder(dividingBy: 360)
        let positive = normalized >= 0 ? normalized : normalized + 360
        let index = Int((positive + 22.5) / 45.0) % 8
        return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][index]
    }

    /// Distance label with one decimal below 10 km and whole kilometers from 10 km up.
    public static func kilometers(_ value: Double) -> String {
        String(format: value >= 10 ? "%.0f km" : "%.1f km", value)
    }
}
