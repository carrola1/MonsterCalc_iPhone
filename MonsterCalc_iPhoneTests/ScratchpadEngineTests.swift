import XCTest
@testable import MonsterCalc_iPhone

final class ScratchpadEngineTests: XCTestCase {
    private let engine = ScratchpadEngine()

    private func parseDividerPair(_ display: String) -> (Double, Double)? {
        guard display.first == "[", display.last == "]" else {
            return nil
        }

        let body = display.dropFirst().dropLast()
        let parts = body.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        guard parts.count == 2,
              let r1 = Double(parts[0]),
              let r2 = Double(parts[1])
        else {
            return nil
        }

        return (r1, r2)
    }

    func testAssignmentsAnsAndLineReferencesEvaluateInOrder() {
        let results = engine.evaluateDocument(
            """
            x = 2*pi
            y = x + 1
            ans + line1
            """
        )

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].assignmentName, "x")
        XCTAssertEqual(results[1].assignmentName, "y")
        XCTAssertEqual(results[2].assignmentName, nil)

        XCTAssertEqual(results[0].value?.numberValue ?? 0, 2 * .pi, accuracy: 0.000001)
        XCTAssertEqual(results[1].value?.numberValue ?? 0, (2 * .pi) + 1, accuracy: 0.000001)
        XCTAssertEqual(results[2].value?.numberValue ?? 0, ((2 * .pi) + 1) + (2 * .pi), accuracy: 0.000001)
    }

    func testCommentsAndBlankLinesStayBlank() {
        let results = engine.evaluateDocument(
            """
            # comment

            10k # inline comment
            """
        )

        XCTAssertEqual(results.count, 3)
        XCTAssertTrue(results[0].isEmpty)
        XCTAssertTrue(results[1].isEmpty)
        XCTAssertNil(results[2].error)
        XCTAssertEqual(results[2].value?.numberValue ?? 0, 10_000, accuracy: 0.000001)
    }

    func testIncompleteInputSuppressesLiveErrors() {
        let results = engine.evaluateDocument(
            """
            abs(
            x =
            findrdiv(
            vdiv(5, r)
            70 F
            70 F to
            """
        )

        XCTAssertEqual(results.count, 6)
        for result in results {
            XCTAssertEqual(result.display, "")
            XCTAssertNil(result.error)
            XCTAssertNil(result.value)
        }
    }

    func testInvalidOrUnknownLinesStayBlank() {
        let results = engine.evaluateDocument(
            """
            missing_name
            5 + )
            70 F to
            bitget(0xFF,)
            """
        )

        XCTAssertEqual(results.count, 4)
        for result in results {
            XCTAssertEqual(result.display, "")
            XCTAssertNil(result.error)
            XCTAssertNil(result.value)
        }
    }

    func testMathHelpersAndProbabilityFunctions() {
        let results = engine.evaluateDocument(
            """
            sqrt(81)
            deg(pi)
            cdf(0)
            pdf(0)
            """
        )

        XCTAssertEqual(results[0].value?.numberValue ?? 0, 9, accuracy: 0.000001)
        XCTAssertEqual(results[1].value?.numberValue ?? 0, 180, accuracy: 0.000001)
        XCTAssertEqual(results[2].value?.numberValue ?? 0, 0.5, accuracy: 0.000001)
        XCTAssertEqual(results[3].value?.numberValue ?? 0, 0.3989422804, accuracy: 0.000001)
    }

    func testProgrammingHelpers() {
        let results = engine.evaluateDocument(
            """
            hex(255)
            bin(5, 4)
            bitget(0x81, 7, 7)
            bitpunch(1, 7, 1)
            a2h("Az")
            a2h(Az)
            h2a("0x417a")
            """
        )

        XCTAssertEqual(results[0].display, "0xff")
        XCTAssertEqual(results[1].display, "0b0101")
        XCTAssertEqual(results[2].display, "0b1")
        XCTAssertEqual(results[3].value?.numberValue ?? 0, 129, accuracy: 0.000001)
        XCTAssertEqual(results[4].display, "0x417a")
        XCTAssertEqual(results[5].display, "0x417a")
        XCTAssertEqual(results[6].display, "Az")
    }

    func testEEHelpers() throws {
        let results = engine.evaluateDocument(
            """
            vdiv(5, 10k, 10k)
            rpar(100, 100)
            findres(5030)
            findrdiv(5, 2.5)
            findv(0.002, 4.7k)
            findi(5, 10k)
            findr(5, 0.002)
            xc(1k, 0.1u)
            xl(1k, 10m)
            db(2, 1)
            db10(10, 1)
            fc_rc(10k, 0.1u)
            tau(10k, 0.1u)
            rc_charge(5, 1m, 1k, 1u)
            rc_discharge(5, 1m, 1k, 1u)
            ledr(5, 2, 20m)
            adc(1.65, 3.3, 10)
            dac(512, 3.3, 10)
            """
        )

        XCTAssertEqual(results[0].value?.numberValue ?? 0, 2.5, accuracy: 0.000001)
        XCTAssertEqual(results[1].value?.numberValue ?? 0, 50, accuracy: 0.000001)
        XCTAssertEqual(results[2].value?.numberValue ?? 0, 4_990, accuracy: 0.000001)
        let pair = try XCTUnwrap(parseDividerPair(results[3].display))
        XCTAssertEqual(5 * pair.1 / (pair.0 + pair.1), 2.5, accuracy: 0.05)
        XCTAssertEqual(results[4].value?.numberValue ?? 0, 9.4, accuracy: 0.000001)
        XCTAssertEqual(results[5].value?.numberValue ?? 0, 0.0005, accuracy: 0.0000001)
        XCTAssertEqual(results[6].value?.numberValue ?? 0, 2_500, accuracy: 0.000001)
        XCTAssertEqual(results[7].value?.numberValue ?? 0, 1_591.549, accuracy: 0.01)
        XCTAssertEqual(results[8].value?.numberValue ?? 0, 62.8318, accuracy: 0.001)
        XCTAssertEqual(results[9].value?.numberValue ?? 0, 6.0206, accuracy: 0.001)
        XCTAssertEqual(results[10].value?.numberValue ?? 0, 10, accuracy: 0.000001)
        XCTAssertEqual(results[11].value?.numberValue ?? 0, 159.1549, accuracy: 0.001)
        XCTAssertEqual(results[12].value?.numberValue ?? 0, 0.001, accuracy: 0.0000001)
        XCTAssertEqual(results[13].value?.numberValue ?? 0, 3.1606, accuracy: 0.001)
        XCTAssertEqual(results[14].value?.numberValue ?? 0, 1.8394, accuracy: 0.001)
        XCTAssertEqual(results[15].value?.numberValue ?? 0, 150, accuracy: 0.000001)
        XCTAssertEqual(results[16].value?.numberValue ?? 0, 512, accuracy: 0.000001)
        XCTAssertEqual(results[17].value?.numberValue ?? 0, 1.6516, accuracy: 0.001)
    }

    func testUnitConversions() {
        let results = engine.evaluateDocument(
            """
            70 F to C
            25.4 mm to in
            x = 2
            x in to mm
            """
        )

        XCTAssertEqual(results[0].display, "21.111 C")
        XCTAssertEqual(results[0].value?.numberValue ?? 0, 21.111111, accuracy: 0.0005)
        XCTAssertEqual(results[1].display, "1 in")
        XCTAssertEqual(results[1].value?.numberValue ?? 0, 1.0, accuracy: 0.000001)
        XCTAssertEqual(results[2].value?.numberValue ?? 0, 2.0, accuracy: 0.000001)
        XCTAssertEqual(results[3].display, "50.8 mm")
        XCTAssertEqual(results[3].value?.numberValue ?? 0, 50.8, accuracy: 0.000001)
    }

    func testExponentAndXorAreDistinct() {
        let results = engine.evaluateDocument(
            """
            2 ^ 3
            7 xor 3
            ~0
            """
        )

        XCTAssertEqual(results[0].value?.numberValue ?? 0, 8, accuracy: 0.000001)
        XCTAssertEqual(results[1].value?.numberValue ?? 0, 4, accuracy: 0.000001)
        XCTAssertEqual(results[2].value?.numberValue ?? 0, -1, accuracy: 0.000001)
    }

    func testHexBinaryAndEngineeringNotationInputsParse() {
        let results = engine.evaluateDocument(
            """
            0x10 + 0b11
            10k + 2M
            """
        )

        XCTAssertEqual(results[0].value?.numberValue ?? 0, 19, accuracy: 0.000001)
        XCTAssertEqual(results[1].value?.numberValue ?? 0, 2_010_000, accuracy: 0.000001)
    }

    func testResultFormattingSettingsAffectDisplay() {
        let siEngine = ScratchpadEngine(
            config: ScratchpadEngineConfig(sigFigures: 4, resultFormat: .si)
        )
        let scientificEngine = ScratchpadEngine(
            config: ScratchpadEngineConfig(sigFigures: 4, resultFormat: .scientific)
        )
        let engineeringEngine = ScratchpadEngine(
            config: ScratchpadEngineConfig(sigFigures: 4, resultFormat: .engineering)
        )

        XCTAssertEqual(siEngine.evaluateDocument("10000")[0].display, "10k")
        XCTAssertEqual(scientificEngine.evaluateDocument("10000")[0].display, "1e4")
        XCTAssertEqual(engineeringEngine.evaluateDocument("10000")[0].display, "10e3")
    }
}
