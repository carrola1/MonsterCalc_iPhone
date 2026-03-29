import UIKit
import XCTest
@testable import MonsterCalc_iPhone

final class ScratchpadEditorBehaviorTests: XCTestCase {
    func testAssignedVariableNamesReturnsEachDeclaredVariable() {
        let variableNames = assignedVariableNames(
            in: """
            alpha = 5
            beta = alpha + 1
            _temp = beta
            """
        )

        XCTAssertEqual(variableNames, ["alpha", "beta", "_temp"])
    }

    func testFormattedInsertedTokenAddsOneSpaceOnBothSidesOfOperator() {
        let textView = UITextView()
        textView.text = "1"
        textView.selectedRange = NSRange(location: 1, length: 0)

        let token = formattedInsertedToken("+", in: textView, operatorAutospaceEnabled: true)

        XCTAssertEqual(token, " + ")
    }

    func testFormattedInsertedTokenDoesNotDoubleLeadingSpace() {
        let textView = UITextView()
        textView.text = "1 "
        textView.selectedRange = NSRange(location: 2, length: 0)

        let token = formattedInsertedToken("+", in: textView, operatorAutospaceEnabled: true)

        XCTAssertEqual(token, "+ ")
    }

    func testFormattedInsertedTokenTreatsTrailingNewlineAsEndOfLine() {
        let textView = UITextView()
        textView.text = "1\n"
        textView.selectedRange = NSRange(location: 1, length: 0)

        let token = formattedInsertedToken("+", in: textView, operatorAutospaceEnabled: true)

        XCTAssertEqual(token, " + ")
    }

    func testFormattedInsertedTokenLeavesOperatorUntouchedWhenAutospaceDisabled() {
        let textView = UITextView()
        textView.text = "1"
        textView.selectedRange = NSRange(location: 1, length: 0)

        let token = formattedInsertedToken("+", in: textView, operatorAutospaceEnabled: false)

        XCTAssertEqual(token, "+")
    }

    func testUserDefinedVariableTokenReturnsAssignedVariableOnly() {
        let token = userDefinedVariableToken(
            in: """
            alpha = 5
            beta = alpha + 1
            """,
            at: 17
        )

        XCTAssertEqual(token, "alpha")
    }

    func testUserDefinedVariableTokenReturnsNilOutsideTokenCharacters() {
        let token = userDefinedVariableToken(
            in: """
            alpha = 5
            beta = alpha + 1
            """,
            at: 16
        )

        XCTAssertNil(token)
    }

    func testUserDefinedVariableTokenIgnoresBuiltInSymbolNames() {
        let token = userDefinedVariableToken(
            in: "alpha = 5\nans + alpha",
            at: 10
        )

        XCTAssertNil(token)
    }

    func testSteppedOverClosingParenCursorLocationAdvancesOverExistingParen() {
        let steppedCursorLocation = steppedOverClosingParenCursorLocation(
            text: "sqrt(x)",
            selectedRange: NSRange(location: 6, length: 0),
            replacementText: ")"
        )

        XCTAssertEqual(steppedCursorLocation, 7)
    }

    func testSteppedOverClosingParenCursorLocationDoesNothingWhenNextCharacterIsNotParen() {
        let steppedCursorLocation = steppedOverClosingParenCursorLocation(
            text: "sqrt(x)+1",
            selectedRange: NSRange(location: 7, length: 0),
            replacementText: ")"
        )

        XCTAssertNil(steppedCursorLocation)
    }

    func testAutoCloseFunctionCallIfNeededAddsClosingParenForFinalArgument() {
        let autoClosed = autoCloseFunctionCallIfNeeded(
            text: "sqrt(9",
            cursorLocation: 6,
            signatures: inlineFunctionSignatures,
            insertedToken: "9"
        )

        XCTAssertEqual(autoClosed?.text, "sqrt(9)")
        XCTAssertEqual(autoClosed?.cursorLocation, 6)
    }

    func testAutoCloseFunctionCallIfNeededSkipsWhenClosingParenAlreadyExists() {
        let autoClosed = autoCloseFunctionCallIfNeeded(
            text: "sqrt(9)",
            cursorLocation: 6,
            signatures: inlineFunctionSignatures,
            insertedToken: "9"
        )

        XCTAssertNil(autoClosed)
    }

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
