import XCTest
@testable import MonsterCalc_iPhone

@MainActor
final class ScratchpadViewModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "MonsterCalc_iPhoneTests.\(name)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let defaults, let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testResultsTextUsesDisplaysAndErrorsLineByLine() {
        let model = ScratchpadViewModel(defaults: defaults)
        model.sigFigures = 5
        model.resultFormat = .si
        model.text =
            """
            5
            missing_name
            abs(
            """

        XCTAssertEqual(model.results.count, 3)
        XCTAssertEqual(model.resultsText, "5\n\n")
        XCTAssertEqual(model.results[0].display, "5")
        XCTAssertEqual(model.results[1].display, "")
        XCTAssertEqual(model.results[1].error, nil)
        XCTAssertEqual(model.results[2].display, "")
        XCTAssertEqual(model.results[2].error, nil)
    }

    func testClearAndLoadDemoUpdateDocument() {
        let model = ScratchpadViewModel(defaults: defaults)
        model.sigFigures = 5
        model.resultFormat = .si

        model.clear()
        XCTAssertEqual(model.text, "")
        XCTAssertTrue(model.results.allSatisfy(\.isEmpty))

        model.loadDemo()
        XCTAssertEqual(model.text, DemoSheet.text)
        XCTAssertFalse(model.results.isEmpty)
    }

    func testDemoLoadsOnlyOnFirstLaunch() {
        let firstModel = ScratchpadViewModel(defaults: defaults)
        XCTAssertEqual(firstModel.text, DemoSheet.text)
        XCTAssertFalse(firstModel.results.isEmpty)

        let secondModel = ScratchpadViewModel(defaults: defaults)
        XCTAssertEqual(secondModel.text, "")
        XCTAssertTrue(secondModel.results.allSatisfy(\.isEmpty))

        secondModel.loadDemo()
        XCTAssertEqual(secondModel.text, DemoSheet.text)
        XCTAssertFalse(secondModel.results.isEmpty)
    }
}
