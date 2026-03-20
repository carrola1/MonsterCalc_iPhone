import XCTest
import UIKit

final class MonsterCalc_iPhoneUITests: XCTestCase {
    private enum SnapshotMode {
        case verify
        case record
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testPortraitLaunchSnapshot() throws {
        let app = launchApp()

        XCTAssertTrue(app.staticTexts["scratchpad.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textViews["scratchpad.editor"].waitForExistence(timeout: 5))
        assertSnapshot(named: "portrait-launch")
    }

    @MainActor
    func testKeyboardModeSnapshots() throws {
        let app = launchApp()
        let editor = app.textViews["scratchpad.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))

        editor.tap()
        XCTAssertTrue(app.segmentedControls["keyboard.modeSelector"].waitForExistence(timeout: 5))

        assertSnapshot(named: "keyboard-calc-portrait")

        app.buttons["Math"].tap()
        assertSnapshot(named: "keyboard-math-portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["Text"].waitForExistence(timeout: 5))

        app.buttons["Text"].tap()
        assertSnapshot(named: "keyboard-text-landscape")

        app.buttons["Convert"].tap()
        assertSnapshot(named: "keyboard-convert-landscape")
    }

    @MainActor
    func testHelpMenuSnapshot() throws {
        let app = launchApp()
        let menuButton = app.buttons["header.menu"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5))

        menuButton.tap()
        XCTAssertTrue(app.buttons["User Guide"].waitForExistence(timeout: 5))
        assertSnapshot(named: "header-menu")
    }

    @MainActor
    func testRecordAppStoreScreenshots() throws {
        var app = launchApp(demo: nil)
        let editor = app.textViews["scratchpad.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["scratchpad.title"].waitForExistence(timeout: 5))

        recordAppStoreScreenshot(named: "01-home")

        app.terminate()
        app = launchApp(demo: "ee")
        let eeEditor = app.textViews["scratchpad.editor"]
        XCTAssertTrue(eeEditor.waitForExistence(timeout: 5))
        eeEditor.tap()
        XCTAssertTrue(app.segmentedControls["keyboard.modeSelector"].waitForExistence(timeout: 5))
        app.buttons["EE"].tap()
        assertHintContains("Electrical", in: app)
        recordAppStoreScreenshot(named: "02-ee-keyboard")

        app.terminate()
        app = launchApp(demo: "prog")
        let progEditor = app.textViews["scratchpad.editor"]
        XCTAssertTrue(progEditor.waitForExistence(timeout: 5))
        progEditor.tap()
        XCTAssertTrue(app.segmentedControls["keyboard.modeSelector"].waitForExistence(timeout: 5))
        app.buttons["Prog"].tap()
        assertHintContains("Programming", in: app)
        recordAppStoreScreenshot(named: "03-prog-keyboard")

        app.terminate()
        app = launchApp(demo: "convert")
        let convertEditor = app.textViews["scratchpad.editor"]
        XCTAssertTrue(convertEditor.waitForExistence(timeout: 5))
        convertEditor.tap()
        XCTAssertTrue(app.segmentedControls["keyboard.modeSelector"].waitForExistence(timeout: 5))
        app.buttons["Convert"].tap()
        assertHintContains("conversion", in: app)
        recordAppStoreScreenshot(named: "04-convert-keyboard")

        app.terminate()
        app = launchApp(demo: nil)
        XCTAssertTrue(app.buttons["header.menu"].waitForExistence(timeout: 5))
        app.buttons["header.menu"].tap()
        XCTAssertTrue(app.buttons["Load Sheet"].waitForExistence(timeout: 5))
        recordAppStoreScreenshot(named: "05-menu")
    }

    @MainActor
    func testEditorHorizontalScrollFollowsCaretAndAllowsManualPanning() throws {
        let app = launchApp()
        let editor = app.textViews["scratchpad.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))

        editor.tap()
        let longLine = String(repeating: "1234567890", count: 10)
        editor.typeText(longLine)

        let debugValue = editor.value as? String ?? "<unavailable>"
        let autoScrolledOffset = try horizontalOffset(from: editor)
        XCTAssertGreaterThan(
            autoScrolledOffset,
            20,
            "Expected caret-follow horizontal scroll after typing a long line. Editor state: \(debugValue)"
        )

        editor.swipeRight()
        let afterSwipeRight = try horizontalOffset(from: editor)
        XCTAssertLessThan(afterSwipeRight, autoScrolledOffset - 5, "Expected manual swipe right to move the editor back toward the line start")

        editor.swipeLeft()
        let afterSwipeLeft = try horizontalOffset(from: editor)
        XCTAssertGreaterThan(afterSwipeLeft, afterSwipeRight + 5, "Expected manual swipe left to move the editor toward the long-line tail")
    }

    private func launchApp(demo: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--ui-testing", "--ui-testing-reset"]
        if let demo {
            app.launchArguments += ["--ui-testing-demo", demo]
        }
        app.launch()
        return app
    }

    private var snapshotMode: SnapshotMode {
        ProcessInfo.processInfo.environment["MONSTERCALC_RECORD_SNAPSHOTS"] == "1" ? .record : .verify
    }

    private var snapshotDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__", isDirectory: true)
    }

    private var appStoreScreenshotDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AppStoreScreenshots", isDirectory: true)
    }

    private func assertSnapshot(
        named name: String,
        maxByteDeltaRatio: Double = 0.001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let screenshot = XCUIScreen.main.screenshot()
        attachScreenshot(named: name, screenshot: screenshot)

        let baselineURL = snapshotDirectory.appendingPathComponent("\(name).png")
        guard let pngData = screenshot.image.pngData() else {
            XCTFail("Unable to encode screenshot PNG", file: file, line: line)
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: snapshotDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            XCTFail("Unable to create snapshot directory: \(error)", file: file, line: line)
            return
        }

        switch snapshotMode {
        case .record:
            do {
                try pngData.write(to: baselineURL, options: .atomic)
            } catch {
                XCTFail("Unable to write baseline snapshot \(baselineURL.lastPathComponent): \(error)", file: file, line: line)
            }
        case .verify:
            guard let baselineData = try? Data(contentsOf: baselineURL) else {
                do {
                    try pngData.write(to: baselineURL, options: .atomic)
                } catch {
                    XCTFail(
                        "Missing baseline snapshot \(baselineURL.lastPathComponent), and auto-record failed: \(error)",
                        file: file,
                        line: line
                    )
                }
                return
            }

            let baselineImage = UIImage(data: baselineData)
            let currentImage = UIImage(data: pngData)

            guard let baseline = normalizedRGBABytes(from: baselineImage),
                  let current = normalizedRGBABytes(from: currentImage)
            else {
                XCTFail("Unable to decode snapshot image bytes for \(name)", file: file, line: line)
                return
            }

            XCTAssertEqual(baseline.width, current.width, "Snapshot width mismatch for \(name)", file: file, line: line)
            XCTAssertEqual(baseline.height, current.height, "Snapshot height mismatch for \(name)", file: file, line: line)

            guard baseline.width == current.width,
                  baseline.height == current.height,
                  baseline.bytes.count == current.bytes.count
            else {
                return
            }

            let mismatchedBytes = zip(baseline.bytes, current.bytes).reduce(into: 0) { partial, pair in
                if pair.0 != pair.1 {
                    partial += 1
                }
            }
            let deltaRatio = Double(mismatchedBytes) / Double(max(1, baseline.bytes.count))

            XCTAssertLessThanOrEqual(
                deltaRatio,
                maxByteDeltaRatio,
                "Snapshot \(name) drifted beyond tolerance. Delta ratio: \(deltaRatio), allowed: \(maxByteDeltaRatio)",
                file: file,
                line: line
            )
        }
    }

    private func normalizedRGBABytes(from image: UIImage?) -> (width: Int, height: Int, bytes: [UInt8])? {
        guard let cgImage = image?.cgImage else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        let drewSuccessfully: Bool = bytes.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else {
                return false
            }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard drewSuccessfully else {
            return nil
        }

        return (width, height, bytes)
    }

    private func attachScreenshot(named name: String, screenshot: XCUIScreenshot) {
        XCTContext.runActivity(named: name) { activity in
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }

    private func recordAppStoreScreenshot(named name: String, file: StaticString = #filePath, line: UInt = #line) {
        let screenshot = XCUIScreen.main.screenshot()
        attachScreenshot(named: "app-store-\(name)", screenshot: screenshot)

        guard let pngData = screenshot.image.pngData() else {
            XCTFail("Unable to encode App Store screenshot PNG", file: file, line: line)
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: appStoreScreenshotDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            try pngData.write(
                to: appStoreScreenshotDirectory.appendingPathComponent("\(name).png"),
                options: .atomic
            )
        } catch {
            XCTFail("Unable to write App Store screenshot \(name): \(error)", file: file, line: line)
        }
    }

    private func assertHintContains(_ token: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let hint = app.staticTexts["keyboard.hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 3), "Keyboard hint did not appear", file: file, line: line)
        XCTAssertTrue(
            hint.label.localizedCaseInsensitiveContains(token),
            "Expected keyboard hint to contain '\(token)', got '\(hint.label)'",
            file: file,
            line: line
        )
    }

    private func horizontalOffset(from editor: XCUIElement, file: StaticString = #filePath, line: UInt = #line) throws -> Double {
        guard let value = editor.value as? String else {
            XCTFail("Editor accessibility value is unavailable", file: file, line: line)
            return 0
        }

        guard let range = value.range(of: #"offsetX=([0-9]+(?:\.[0-9]+)?)"#, options: .regularExpression) else {
            XCTFail("Unable to parse offsetX from editor value: \(value)", file: file, line: line)
            return 0
        }

        let token = String(value[range]).replacingOccurrences(of: "offsetX=", with: "")
        guard let offset = Double(token) else {
            XCTFail("Unable to decode horizontal offset from editor value: \(value)", file: file, line: line)
            return 0
        }
        return offset
    }
}
