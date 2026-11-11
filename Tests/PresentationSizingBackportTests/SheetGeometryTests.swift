import XCTest
@testable import PresentationSizingBackport

final class SheetGeometryTests: XCTestCase {
    func testFitsContentAndSafeArea() {
        XCTAssertEqual(SheetGeometry.height(content: 200, bottomInset: 34, available: 800), 234)
    }

    func testCapsOverflow() {
        XCTAssertEqual(SheetGeometry.height(content: 1200, bottomInset: 34, available: 600), 600)
    }

    func testInvalidMeasurementsRemainFiniteAndPositive() {
        XCTAssertEqual(SheetGeometry.height(content: .nan, bottomInset: .infinity, available: 600), 1)
        XCTAssertEqual(SheetGeometry.height(content: 200, bottomInset: 34, available: -20), 1)
    }
}
