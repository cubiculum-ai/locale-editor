import XCTest
@testable import LocaleEditorTUI

final class MenuTests: XCTestCase {
    private func menus(field: Bool = true, undo: Bool = true, redo: Bool = true) -> [AppMenu] {
        EditorMenus.make(MenuAvailability(fieldSelected: field, canUndo: undo, canRedo: redo, canPreview: true, canCompile: true))
    }

    func testMnemonicsAreVisibleAndUniqueWithinEachMenu() {
        let list = menus()
        XCTAssertEqual(list.map { $0.label.mnemonic }, ["l", "f", "e", "o", "h"])
        for menu in list {
            let letters = menu.items.compactMap { $0.label.mnemonic }
            XCTAssertEqual(Set(letters).count, letters.count, menu.label.text)
            for item in menu.items where !item.isSeparator {
                XCTAssertFalse(item.label.text.contains("&"))
                XCTAssertNotNil(item.command)
                XCTAssertNotNil(item.label.mnemonic)
            }
        }
        let label = MenuLabel("Save project &as…")
        XCTAssertEqual(label.text, "Save project as…")
        XCTAssertEqual(label.mnemonicColumn, 13)
    }

    func testNavigationSkipsSeparatorsAndWraps() {
        var selection = MenuSelection(menus: menus(), heading: 1)
        XCTAssertEqual(selection.command, .open)
        selection.moveItem(-1)
        XCTAssertEqual(selection.command, .quit)
        selection.moveItem(1)
        XCTAssertEqual(selection.command, .open)
        selection.selectItem(2)
        selection.moveItem(1)
        XCTAssertEqual(selection.command, .viewSource)
        selection.edge(first: false)
        XCTAssertEqual(selection.command, .quit)
        selection.moveHeading(-2)
        XCTAssertEqual(selection.heading, 4)
        selection.moveHeading(1)
        XCTAssertEqual(selection.heading, 0)
    }

    func testUnavailableEditActionsCannotBeSelected() {
        var selection = MenuSelection(menus: menus(field: false, undo: false, redo: false), heading: 2)
        XCTAssertNil(selection.item)
        XCTAssertNil(selection.command)
        selection.moveItem(1); selection.edge(first: false); selection.selectItem(0)
        XCTAssertNil(selection.command)
        let partial = menus(field: false, undo: true, redo: false)
        selection = MenuSelection(menus: partial, heading: 2)
        XCTAssertEqual(selection.command, .undo)
        selection.moveItem(1)
        XCTAssertEqual(selection.command, .undo)
    }

    func testMenusExposeRealCommandsAndRespectRuntimeAvailability() {
        let list = EditorMenus.make(MenuAvailability(fieldSelected: true, canUndo: true, canRedo: true, canPreview: false, canCompile: false))
        let items = list.flatMap(\.items)
        XCTAssertEqual(items.first { $0.command == .save }?.shortcut, "F2")
        XCTAssertTrue(items.contains { $0.command == .saveAs && $0.enabled })
        XCTAssertFalse(items.first { $0.command == .preview }!.enabled)
        XCTAssertFalse(items.first { $0.command == .compile }!.enabled)
        XCTAssertTrue(items.contains { $0.command == .cursorOptions && $0.enabled })
    }

    func testRenderedHeadingAndItemTargetsMatchTheirCellsAndMaskPanels() {
        var screen = Screen(width: 120, height: 32)
        screen.clickTarget(.section(2), x: 1, y: 5, width: 22)
        var selection = MenuSelection(menus: menus(), heading: 1)
        let bounds = screen.dropdown(&selection)
        XCTAssertEqual(screen.click(at: MouseEvent(x: 10, y: 0, kind: .press(0))), .menuHeading(1))
        XCTAssertEqual(screen.click(at: MouseEvent(x: bounds.x + 2, y: 3, kind: .press(0))), .menuItem(1))
        XCTAssertNil(screen.click(at: MouseEvent(x: 2, y: 5, kind: .press(0))))
        XCTAssertNil(screen.click(at: MouseEvent(x: bounds.x, y: 3, kind: .press(0))))
        XCTAssertEqual(screen.scroll(at: MouseEvent(x: bounds.x + 2, y: 4, kind: .wheel(1))), .menu)
    }

    func testMenusClampAndScrollWhenResized() {
        var screen = Screen(width: 28, height: 8)
        var selection = MenuSelection(menus: menus(), heading: 1)
        selection.edge(first: false)
        let bounds = screen.dropdown(&selection)
        XCTAssertGreaterThanOrEqual(bounds.x, 0)
        XCTAssertLessThanOrEqual(bounds.x + bounds.width, screen.width)
        XCTAssertLessThan(bounds.y + bounds.height, screen.height)
        XCTAssertGreaterThan(selection.offset, 0)
        XCTAssertEqual(selection.command, .quit)
    }
}
