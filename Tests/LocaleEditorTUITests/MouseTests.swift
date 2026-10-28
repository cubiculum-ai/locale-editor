import XCTest
@testable import LocaleEditorTUI
#if os(Linux)
import Glibc
#else
import Darwin
#endif

final class MouseTests: XCTestCase {
    func testSGRUsesOneBasedWireCoordinatesAndDistinguishesRelease() throws {
        let press = try XCTUnwrap(MouseEvent.sgr("<0;1000;300M"))
        XCTAssertEqual(press, MouseEvent(x: 999, y: 299, kind: .press(0)))
        XCTAssertEqual(MouseEvent.sgr("<0;1000;300m")?.kind, .release)
        XCTAssertEqual(MouseEvent.sgr("<64;1;1M")?.kind, .wheel(-1))
        XCTAssertEqual(MouseEvent.sgr("<65;1;1M")?.kind, .wheel(1))
    }
    func testInvalidMotionAndHorizontalWheelReportsAreIgnored() {
        for report in ["<0;0;1M", "<0;-1;2M", "<0;1M", "<0;x;1M", "<0;1;2Q", "<32;1;1M", "<66;1;1M", "<128;1;1M", "<0;999999999999999999999;1M"] {
            XCTAssertNil(MouseEvent.sgr(report), report)
        }
    }
    func testLegacyReportsAndModifiersDoNotChangeCoordinates() {
        XCTAssertEqual(MouseEvent.legacy([32, 42, 52]), MouseEvent(x: 9, y: 19, kind: .press(0)))
        XCTAssertEqual(MouseEvent.legacy([35, 42, 52])?.kind, .release)
        XCTAssertEqual(MouseEvent.legacy([96, 42, 52])?.kind, .wheel(-1))
        XCTAssertEqual(MouseEvent.sgr("<20;10;20M"), MouseEvent(x: 9, y: 19, kind: .press(0)))
        XCTAssertNil(MouseEvent.legacy([32, 0, 1]))
    }
    func testFunctionBarBoundaryPixelsUseRenderedCellRanges() {
        var screen = Screen(width: 120, height: 32)
        screen.functionBar(["Help", "Save", "Source", "Edit", "Preview", "Inherit", "Search", "Reset", "Options", "Quit"])
        for index in 0..<10 {
            let first = index * screen.width / 10, last = (index + 1) * screen.width / 10 - 1
            for x in [first, last] {
                XCTAssertEqual(screen.click(at: MouseEvent(x: x, y: 31, kind: .press(0))), .function(index + 1))
            }
        }
        XCTAssertNil(screen.click(at: MouseEvent(x: 119, y: 31, kind: .press(0))))
        XCTAssertNil(screen.click(at: MouseEvent(x: 11, y: 31, kind: .release)))
        XCTAssertNil(screen.click(at: MouseEvent(x: 11, y: 31, kind: .press(2))))
    }
    func testModalTargetsReplaceRatherThanLeakThroughBackground() {
        var screen = Screen(width: 120, height: 32)
        screen.clickTarget(.section(2), x: 1, y: 5, width: 22)
        screen.scrollTarget(.sections, x: 1, y: 3, width: 22, height: 12)
        screen.clearTargets()
        screen.clickTarget(.choice(4), x: 5, y: 7, width: 40)
        XCTAssertNil(screen.click(at: MouseEvent(x: 2, y: 5, kind: .press(0))))
        XCTAssertNil(screen.scroll(at: MouseEvent(x: 2, y: 5, kind: .wheel(1))))
        XCTAssertEqual(screen.click(at: MouseEvent(x: 6, y: 7, kind: .press(0))), .choice(4))
    }
    func testHitRegionsAreExclusiveAtTheirRightAndBottomEdges() {
        let rect = CellRect(x: 2, y: 3, width: 10, height: 2)
        XCTAssertTrue(rect.contains(x: 11, y: 4))
        XCTAssertFalse(rect.contains(x: 12, y: 4))
        XCTAssertFalse(rect.contains(x: 11, y: 5))
    }
    func testTextClicksRespectWideAndCombiningCharactersAndScrollOffset() {
        #if os(Linux)
        _ = setlocale(LC_CTYPE, "C.UTF-8")
        #else
        _ = setlocale(LC_CTYPE, "UTF-8")
        #endif
        let chars = Array("A界e\u{301}B")
        XCTAssertEqual(Screen.cursorIndex(in: chars, offset: 0, column: 0), 0)
        XCTAssertEqual(Screen.cursorIndex(in: chars, offset: 0, column: 2), 1)
        XCTAssertEqual(Screen.cursorIndex(in: chars, offset: 0, column: 3), 2)
        XCTAssertEqual(Screen.cursorIndex(in: chars, offset: 2, column: 1), 3)
        XCTAssertEqual(Screen.cursorIndex(in: chars, offset: 2, column: 100), 4)
    }
}
