import UIKit

/// Pure geometry for the bottom swipe zones. Percentages follow the reference
/// package: widths are fractions of the screen width, heights fractions of the
/// screen height. Nothing private is touched here, so the whole type can be
/// exercised offline by the Swift harness.
struct BottomSwipeGeometry {
    enum Zone: Equatable {
        case outside
        case left
        case right
    }

    enum Tier: Equatable {
        case insufficient
        case base
        case plus
        case plusPlus
    }

    let size: CGSize
    let startBand: CGFloat
    let leftWidthPercent: Double
    let rightWidthPercent: Double
    let basePercent: Double
    let plusPercent: Double
    let plusPlusPercent: Double
    let maxPercent: Double

    /// Reference defaults: 30/30 width, 7/18/40/60 height.
    static func current(size: CGSize, safeBottom: CGFloat) -> BottomSwipeGeometry {
        BottomSwipeGeometry(
            size: size,
            startBand: max(12, safeBottom),
            leftWidthPercent: 30,
            rightWidthPercent: 30,
            basePercent: 7,
            plusPercent: 18,
            plusPlusPercent: 40,
            maxPercent: 60
        )
    }

    /// Only the bottom strip is a valid origin; the middle band stays untouched
    /// so the system keeps its own Home gesture there.
    func zone(for point: CGPoint) -> Zone {
        guard size.width > 0, size.height > 0 else { return .outside }
        guard point.y >= size.height - startBand else { return .outside }
        if point.x <= size.width * CGFloat(leftWidthPercent) / 100 { return .left }
        if point.x >= size.width * (1 - CGFloat(rightWidthPercent) / 100) { return .right }
        return .outside
    }

    /// `upward` is a positive distance travelled towards the top of the screen.
    func tier(forUpward upward: CGFloat) -> Tier {
        guard size.height > 0, upward > 0 else { return .insufficient }
        let percent = Double(upward / size.height) * 100
        if percent >= maxPercent { return .plusPlus }
        if percent >= plusPlusPercent { return .plusPlus }
        if percent >= plusPercent { return .plus }
        if percent >= basePercent { return .base }
        return .insufficient
    }
}
