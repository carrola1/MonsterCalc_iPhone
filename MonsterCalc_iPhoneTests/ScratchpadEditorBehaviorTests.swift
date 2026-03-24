import XCTest
@testable import MonsterCalc_iPhone

final class ScratchpadEditorBehaviorTests: XCTestCase {
    func testEnsuredTrailingEditableLineAppendsBlankLineWithoutMovingCaret() {
        let normalized = ensuredTrailingEditableLine(text: "abc", cursorLocation: 3)

        XCTAssertEqual(normalized.text, "abc\n")
        XCTAssertEqual(normalized.cursorLocation, 3)
    }

    func testEnsuredTrailingEditableLineLeavesExistingBlankLineAlone() {
        let normalized = ensuredTrailingEditableLine(text: "abc\n", cursorLocation: 2)

        XCTAssertEqual(normalized.text, "abc\n")
        XCTAssertEqual(normalized.cursorLocation, 2)
    }

    func testEnsuredTrailingEditableLineCollapsesNewlineOnlyDocumentToEmpty() {
        let normalized = ensuredTrailingEditableLine(text: "\n", cursorLocation: 1)

        XCTAssertEqual(normalized.text, "")
        XCTAssertEqual(normalized.cursorLocation, 0)
    }
}
