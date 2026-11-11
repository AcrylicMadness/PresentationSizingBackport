import Foundation

/// Kept independent of UIKit so bounds behavior can be unit tested.
enum SheetGeometry {
    static func height(content: CGFloat, bottomInset: CGFloat, available: CGFloat) -> CGFloat {
        guard available.isFinite, available > 0 else { return 1 }
        let content = content.isFinite ? max(1, content) : 1
        let inset = bottomInset.isFinite ? max(0, bottomInset) : 0
        return min(available, content + inset)
    }
}
