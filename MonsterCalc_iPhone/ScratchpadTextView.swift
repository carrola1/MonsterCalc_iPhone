import SwiftUI
import UIKit

final class NonWrappingTextView: UITextView {
    fileprivate var onPreferredWidthChange: ((CGFloat) -> Void)?
    private var preferredContentWidth: CGFloat = 0

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        layoutManager.allowsNonContiguousLayout = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        layoutManager.allowsNonContiguousLayout = false
    }

    private func plainFont() -> UIFont {
        font ?? UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
    }

    private func measuredLineWidth(_ line: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: plainFont()]
        return ceil((line as NSString).size(withAttributes: attributes).width)
    }

    private func currentLines() -> [String] {
        let lines = (text ?? "").components(separatedBy: "\n")
        return lines.isEmpty ? [""] : lines
    }

    fileprivate func longestLineWidth() -> CGFloat {
        currentLines().map(measuredLineWidth).max() ?? 0
    }

    fileprivate func caretXPosition() -> CGFloat {
        guard let selectedTextRange else {
            return textContainerInset.left
        }

        let cursorLocation = offset(from: beginningOfDocument, to: selectedTextRange.end)
        let nsText = (text ?? "") as NSString
        let clampedLocation = max(0, min(cursorLocation, nsText.length))

        var lineStart = 0
        nsText.getLineStart(&lineStart, end: nil, contentsEnd: nil, for: NSRange(location: clampedLocation, length: 0))
        let prefixRange = NSRange(location: lineStart, length: max(0, clampedLocation - lineStart))
        let prefix = nsText.substring(with: prefixRange)
        return textContainerInset.left + measuredLineWidth(prefix)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        textContainer.widthTracksTextView = true
        textContainer.lineBreakMode = .byClipping
        layoutManager.ensureLayout(for: textContainer)
        let horizontalInsets = textContainerInset.left + textContainerInset.right + (textContainer.lineFragmentPadding * 2)
        let verticalInsets = textContainerInset.top + textContainerInset.bottom
        let contentWidth = max(
            bounds.width + 1,
            ceil(max(longestLineWidth(), caretXPosition()) + horizontalInsets + 48)
        )

        if abs(preferredContentWidth - contentWidth) > 0.5 {
            preferredContentWidth = contentWidth
            onPreferredWidthChange?(contentWidth)
        }

        let fittedSize = sizeThatFits(CGSize(width: max(bounds.width, 1), height: CGFloat.greatestFiniteMagnitude))
        let contentHeight = max(bounds.height + 1, ceil(max(fittedSize.height, bounds.height) + max(0, verticalInsets - 4)))

        if abs(contentSize.height - contentHeight) > 0.5 || abs(contentSize.width - contentWidth) > 0.5 {
            contentSize = CGSize(width: contentWidth, height: contentHeight)
        }
    }
}

private func clampedVerticalOffset(_ desiredOffset: CGFloat, in textView: UITextView) -> CGFloat {
    let topInset = textView.adjustedContentInset.top
    let bottomInset = textView.adjustedContentInset.bottom
    let minOffset = -topInset
    let maxOffset = max(minOffset, textView.contentSize.height + bottomInset - textView.bounds.height)
    return min(max(desiredOffset, minOffset), maxOffset)
}

enum EditorInputMode: Int {
    case system
    case calc
    case math
    case convert
    case ee
    case prog

    var usesCustomKeyboard: Bool {
        true
    }

    var keyboardPageIndex: Int {
        switch self {
        case .system:
            return 0
        case .calc:
            return 1
        case .math:
            return 2
        case .convert:
            return 3
        case .ee:
            return 4
        case .prog:
            return 5
        }
    }
}

private enum KeyboardAction: Equatable {
    case insert(String)
    case toggleShift
    case backspace
    case clearLine
    case clearAll
    case newline
    case moveLeft
    case moveRight
    case none
}

private struct KeyboardKey {
    let label: String
    let action: KeyboardAction
    let menuOptions: [KeyboardKey]
    let description: String
    let span: Int

    init(label: String, action: KeyboardAction, description: String, menuOptions: [KeyboardKey] = [], span: Int = 1) {
        self.label = label
        self.action = action
        self.menuOptions = menuOptions
        self.description = description
        self.span = max(1, span)
    }
}

final class ExpandableKeyboardButton: UIButton {
    fileprivate var expansionOptions: [KeyboardKey] = []
}

final class ExpansionOptionButton: UIButton {
    fileprivate var optionKey: KeyboardKey?
}

private struct KeyboardPage {
    let title: String
    let keys: [KeyboardKey]
}

private struct KeyboardRowSpec {
    let keys: [KeyboardKey]
    let columns: Int
    let rowHeight: CGFloat
}

private enum CustomKeyboardMetrics {
    static let portraitButtonHeight: CGFloat = 40
    static let landscapeButtonHeight: CGFloat = 31
}

private extension KeyboardKey {
    func withSpan(_ span: Int) -> KeyboardKey {
        KeyboardKey(
            label: label,
            action: action,
            description: description,
            menuOptions: menuOptions,
            span: span
        )
    }
}

private let customKeyboardPageCount = 6

private let calcKeyboardPage = KeyboardPage(title: "Calc", keys: [
    KeyboardKey(label: "7", action: .insert("7"), description: "Insert 7"),
    KeyboardKey(label: "8", action: .insert("8"), description: "Insert 8"),
    KeyboardKey(label: "9", action: .insert("9"), description: "Insert 9"),
    KeyboardKey(label: "+", action: .insert("+"), description: "Add"),
    KeyboardKey(label: "-", action: .insert("-"), description: "Subtract"),
    KeyboardKey(label: "4", action: .insert("4"), description: "Insert 4"),
    KeyboardKey(label: "5", action: .insert("5"), description: "Insert 5"),
    KeyboardKey(label: "6", action: .insert("6"), description: "Insert 6"),
    KeyboardKey(label: "*", action: .insert("*"), description: "Multiply"),
    KeyboardKey(label: "/", action: .insert("/"), description: "Divide"),
    KeyboardKey(label: "1", action: .insert("1"), description: "Insert 1"),
    KeyboardKey(label: "2", action: .insert("2"), description: "Insert 2"),
    KeyboardKey(label: "3", action: .insert("3"), description: "Insert 3"),
    KeyboardKey(label: "(", action: .insert("("), description: "Left parenthesis"),
    KeyboardKey(label: ")", action: .insert(")"), description: "Right parenthesis"),
    KeyboardKey(label: "0", action: .insert("0"), description: "Insert 0"),
    KeyboardKey(label: ".", action: .insert("."), description: "Decimal point"),
    KeyboardKey(label: ",", action: .insert(","), description: "Comma"),
    KeyboardKey(label: "=", action: .insert(" = "), description: "Assignment equals"),
    KeyboardKey(label: "ans", action: .insert("ans"), description: "Previous result"),
    KeyboardKey(label: "<-", action: .moveLeft, description: "Move cursor left"),
    KeyboardKey(label: "->", action: .moveRight, description: "Move cursor right"),
    KeyboardKey(
        label: "␣",
        action: .insert(" "),
        description: "Space"
    ),
    KeyboardKey(
        label: "⌫",
        action: .backspace,
        description: "Delete backward",
        menuOptions: [
            KeyboardKey(label: "Line", action: .clearLine, description: "Clear current line"),
            KeyboardKey(label: "All", action: .clearAll, description: "Clear entire scratchpad"),
        ]
    ),
    KeyboardKey(label: "↵", action: .newline, description: "New line"),
])

private let mathKeyboardPage = KeyboardPage(title: "Math", keys: [
    KeyboardKey(label: "π", action: .insert("pi"), description: "Pi constant"),
    KeyboardKey(label: "E", action: .insert("e"), description: "Euler's number"),
    KeyboardKey(label: "e", action: .insert("e"), description: "Euler's number"),
    KeyboardKey(
        label: "ENG",
        action: .none,
        description: "Engineering notation prefixes",
        menuOptions: [
            KeyboardKey(label: "p", action: .insert("p"), description: "Pico (1e-12)"),
            KeyboardKey(label: "n", action: .insert("n"), description: "Nano (1e-9)"),
            KeyboardKey(label: "u", action: .insert("u"), description: "Micro (1e-6)"),
            KeyboardKey(label: "m", action: .insert("m"), description: "Milli (1e-3)"),
            KeyboardKey(label: "k", action: .insert("k"), description: "Kilo (1e3)"),
            KeyboardKey(label: "M", action: .insert("M"), description: "Mega (1e6)"),
            KeyboardKey(label: "G", action: .insert("G"), description: "Giga (1e9)"),
        ]
    ),
    KeyboardKey(label: "√", action: .insert("sqrt("), description: "Square root"),
    KeyboardKey(label: "^", action: .insert("^"), description: "Exponent"),
    KeyboardKey(label: "%", action: .insert("%"), description: "Modulus"),
    KeyboardKey(label: "abs", action: .insert("abs("), description: "Absolute value"),
    KeyboardKey(
        label: "sin",
        action: .insert("sin("),
        description: "Trig functions",
        menuOptions: [
            KeyboardKey(label: "sin", action: .insert("sin("), description: "Sine"),
            KeyboardKey(label: "asin", action: .insert("asin("), description: "Arc-sine"),
            KeyboardKey(label: "cos", action: .insert("cos("), description: "Cosine"),
            KeyboardKey(label: "acos", action: .insert("acos("), description: "Arc-cosine"),
            KeyboardKey(label: "tan", action: .insert("tan("), description: "Tangent"),
            KeyboardKey(label: "atan", action: .insert("atan("), description: "Arc-tangent"),
        ]
    ),
    KeyboardKey(
        label: "log",
        action: .insert("log("),
        description: "Log and exponent functions",
        menuOptions: [
            KeyboardKey(label: "log", action: .insert("log("), description: "Natural log"),
            KeyboardKey(label: "log10", action: .insert("log10("), description: "Log base 10"),
            KeyboardKey(label: "log2", action: .insert("log2("), description: "Log base 2"),
            KeyboardKey(label: "exp", action: .insert("exp("), description: "Exponential"),
        ]
    ),
    KeyboardKey(label: "deg", action: .insert("deg("), description: "Radians to degrees"),
    KeyboardKey(label: "rad", action: .insert("rad("), description: "Degrees to radians"),
    KeyboardKey(label: "sum", action: .insert("sum("), description: "Sum values"),
    KeyboardKey(label: "min", action: .insert("min("), description: "Minimum value"),
    KeyboardKey(label: "max", action: .insert("max("), description: "Maximum value"),
    KeyboardKey(label: "cdf", action: .insert("cdf("), description: "Normal cumulative distribution"),
    KeyboardKey(label: "pdf", action: .insert("pdf("), description: "Normal probability density"),
    KeyboardKey(
        label: "rnd",
        action: .insert("floor("),
        description: "Rounding functions",
        menuOptions: [
            KeyboardKey(label: "floor", action: .insert("floor("), description: "Round down"),
            KeyboardKey(label: "ceil", action: .insert("ceil("), description: "Round up"),
        ]
    ),
])

private let eeKeyboardPage = KeyboardPage(title: "EE", keys: [
    KeyboardKey(label: "vdiv", action: .insert("vdiv("), description: "Voltage divider out (vin, R1, R2)"),
    KeyboardKey(label: "rpar", action: .insert("rpar("), description: "Parallel resistor calc"),
    KeyboardKey(label: "findres", action: .insert("findres("), description: "Closest standard resistor"),
    KeyboardKey(label: "findrdiv", action: .insert("findrdiv("), description: "Find resistor divider values", span: 2),
])

private let progKeyboardPage = KeyboardPage(title: "Prog", keys: [
    KeyboardKey(label: "0x", action: .insert("0x"), description: "Hex prefix"),
    KeyboardKey(label: "0b", action: .insert("0b"), description: "Binary prefix"),
    KeyboardKey(label: "0", action: .insert("0"), description: "Insert 0"),
    KeyboardKey(label: "1", action: .insert("1"), description: "Insert 1"),
    KeyboardKey(
        label: "2-9",
        action: .none,
        description: "Digits 2 through 9",
        menuOptions: [
            KeyboardKey(label: "2", action: .insert("2"), description: "Insert 2"),
            KeyboardKey(label: "3", action: .insert("3"), description: "Insert 3"),
            KeyboardKey(label: "4", action: .insert("4"), description: "Insert 4"),
            KeyboardKey(label: "5", action: .insert("5"), description: "Insert 5"),
            KeyboardKey(label: "6", action: .insert("6"), description: "Insert 6"),
            KeyboardKey(label: "7", action: .insert("7"), description: "Insert 7"),
            KeyboardKey(label: "8", action: .insert("8"), description: "Insert 8"),
            KeyboardKey(label: "9", action: .insert("9"), description: "Insert 9"),
        ]
    ),
    KeyboardKey(
        label: "A-F",
        action: .none,
        description: "Hex digits A through F",
        menuOptions: [
            KeyboardKey(label: "A", action: .insert("A"), description: "Insert A"),
            KeyboardKey(label: "B", action: .insert("B"), description: "Insert B"),
            KeyboardKey(label: "C", action: .insert("C"), description: "Insert C"),
            KeyboardKey(label: "D", action: .insert("D"), description: "Insert D"),
            KeyboardKey(label: "E", action: .insert("E"), description: "Insert E"),
            KeyboardKey(label: "F", action: .insert("F"), description: "Insert F"),
        ]
    ),
    KeyboardKey(
        label: "xor",
        action: .insert(" xor "),
        description: "Bitwise logic operators",
        menuOptions: [
            KeyboardKey(label: "xor", action: .insert(" xor "), description: "Bitwise XOR"),
            KeyboardKey(label: "&", action: .insert("&"), description: "Bitwise AND"),
            KeyboardKey(label: "|", action: .insert("|"), description: "Bitwise OR"),
        ]
    ),
    KeyboardKey(label: "<<", action: .insert(" << "), description: "Shift left"),
    KeyboardKey(label: ">>", action: .insert(" >> "), description: "Shift right"),
    KeyboardKey(label: "to", action: .insert(" to "), description: "Unit conversion"),
    KeyboardKey(label: "hex", action: .insert("hex("), description: "Convert to hex"),
    KeyboardKey(label: "bin", action: .insert("bin("), description: "Convert to binary"),
    KeyboardKey(label: "bitget", action: .insert("bitget("), description: "Bit slice (value, msb, lsb)"),
    KeyboardKey(label: "bitpunch", action: .insert("bitpunch("), description: "Set or clear bit", span: 2),
    KeyboardKey(label: "a2h", action: .insert("a2h("), description: "ASCII to hex"),
    KeyboardKey(label: "h2a", action: .insert("h2a("), description: "Hex to ASCII"),
    KeyboardKey(label: "(", action: .insert("("), description: "Left parenthesis"),
    KeyboardKey(label: ")", action: .insert(")"), description: "Right parenthesis"),
    KeyboardKey(label: ",", action: .insert(","), description: "Comma"),
    KeyboardKey(label: "␣", action: .insert(" "), description: "Space", span: 2),
    KeyboardKey(label: "↵", action: .newline, description: "New line"),
    KeyboardKey(
        label: "⌫",
        action: .backspace,
        description: "Delete backward",
        menuOptions: [
            KeyboardKey(label: "Line", action: .clearLine, description: "Clear current line"),
            KeyboardKey(label: "All", action: .clearAll, description: "Clear entire scratchpad"),
        ]
    ),
])

private struct ConversionUnit {
    let label: String
    let token: String
}

private struct ConversionCategory {
    let title: String
    let units: [ConversionUnit]
}

private let conversionCategories: [ConversionCategory] = [
    ConversionCategory(title: "Length", units: [
        ConversionUnit(label: "Millimeter", token: "mm"),
        ConversionUnit(label: "Centimeter", token: "cm"),
        ConversionUnit(label: "Meter", token: "m"),
        ConversionUnit(label: "Kilometer", token: "km"),
        ConversionUnit(label: "Mil", token: "mil"),
        ConversionUnit(label: "Inch", token: "in"),
    ]),
    ConversionCategory(title: "Weight", units: [
        ConversionUnit(label: "Milligram", token: "mg"),
        ConversionUnit(label: "Gram", token: "g"),
        ConversionUnit(label: "Kilogram", token: "kg"),
        ConversionUnit(label: "Pound", token: "lbs"),
        ConversionUnit(label: "Ounce", token: "oz"),
    ]),
    ConversionCategory(title: "Temp", units: [
        ConversionUnit(label: "Celsius", token: "C"),
        ConversionUnit(label: "Fahrenheit", token: "F"),
    ]),
    ConversionCategory(title: "Volume", units: [
        ConversionUnit(label: "Milliliter", token: "mL"),
        ConversionUnit(label: "Liter", token: "L"),
        ConversionUnit(label: "Teaspoon", token: "tsp"),
        ConversionUnit(label: "Tablespoon", token: "tbl"),
        ConversionUnit(label: "Pint", token: "pt"),
        ConversionUnit(label: "Quart", token: "qt"),
        ConversionUnit(label: "Gallon", token: "gal"),
    ]),
    ConversionCategory(title: "Force", units: [
        ConversionUnit(label: "Newton", token: "N"),
        ConversionUnit(label: "Kilonewton", token: "kN"),
        ConversionUnit(label: "Pound-force", token: "lbf"),
    ]),
    ConversionCategory(title: "Memory", units: [
        ConversionUnit(label: "Bits", token: "bits"),
        ConversionUnit(label: "Bytes", token: "bytes"),
        ConversionUnit(label: "KB", token: "KB"),
        ConversionUnit(label: "MB", token: "MB"),
        ConversionUnit(label: "GB", token: "GB"),
        ConversionUnit(label: "Tb", token: "Tb"),
    ]),
]

final class ScrollSyncBridge: ObservableObject {
    private weak var gutterView: UITextView?
    private weak var resultsView: UITextView?
    private var isSyncing = false

    func registerEditor(textView: UITextView, gutterView: UITextView) {
        self.gutterView = gutterView
    }

    func registerResults(textView: UITextView) {
        self.resultsView = textView
    }

    func syncVerticalOffset(_ offset: CGFloat, source: UITextView?) {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        if let gutterView, gutterView !== source {
            let targetOffset = max(0, offset)
            if abs(gutterView.contentOffset.y - targetOffset) > 0.5 {
                gutterView.setContentOffset(CGPoint(x: 0, y: targetOffset), animated: false)
            }
        }
        if let resultsView, resultsView !== source {
            let targetOffset = max(0, offset)
            if abs(resultsView.contentOffset.y - targetOffset) > 0.5 {
                resultsView.setContentOffset(CGPoint(x: resultsView.contentOffset.x, y: targetOffset), animated: false)
            }
        }
    }
}

final class MonsterKeyboardHostView: UIInputView {
    let keyboardView: MonsterKeyboardView
    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: currentKeyboardHeight)

    init(keyboardView: MonsterKeyboardView) {
        self.keyboardView = keyboardView
        super.init(frame: .zero, inputViewStyle: .keyboard)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        allowsSelfSizing = true

        addSubview(keyboardView)
        NSLayoutConstraint.activate([
            keyboardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            keyboardView.topAnchor.constraint(equalTo: topAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        heightConstraint.isActive = true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: currentKeyboardHeight)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshHeight()
            self.keyboardView.forceRefreshLayout()
        }
    }

    func refreshHeight() {
        let height = currentKeyboardHeight
        if abs(heightConstraint.constant - height) > 0.5 {
            heightConstraint.constant = height
        }
        invalidateIntrinsicContentSize()
        frame.size.height = height
        keyboardView.refreshLayoutForCurrentOrientation()
        setNeedsLayout()
    }

    private var currentKeyboardHeight: CGFloat {
        let isLandscape: Bool
        if let orientation = window?.windowScene?.interfaceOrientation {
            isLandscape = orientation.isLandscape
        } else {
            isLandscape = UIScreen.main.bounds.width > UIScreen.main.bounds.height
        }
        return isLandscape ? 220 : 338
    }
}

final class MonsterKeyboardView: UIView {
    private let actionHandler: (KeyboardAction) -> Void
    private let scrollView = UIScrollView()
    private let onPageChange: (Int) -> Void
    private let onDismissKeyboard: () -> Void
    private let overlayDismissControl = UIControl()
    private let segmentedControl = UISegmentedControl(items: ["Text", "Calc", "Math", "Convert", "EE", "Prog"])
    private let dismissButton = UIButton(type: .system)
    private let hintLabel = UILabel()
    private let backgroundPanel = UIView()
    private var hintHeightConstraint: NSLayoutConstraint?
    private var scrollViewTopConstraint: NSLayoutConstraint?
    private var activeExpansionOptionButtons: [ExpansionOptionButton] = []
    private weak var highlightedExpansionOptionButton: ExpansionOptionButton?
    private let textPageContainer = UIView()
    private let calcPageContainer = UIView()
    private let mathPageContainer = UIView()
    private let convertPageContainer = UIView()
    private let eePageContainer = UIView()
    private let progPageContainer = UIView()
    private var isTextShiftEnabled = false
    private weak var activeExpansionView: UIView?
    private var currentPage = 0
    private var layoutConstraints: [NSLayoutConstraint] = []
    private var lastLandscapeState: Bool?

    fileprivate init(
        actionHandler: @escaping (KeyboardAction) -> Void,
        onPageChange: @escaping (Int) -> Void,
        onDismissKeyboard: @escaping () -> Void
    ) {
        self.actionHandler = actionHandler
        self.onPageChange = onPageChange
        self.onDismissKeyboard = onDismissKeyboard
        super.init(frame: .zero)
        autoresizingMask = [.flexibleHeight]
        translatesAutoresizingMaskIntoConstraints = false
        isOpaque = true
        backgroundColor = UIColor(red: 0.17, green: 0.18, blue: 0.19, alpha: 1.0)
        setup()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if lastLandscapeState == nil {
            lastLandscapeState = currentOrientationIsLandscape()
            rebuildPages()
        }
        guard scrollView.bounds.width > 0 else { return }
        let targetX = CGFloat(currentPage) * scrollView.bounds.width
        if abs(scrollView.contentOffset.x - targetX) > 0.5 {
            scrollView.setContentOffset(CGPoint(x: targetX, y: 0), animated: false)
        }
    }

    func forceRefreshLayout() {
        lastLandscapeState = currentOrientationIsLandscape()
        rebuildPages()
        setPage(currentPage, animated: false)
        setNeedsLayout()
    }

    func refreshLayoutForCurrentOrientation() {
        let isLandscape = currentOrientationIsLandscape()
        guard lastLandscapeState != isLandscape || textPageContainer.subviews.isEmpty else {
            return
        }
        lastLandscapeState = isLandscape
        rebuildPages()
        setNeedsLayout()
    }

    private func setup() {
        backgroundPanel.translatesAutoresizingMaskIntoConstraints = false
        backgroundPanel.backgroundColor = UIColor(red: 0.17, green: 0.18, blue: 0.19, alpha: 1.0)

        overlayDismissControl.translatesAutoresizingMaskIntoConstraints = false
        overlayDismissControl.backgroundColor = .clear
        overlayDismissControl.isHidden = true
        overlayDismissControl.addAction(UIAction { [weak self] _ in
            self?.dismissExpansion()
        }, for: .touchUpInside)

        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.backgroundColor = UIColor(red: 0.24, green: 0.25, blue: 0.27, alpha: 1.0)
        segmentedControl.selectedSegmentTintColor = ScratchpadStyle.accent
        segmentedControl.accessibilityIdentifier = "keyboard.modeSelector"
        segmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        segmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        segmentedControl.addTarget(self, action: #selector(handleSegmentChange), for: .valueChanged)

        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 15.0, *) {
            dismissButton.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
        } else {
            dismissButton.setTitle("⌄", for: .normal)
        }
        dismissButton.tintColor = UIColor.white.withAlphaComponent(0.88)
        dismissButton.backgroundColor = UIColor(red: 0.24, green: 0.25, blue: 0.27, alpha: 1.0)
        dismissButton.layer.cornerRadius = 9
        dismissButton.contentEdgeInsets = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        dismissButton.accessibilityIdentifier = "keyboard.dismiss"
        dismissButton.accessibilityLabel = "Dismiss keyboard"
        dismissButton.addAction(UIAction { [weak self] _ in
            self?.onDismissKeyboard()
        }, for: .touchUpInside)

        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.78)
        hintLabel.numberOfLines = 1
        hintLabel.lineBreakMode = .byClipping
        hintLabel.adjustsFontSizeToFitWidth = true
        hintLabel.minimumScaleFactor = 0.82
        hintLabel.accessibilityIdentifier = "keyboard.hint"
        hintLabel.text = defaultHint(for: 0)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = self

        let pagesStack = UIStackView()
        pagesStack.translatesAutoresizingMaskIntoConstraints = false
        pagesStack.axis = .horizontal
        pagesStack.alignment = .fill
        pagesStack.distribution = .fillEqually

        textPageContainer.translatesAutoresizingMaskIntoConstraints = false
        calcPageContainer.translatesAutoresizingMaskIntoConstraints = false
        mathPageContainer.translatesAutoresizingMaskIntoConstraints = false
        convertPageContainer.translatesAutoresizingMaskIntoConstraints = false
        eePageContainer.translatesAutoresizingMaskIntoConstraints = false
        progPageContainer.translatesAutoresizingMaskIntoConstraints = false
        pagesStack.addArrangedSubview(textPageContainer)
        pagesStack.addArrangedSubview(calcPageContainer)
        pagesStack.addArrangedSubview(mathPageContainer)
        pagesStack.addArrangedSubview(convertPageContainer)
        pagesStack.addArrangedSubview(eePageContainer)
        pagesStack.addArrangedSubview(progPageContainer)

        addSubview(backgroundPanel)
        addSubview(segmentedControl)
        addSubview(dismissButton)
        addSubview(hintLabel)
        addSubview(scrollView)
        addSubview(overlayDismissControl)
        scrollView.addSubview(pagesStack)

        layoutConstraints = [
            backgroundPanel.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundPanel.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundPanel.topAnchor.constraint(equalTo: topAnchor),
            backgroundPanel.bottomAnchor.constraint(equalTo: bottomAnchor),

            segmentedControl.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 10),
            segmentedControl.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -8),
            segmentedControl.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            segmentedControl.heightAnchor.constraint(equalToConstant: 32),

            dismissButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -10),
            dismissButton.centerYAnchor.constraint(equalTo: segmentedControl.centerYAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 32),
            dismissButton.heightAnchor.constraint(equalToConstant: 32),

            hintLabel.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 12),
            hintLabel.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -12),
            hintLabel.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 6),

            scrollView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),

            pagesStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            pagesStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            pagesStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            pagesStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            pagesStack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            pagesStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, multiplier: CGFloat(customKeyboardPageCount)),
            scrollView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -4),

            overlayDismissControl.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayDismissControl.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayDismissControl.topAnchor.constraint(equalTo: topAnchor),
            overlayDismissControl.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]
        hintHeightConstraint = hintLabel.heightAnchor.constraint(equalToConstant: 18)
        scrollViewTopConstraint = scrollView.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 6)
        if let hintHeightConstraint, let scrollViewTopConstraint {
            layoutConstraints.append(contentsOf: [hintHeightConstraint, scrollViewTopConstraint])
        }
        NSLayoutConstraint.activate(layoutConstraints)

        rebuildPages()
        setPage(segmentedControl.selectedSegmentIndex, animated: false)
    }

    @objc private func handleSegmentChange() {
        setPage(segmentedControl.selectedSegmentIndex, animated: false)
    }

    private func rebuildPages() {
        rebuildTextPage()
        rebuildGridPage(in: calcPageContainer, pageModel: calcKeyboardPage)
        rebuildGridPage(in: mathPageContainer, pageModel: mathKeyboardPage)
        rebuildConvertPage()
        rebuildGridPage(in: eePageContainer, pageModel: eeKeyboardPage)
        rebuildGridPage(in: progPageContainer, pageModel: progKeyboardPage)
    }

    private func rebuildTextPage() {
        textPageContainer.subviews.forEach { $0.removeFromSuperview() }

        let isLandscape = currentOrientationIsLandscape()
        if isLandscape {
            let rowSpecs: [KeyboardRowSpec] = [
                KeyboardRowSpec(
                    keys: ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"].map {
                        KeyboardKey(label: isTextShiftEnabled ? $0.uppercased() : $0, action: .insert(isTextShiftEnabled ? $0.uppercased() : $0), description: "Insert \(isTextShiftEnabled ? $0.uppercased() : $0)")
                    },
                    columns: 10,
                    rowHeight: 31
                ),
                KeyboardRowSpec(
                    keys: ["a", "s", "d", "f", "g", "h", "j", "k", "l"].map {
                        KeyboardKey(label: isTextShiftEnabled ? $0.uppercased() : $0, action: .insert(isTextShiftEnabled ? $0.uppercased() : $0), description: "Insert \(isTextShiftEnabled ? $0.uppercased() : $0)")
                    },
                    columns: 9,
                    rowHeight: 31
                ),
                KeyboardRowSpec(
                    keys: [
                        KeyboardKey(label: "⇧", action: .toggleShift, description: isTextShiftEnabled ? "Disable shift" : "Enable shift", span: 2),
                        KeyboardKey(label: isTextShiftEnabled ? "Z" : "z", action: .insert(isTextShiftEnabled ? "Z" : "z"), description: "Insert \(isTextShiftEnabled ? "Z" : "z")"),
                        KeyboardKey(label: isTextShiftEnabled ? "X" : "x", action: .insert(isTextShiftEnabled ? "X" : "x"), description: "Insert \(isTextShiftEnabled ? "X" : "x")"),
                        KeyboardKey(label: isTextShiftEnabled ? "C" : "c", action: .insert(isTextShiftEnabled ? "C" : "c"), description: "Insert \(isTextShiftEnabled ? "C" : "c")"),
                        KeyboardKey(label: isTextShiftEnabled ? "V" : "v", action: .insert(isTextShiftEnabled ? "V" : "v"), description: "Insert \(isTextShiftEnabled ? "V" : "v")"),
                        KeyboardKey(label: isTextShiftEnabled ? "B" : "b", action: .insert(isTextShiftEnabled ? "B" : "b"), description: "Insert \(isTextShiftEnabled ? "B" : "b")"),
                        KeyboardKey(label: isTextShiftEnabled ? "N" : "n", action: .insert(isTextShiftEnabled ? "N" : "n"), description: "Insert \(isTextShiftEnabled ? "N" : "n")"),
                        KeyboardKey(label: isTextShiftEnabled ? "M" : "m", action: .insert(isTextShiftEnabled ? "M" : "m"), description: "Insert \(isTextShiftEnabled ? "M" : "m")"),
                        KeyboardKey(
                            label: "⌫",
                            action: .backspace,
                            description: "Delete backward",
                            menuOptions: [
                                KeyboardKey(label: "Line", action: .clearLine, description: "Clear current line"),
                                KeyboardKey(label: "All", action: .clearAll, description: "Clear entire scratchpad"),
                            ],
                            span: 2
                        ),
                    ],
                    columns: 11,
                    rowHeight: 31
                ),
                KeyboardRowSpec(
                    keys: [
                        KeyboardKey(label: "<-", action: .moveLeft, description: "Move cursor left"),
                        KeyboardKey(label: "->", action: .moveRight, description: "Move cursor right"),
                        KeyboardKey(label: "#", action: .insert("# "), description: "Insert comment"),
                        KeyboardKey(label: "␣", action: .insert(" "), description: "Space", span: 5),
                        KeyboardKey(label: "↵", action: .newline, description: "New line", span: 2),
                    ],
                    columns: 10,
                    rowHeight: 31
                ),
            ]

            let page = makeRowSpecsPage(rowSpecs, rowSpacing: 4)
            textPageContainer.addSubview(page)
            NSLayoutConstraint.activate([
                page.leadingAnchor.constraint(equalTo: textPageContainer.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: textPageContainer.trailingAnchor),
                page.topAnchor.constraint(equalTo: textPageContainer.topAnchor),
                page.bottomAnchor.constraint(equalTo: textPageContainer.bottomAnchor),
            ])
            return
        }

        let alphaRowHeight: CGFloat = isLandscape ? 34 : 40
        let symbolsRowHeight: CGFloat = isLandscape ? 30 : 34
        let bottomRowHeight: CGFloat = isLandscape ? 34 : 40
        let rowSpacing: CGFloat = isLandscape ? 4 : 6

        let letters = isTextShiftEnabled
            ? ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "A", "S", "D", "F", "G", "H", "J", "K", "L", "Z", "X", "C", "V", "B", "N", "M"]
            : ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "a", "s", "d", "f", "g", "h", "j", "k", "l", "z", "x", "c", "v", "b", "n", "m"]

        let rowSpecs: [KeyboardRowSpec] = [
            KeyboardRowSpec(
                keys: letters[0...9].map { KeyboardKey(label: $0, action: .insert($0), description: "Insert \($0)") },
                columns: 10,
                rowHeight: alphaRowHeight
            ),
            KeyboardRowSpec(
                keys: letters[10...18].map { KeyboardKey(label: $0, action: .insert($0), description: "Insert \($0)") },
                columns: 9,
                rowHeight: alphaRowHeight
            ),
            KeyboardRowSpec(
                keys: [
                    KeyboardKey(label: "⇧", action: .toggleShift, description: isTextShiftEnabled ? "Disable shift" : "Enable shift", span: 2),
                    KeyboardKey(label: letters[19], action: .insert(letters[19]), description: "Insert \(letters[19])"),
                    KeyboardKey(label: letters[20], action: .insert(letters[20]), description: "Insert \(letters[20])"),
                    KeyboardKey(label: letters[21], action: .insert(letters[21]), description: "Insert \(letters[21])"),
                    KeyboardKey(label: letters[22], action: .insert(letters[22]), description: "Insert \(letters[22])"),
                    KeyboardKey(label: letters[23], action: .insert(letters[23]), description: "Insert \(letters[23])"),
                    KeyboardKey(label: letters[24], action: .insert(letters[24]), description: "Insert \(letters[24])"),
                    KeyboardKey(label: letters[25], action: .insert(letters[25]), description: "Insert \(letters[25])"),
                    KeyboardKey(
                        label: "⌫",
                        action: .backspace,
                        description: "Delete backward",
                        menuOptions: [
                            KeyboardKey(label: "Line", action: .clearLine, description: "Clear current line"),
                            KeyboardKey(label: "All", action: .clearAll, description: "Clear entire scratchpad"),
                        ],
                        span: 2
                    ),
                ],
                columns: 11,
                rowHeight: alphaRowHeight
            ),
            KeyboardRowSpec(
                keys: [
                    KeyboardKey(label: "#", action: .insert("# "), description: "Insert comment"),
                    KeyboardKey(label: "ans", action: .insert("ans"), description: "Previous result"),
                    KeyboardKey(label: "line", action: .insert("line"), description: "Insert line reference", span: 2),
                    KeyboardKey(label: "\"", action: .insert("\""), description: "Insert quote"),
                    KeyboardKey(label: "_", action: .insert("_"), description: "Insert underscore"),
                    KeyboardKey(label: ".", action: .insert("."), description: "Insert period"),
                    KeyboardKey(label: ",", action: .insert(","), description: "Insert comma"),
                    KeyboardKey(label: "=", action: .insert(" = "), description: "Assignment equals"),
                ],
                columns: 9,
                rowHeight: symbolsRowHeight
            ),
            KeyboardRowSpec(
                keys: [
                    KeyboardKey(label: "<-", action: .moveLeft, description: "Move cursor left"),
                    KeyboardKey(label: "->", action: .moveRight, description: "Move cursor right"),
                    KeyboardKey(label: "␣", action: .insert(" "), description: "Space", span: 6),
                    KeyboardKey(label: "↵", action: .newline, description: "New line", span: 2),
                ],
                columns: 10,
                rowHeight: bottomRowHeight
            ),
        ]

        let page = makeRowSpecsPage(rowSpecs, rowSpacing: rowSpacing)
        textPageContainer.addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: textPageContainer.safeAreaLayoutGuide.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: textPageContainer.safeAreaLayoutGuide.trailingAnchor),
            page.topAnchor.constraint(equalTo: textPageContainer.topAnchor),
            page.bottomAnchor.constraint(equalTo: textPageContainer.bottomAnchor),
        ])
    }

    private func rebuildGridPage(in container: UIView, pageModel: KeyboardPage) {
        container.subviews.forEach { $0.removeFromSuperview() }
        let page = makeButtonGridPage(pageModel)
        container.addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor),
            page.topAnchor.constraint(equalTo: container.topAnchor),
            page.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    private func rebuildConvertPage() {
        convertPageContainer.subviews.forEach { $0.removeFromSuperview() }
        let page = makeConvertPage()
        convertPageContainer.addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: convertPageContainer.safeAreaLayoutGuide.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: convertPageContainer.safeAreaLayoutGuide.trailingAnchor),
            page.topAnchor.constraint(equalTo: convertPageContainer.topAnchor),
            page.bottomAnchor.constraint(equalTo: convertPageContainer.bottomAnchor),
        ])
    }

    private func currentOrientationIsLandscape() -> Bool {
        if let orientation = window?.windowScene?.interfaceOrientation {
            return orientation.isLandscape
        }
        if bounds.width > 0 && bounds.height > 0 {
            return bounds.width > bounds.height
        }
        return UIScreen.main.bounds.width > UIScreen.main.bounds.height
    }

    private func makeButtonGridPage(_ pageModel: KeyboardPage) -> UIView {
        let isLandscape = currentOrientationIsLandscape()
        if isLandscape, let rowSpecs = landscapeRowSpecs(for: pageModel) {
            return makeRowSpecsPage(rowSpecs, rowSpacing: 4)
        }
        if !isLandscape, let rowSpecs = portraitRowSpecs(for: pageModel) {
            return makeRowSpecsPage(rowSpecs, rowSpacing: 8)
        }
        return makeCustomGridPage(
            rows: partitionKeys(pageModel.keys, columns: 5),
            columns: 5,
            rowHeight: isLandscape ? CustomKeyboardMetrics.landscapeButtonHeight : CustomKeyboardMetrics.portraitButtonHeight,
            rowSpacing: isLandscape ? 6 : 8
        )
    }

    private func portraitRowSpecs(for pageModel: KeyboardPage) -> [KeyboardRowSpec]? {
        let keyMap = Dictionary(uniqueKeysWithValues: pageModel.keys.map { ($0.label, $0) })

        func key(_ label: String, span: Int? = nil) -> KeyboardKey {
            guard let base = keyMap[label] else {
                fatalError("Missing keyboard key for label \(label)")
            }
            if let span {
                return base.withSpan(span)
            }
            return base
        }

        switch pageModel.title {
        case "Prog":
            return [
                KeyboardRowSpec(keys: [key("0x"), key("0"), key("2-9"), key("<<"), key("hex")], columns: 5, rowHeight: CustomKeyboardMetrics.portraitButtonHeight),
                KeyboardRowSpec(keys: [key("0b"), key("1"), key("A-F"), key(">>"), key("bin")], columns: 5, rowHeight: CustomKeyboardMetrics.portraitButtonHeight),
                KeyboardRowSpec(keys: [key("bitget", span: 2), key("bitpunch", span: 2), key("to")], columns: 5, rowHeight: CustomKeyboardMetrics.portraitButtonHeight),
                KeyboardRowSpec(keys: [key("a2h"), key("h2a"), key("xor"), key("("), key(")"), key(",")], columns: 6, rowHeight: CustomKeyboardMetrics.portraitButtonHeight),
                KeyboardRowSpec(keys: [key("␣", span: 4), key("⌫"), key("↵")], columns: 6, rowHeight: CustomKeyboardMetrics.portraitButtonHeight),
            ]
        default:
            return nil
        }
    }

    private func landscapeRowSpecs(for pageModel: KeyboardPage) -> [KeyboardRowSpec]? {
        let keyMap = Dictionary(uniqueKeysWithValues: pageModel.keys.map { ($0.label, $0) })

        func key(_ label: String, span: Int? = nil) -> KeyboardKey {
            guard let base = keyMap[label] else {
                fatalError("Missing keyboard key for label \(label)")
            }
            if let span {
                return base.withSpan(span)
            }
            return base
        }

        switch pageModel.title {
        case "Calc":
            return [
                KeyboardRowSpec(keys: [key("7"), key("8"), key("9"), key("+"), key("-"), key("("), key(")")], columns: 7, rowHeight: CustomKeyboardMetrics.landscapeButtonHeight),
                KeyboardRowSpec(keys: [key("4"), key("5"), key("6"), key("*"), key("/"), key("."), key(",")], columns: 7, rowHeight: CustomKeyboardMetrics.landscapeButtonHeight),
                KeyboardRowSpec(keys: [key("1"), key("2"), key("3"), key("="), key("ans"), key("<-"), key("->")], columns: 7, rowHeight: CustomKeyboardMetrics.landscapeButtonHeight),
                KeyboardRowSpec(keys: [key("0"), key("␣", span: 3), key("↵", span: 2), key("⌫", span: 2)], columns: 8, rowHeight: CustomKeyboardMetrics.landscapeButtonHeight),
            ]
        case "Math":
            return [
                KeyboardRowSpec(keys: [key("π"), key("E"), key("e"), key("ENG"), key("√"), key("^"), key("%")], columns: 7, rowHeight: CustomKeyboardMetrics.landscapeButtonHeight),
                KeyboardRowSpec(keys: [key("abs"), key("sin"), key("log"), key("deg"), key("rad"), key("sum")], columns: 6, rowHeight: CustomKeyboardMetrics.landscapeButtonHeight),
                KeyboardRowSpec(keys: [key("min"), key("max"), key("cdf"), key("pdf"), key("rnd")], columns: 5, rowHeight: CustomKeyboardMetrics.landscapeButtonHeight),
            ]
        case "EE":
            return [
                KeyboardRowSpec(keys: [key("vdiv"), key("rpar"), key("findres"), key("findrdiv", span: 2)], columns: 5, rowHeight: CustomKeyboardMetrics.landscapeButtonHeight),
            ]
        case "Prog":
            return [
                KeyboardRowSpec(keys: [key("0x"), key("0b"), key("0"), key("1"), key("2-9"), key("A-F")], columns: 6, rowHeight: CustomKeyboardMetrics.landscapeButtonHeight),
                KeyboardRowSpec(keys: [key("<<"), key(">>"), key("hex"), key("bin"), key("to")], columns: 5, rowHeight: CustomKeyboardMetrics.landscapeButtonHeight),
                KeyboardRowSpec(keys: [key("bitget", span: 2), key("bitpunch", span: 2), key("a2h"), key("h2a"), key("xor")], columns: 7, rowHeight: CustomKeyboardMetrics.landscapeButtonHeight),
                KeyboardRowSpec(keys: [key("("), key(")"), key(","), key("␣", span: 2), key("⌫", span: 2), key("↵")], columns: 8, rowHeight: CustomKeyboardMetrics.landscapeButtonHeight),
            ]
        default:
            return nil
        }
    }

    private func makeRowSpecsPage(_ rowSpecs: [KeyboardRowSpec], rowSpacing: CGFloat) -> UIView {
        let page = UIView()
        page.translatesAutoresizingMaskIntoConstraints = false

        let vertical = UIStackView()
        vertical.translatesAutoresizingMaskIntoConstraints = false
        vertical.axis = .vertical
        vertical.spacing = rowSpacing
        vertical.distribution = .fill

        for spec in rowSpecs {
            vertical.addArrangedSubview(makeButtonRow(spec.keys, columns: spec.columns, rowHeight: spec.rowHeight))
        }

        page.addSubview(vertical)
        NSLayoutConstraint.activate([
            vertical.leadingAnchor.constraint(equalTo: page.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            vertical.trailingAnchor.constraint(equalTo: page.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            vertical.topAnchor.constraint(equalTo: page.topAnchor),
            vertical.bottomAnchor.constraint(lessThanOrEqualTo: page.bottomAnchor),
        ])
        return page
    }

    private func makeCustomGridPage(
        rows: [[KeyboardKey]],
        columns: Int,
        rowHeight: CGFloat,
        rowSpacing: CGFloat
    ) -> UIView {
        let page = UIView()
        page.translatesAutoresizingMaskIntoConstraints = false

        let vertical = UIStackView()
        vertical.translatesAutoresizingMaskIntoConstraints = false
        vertical.axis = .vertical
        vertical.spacing = rowSpacing
        vertical.distribution = .fill

        for rowKeys in rows {
            vertical.addArrangedSubview(makeButtonRow(rowKeys, columns: columns, rowHeight: rowHeight))
        }

        page.addSubview(vertical)
        NSLayoutConstraint.activate([
            vertical.leadingAnchor.constraint(equalTo: page.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            vertical.trailingAnchor.constraint(equalTo: page.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            vertical.topAnchor.constraint(equalTo: page.topAnchor),
            vertical.bottomAnchor.constraint(lessThanOrEqualTo: page.bottomAnchor),
        ])
        return page
    }

    private func partitionKeys(_ keys: [KeyboardKey], columns: Int) -> [[KeyboardKey]] {
        var rows: [[KeyboardKey]] = []
        var currentRow: [KeyboardKey] = []
        var currentWidth = 0

        for key in keys {
            let span = min(columns, key.span)
            if currentWidth + span > columns, !currentRow.isEmpty {
                rows.append(currentRow)
                currentRow = []
                currentWidth = 0
            }
            currentRow.append(key)
            currentWidth += span
        }

        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }

    private func makeButtonRow(_ rowKeys: [KeyboardKey], columns: Int, rowHeight: CGFloat) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true

        var guides: [UILayoutGuide] = []
        for _ in 0..<columns {
            let guide = UILayoutGuide()
            row.addLayoutGuide(guide)
            guides.append(guide)
        }

        let spacing: CGFloat = 8
        for index in guides.indices {
            let guide = guides[index]
            guide.topAnchor.constraint(equalTo: row.topAnchor).isActive = true
            guide.bottomAnchor.constraint(equalTo: row.bottomAnchor).isActive = true

            if index == 0 {
                guide.leadingAnchor.constraint(equalTo: row.leadingAnchor).isActive = true
            } else {
                guide.leadingAnchor.constraint(equalTo: guides[index - 1].trailingAnchor, constant: spacing).isActive = true
                guide.widthAnchor.constraint(equalTo: guides[0].widthAnchor).isActive = true
            }

            if index == guides.count - 1 {
                guide.trailingAnchor.constraint(equalTo: row.trailingAnchor).isActive = true
            }
        }

        var startColumn = 0
        for key in rowKeys {
            let span = min(columns - startColumn, key.span)
            guard span > 0 else { continue }
            let button = makeButton(for: key)
            row.addSubview(button)
            button.leadingAnchor.constraint(equalTo: guides[startColumn].leadingAnchor).isActive = true
            button.trailingAnchor.constraint(equalTo: guides[startColumn + span - 1].trailingAnchor).isActive = true
            button.topAnchor.constraint(equalTo: row.topAnchor).isActive = true
            button.bottomAnchor.constraint(equalTo: row.bottomAnchor).isActive = true
            startColumn += span
        }

        return row
    }

    private func makeConvertPage() -> UIView {
        ConversionPickerPageView(compactLayout: currentOrientationIsLandscape()) { [weak self] token, description in
            self?.setHint(description)
            self?.actionHandler(.insert(token))
        } onInsertTo: { [weak self] in
            self?.setHint("Insert conversion operator")
            self?.actionHandler(.insert(" to "))
        } onInsertText: { [weak self] token, description in
            self?.setHint(description)
            self?.actionHandler(.insert(token))
        } onHintChange: { [weak self] hint in
            self?.setHint(hint)
        }
    }

    private func makeButton(for key: KeyboardKey) -> UIButton {
        let button = ExpandableKeyboardButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(key.label, for: .normal)
        let prominentSymbol = ["⌫", "↵", "␣", "π", "√", "E", "⇧"].contains(key.label)
        button.titleLabel?.font = UIFont.monospacedSystemFont(ofSize: prominentSymbol ? 22 : 16, weight: .semibold)
        button.contentVerticalAlignment = .center
        if key.label == "␣" {
            button.titleEdgeInsets = UIEdgeInsets(top: -3, left: 0, bottom: 3, right: 0)
        }
        let isLabel = key.action == .none && key.menuOptions.isEmpty
        let isShiftKey = key.action == .toggleShift
        let isActiveShiftKey = isShiftKey && isTextShiftEnabled
        button.setTitleColor(isLabel ? ScratchpadStyle.accent : (isActiveShiftKey ? .black : .white), for: .normal)
        button.backgroundColor = isLabel
            ? UIColor(red: 0.20, green: 0.21, blue: 0.22, alpha: 1.0)
            : (isActiveShiftKey ? ScratchpadStyle.accent : UIColor(red: 0.24, green: 0.25, blue: 0.27, alpha: 1.0))
        button.layer.cornerRadius = 10
        button.accessibilityIdentifier = key.label
        if isLabel {
            button.isEnabled = false
        } else {
            button.addAction(UIAction { [weak self, weak button] _ in
                guard let self, let button else { return }
                self.setHint(key.description)
                if key.action == .toggleShift {
                    self.isTextShiftEnabled.toggle()
                    self.rebuildTextPage()
                    return
                }
                if key.action == .none, !key.menuOptions.isEmpty {
                    self.showExpansion(from: button)
                    return
                }
                self.dismissExpansion()
                self.actionHandler(key.action)
                if self.isTextShiftEnabled, self.shouldResetShift(after: key.action) {
                    self.isTextShiftEnabled = false
                    self.rebuildTextPage()
                }
            }, for: .touchUpInside)
            if !key.menuOptions.isEmpty {
                button.expansionOptions = key.menuOptions
                let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleButtonLongPress(_:)))
                longPress.minimumPressDuration = 0.28
                button.addGestureRecognizer(longPress)

                let ellipsis = UILabel()
                ellipsis.translatesAutoresizingMaskIntoConstraints = false
                ellipsis.text = "…"
                ellipsis.font = UIFont.systemFont(ofSize: 12, weight: .bold)
                ellipsis.textColor = UIColor.white.withAlphaComponent(0.75)
                button.addSubview(ellipsis)
                NSLayoutConstraint.activate([
                    ellipsis.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -6),
                    ellipsis.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -3),
                ])
            }
        }
        return button
    }

    @objc private func handleButtonLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard let button = gesture.view as? ExpandableKeyboardButton, !button.expansionOptions.isEmpty else {
            return
        }

        switch gesture.state {
        case .began:
            showExpansion(from: button)
            updateExpansionHighlight(at: gesture.location(in: overlayDismissControl))
        case .changed:
            updateExpansionHighlight(at: gesture.location(in: overlayDismissControl))
        case .ended:
            updateExpansionHighlight(at: gesture.location(in: overlayDismissControl))
            activateHighlightedExpansionOption()
        case .cancelled, .failed:
            dismissExpansion()
        default:
            break
        }
    }

    private func showExpansion(from button: ExpandableKeyboardButton) {
        dismissExpansion()
        overlayDismissControl.isHidden = false

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor(red: 0.20, green: 0.21, blue: 0.22, alpha: 0.98)
        container.layer.cornerRadius = 12
        container.layer.borderWidth = 1
        container.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 6
        stack.distribution = .fillEqually

        activeExpansionOptionButtons = []
        highlightedExpansionOptionButton = nil

        for option in button.expansionOptions {
            let optionButton = ExpansionOptionButton(type: .system)
            optionButton.optionKey = option
            optionButton.translatesAutoresizingMaskIntoConstraints = false
            optionButton.setTitle(option.label, for: .normal)
            optionButton.titleLabel?.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .semibold)
            optionButton.setTitleColor(.white, for: .normal)
            optionButton.backgroundColor = UIColor(red: 0.24, green: 0.25, blue: 0.27, alpha: 1.0)
            optionButton.layer.cornerRadius = 10
            optionButton.addAction(UIAction { [weak self] _ in
                self?.selectExpansionOption(option)
            }, for: .touchUpInside)
            activeExpansionOptionButtons.append(optionButton)
            stack.addArrangedSubview(optionButton)
        }

        container.addSubview(stack)
        overlayDismissControl.addSubview(container)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            container.heightAnchor.constraint(equalToConstant: 54),
        ])

        let sourceFrame = button.convert(button.bounds, to: overlayDismissControl)
        let optionCount = CGFloat(button.expansionOptions.count)
        let preferredWidth = max(sourceFrame.width, optionCount * 64 + max(0, optionCount - 1) * 6 + 12)
        let clampedWidth = min(preferredWidth, bounds.width - 16)
        let centeredX = sourceFrame.midX - clampedWidth / 2
        let leading = max(8, min(centeredX, bounds.width - clampedWidth - 8))
        let top = max(8, sourceFrame.minY - 58)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: overlayDismissControl.leadingAnchor, constant: leading),
            container.topAnchor.constraint(equalTo: overlayDismissControl.topAnchor, constant: top),
            container.widthAnchor.constraint(equalToConstant: clampedWidth),
        ])

        activeExpansionView = container
        overlayDismissControl.layoutIfNeeded()
    }

    private func dismissExpansion() {
        activeExpansionView?.removeFromSuperview()
        activeExpansionView = nil
        activeExpansionOptionButtons = []
        highlightedExpansionOptionButton = nil
        overlayDismissControl.isHidden = true
    }

    private func updateExpansionHighlight(at point: CGPoint) {
        guard !activeExpansionOptionButtons.isEmpty else {
            return
        }

        let matchingButton = activeExpansionOptionButtons.first { optionButton in
            let frame = optionButton.convert(optionButton.bounds, to: overlayDismissControl).insetBy(dx: -6, dy: -10)
            return frame.contains(point)
        }

        guard matchingButton !== highlightedExpansionOptionButton else {
            return
        }

        if let previousButton = highlightedExpansionOptionButton {
            setExpansionOptionButton(previousButton, highlighted: false)
        }

        highlightedExpansionOptionButton = matchingButton

        if let matchingButton {
            setExpansionOptionButton(matchingButton, highlighted: true)
            if let option = matchingButton.optionKey {
                setHint(option.description)
            }
        }
    }

    private func activateHighlightedExpansionOption() {
        guard let option = highlightedExpansionOptionButton?.optionKey else {
            dismissExpansion()
            return
        }
        selectExpansionOption(option)
    }

    private func selectExpansionOption(_ option: KeyboardKey) {
        setHint(option.description)
        dismissExpansion()
        actionHandler(option.action)
    }

    private func setExpansionOptionButton(_ button: ExpansionOptionButton, highlighted: Bool) {
        button.backgroundColor = highlighted
            ? ScratchpadStyle.accent
            : UIColor(red: 0.24, green: 0.25, blue: 0.27, alpha: 1.0)
        button.setTitleColor(highlighted ? .black : .white, for: .normal)
    }

    private func shouldResetShift(after action: KeyboardAction) -> Bool {
        switch action {
        case let .insert(token):
            return token.count == 1 && token.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
        default:
            return false
        }
    }

    private func setHint(_ text: String) {
        hintLabel.text = text
    }

    private func defaultHint(for page: Int) -> String {
        switch page {
        case 0:
            return "Text keyboard for variables, comments, and strings"
        case 1:
            return "Calculator keys and editing controls"
        case 2:
            return "Math symbols, trig, logs, rounding, and engineering notation"
        case 3:
            return "Choose a unit type and unit to build conversions"
        case 4:
            return "Electrical helpers and common resistor values"
        case 5:
            return "Programming prefixes, bitwise ops, and converters"
        default:
            return ""
        }
    }

    func setPage(_ page: Int, animated: Bool) {
        dismissExpansion()
        let clamped = max(0, min(page, customKeyboardPageCount - 1))
        currentPage = clamped
        if segmentedControl.selectedSegmentIndex != clamped {
            segmentedControl.selectedSegmentIndex = clamped
        }
        let xOffset = CGFloat(clamped) * scrollView.bounds.width
        scrollView.setContentOffset(CGPoint(x: xOffset, y: 0), animated: animated)
        setHint(defaultHint(for: clamped))
        hintLabel.isHidden = false
        hintHeightConstraint?.constant = 18
        scrollViewTopConstraint?.constant = 6
        onPageChange(clamped)
    }
}

extension MonsterKeyboardView: UIScrollViewDelegate {
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let page = Int(round(scrollView.contentOffset.x / max(scrollView.bounds.width, 1)))
        currentPage = max(0, min(page, customKeyboardPageCount - 1))
        onPageChange(max(0, min(page, customKeyboardPageCount - 1)))
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        scrollViewDidEndDecelerating(scrollView)
    }
}

final class ConversionPickerPageView: UIView, UIPickerViewDataSource, UIPickerViewDelegate {
    private let typePicker = UIPickerView()
    private let unitPicker = UIPickerView()
    private let onInsertUnit: (String, String) -> Void
    private let onInsertTo: () -> Void
    private let onInsertText: (String, String) -> Void
    private let onHintChange: (String) -> Void
    private var selectedCategoryIndex = 0
    private var selectedUnitIndexes: [Int] = Array(repeating: 0, count: conversionCategories.count)
    private let compactLayout: Bool

    init(
        compactLayout: Bool,
        onInsertUnit: @escaping (String, String) -> Void,
        onInsertTo: @escaping () -> Void,
        onInsertText: @escaping (String, String) -> Void,
        onHintChange: @escaping (String) -> Void
    ) {
        self.compactLayout = compactLayout
        self.onInsertUnit = onInsertUnit
        self.onInsertTo = onInsertTo
        self.onInsertText = onInsertText
        self.onHintChange = onHintChange
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setup()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private func setup() {
        let pickerRow = UIStackView()
        pickerRow.translatesAutoresizingMaskIntoConstraints = false
        pickerRow.axis = .horizontal
        pickerRow.spacing = compactLayout ? 6 : 8
        pickerRow.distribution = .fillEqually

        configurePicker(typePicker, tag: 0)
        configurePicker(unitPicker, tag: 1)
        pickerRow.addArrangedSubview(typePicker)
        pickerRow.addArrangedSubview(unitPicker)

        let buttonsRow = UIStackView()
        buttonsRow.translatesAutoresizingMaskIntoConstraints = false
        buttonsRow.axis = .horizontal
        buttonsRow.spacing = compactLayout ? 8 : 10
        buttonsRow.distribution = .fillEqually

        let toButton = makeActionButton(title: "Insert to") { [weak self] in
            self?.onInsertTo()
        }
        let unitButton = makeActionButton(title: "Insert Unit") { [weak self] in
            guard let self else { return }
            let unit = conversionCategories[self.selectedCategoryIndex].units[self.selectedUnitIndexes[self.selectedCategoryIndex]]
            self.onInsertUnit(unit.token, "\(conversionCategories[self.selectedCategoryIndex].title): \(unit.label)")
        }
        buttonsRow.addArrangedSubview(toButton)
        buttonsRow.addArrangedSubview(unitButton)

        let keypadStack = UIStackView()
        keypadStack.translatesAutoresizingMaskIntoConstraints = false
        keypadStack.axis = .vertical
        keypadStack.spacing = compactLayout ? 2 : 6
        keypadStack.distribution = .fillEqually

        let keypadRows: [[String]] = [
            ["7", "8", "9"],
            ["4", "5", "6"],
            ["1", "2", "3"],
            ["0", ".", ""],
        ]

        for rowValues in keypadRows {
            let row = UIStackView()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.axis = .horizontal
            row.spacing = compactLayout ? 6 : 8
            row.distribution = .fillEqually

            for value in rowValues {
                if value.isEmpty {
                    let spacer = UIView()
                    spacer.translatesAutoresizingMaskIntoConstraints = false
                    row.addArrangedSubview(spacer)
                } else {
                    let title = value
                    let button = makeActionButton(title: title) { [weak self] in
                        self?.onInsertText(title, title == "." ? "Insert decimal point" : "Insert \(title)")
                    }
                    row.addArrangedSubview(button)
                }
            }

            keypadStack.addArrangedSubview(row)
        }

        if compactLayout {
            let leftColumn = UIStackView()
            leftColumn.translatesAutoresizingMaskIntoConstraints = false
            leftColumn.axis = .vertical
            leftColumn.spacing = 4
            leftColumn.distribution = .fill
            leftColumn.addArrangedSubview(pickerRow)
            leftColumn.addArrangedSubview(buttonsRow)

            let contentRow = UIStackView()
            contentRow.translatesAutoresizingMaskIntoConstraints = false
            contentRow.axis = .horizontal
            contentRow.spacing = 8
            contentRow.distribution = .fill

            addSubview(contentRow)
            contentRow.addArrangedSubview(leftColumn)
            contentRow.addArrangedSubview(keypadStack)

            NSLayoutConstraint.activate([
                pickerRow.heightAnchor.constraint(equalToConstant: 54),
                buttonsRow.heightAnchor.constraint(equalToConstant: 24),
                keypadStack.widthAnchor.constraint(equalTo: contentRow.widthAnchor, multiplier: 0.34),

                contentRow.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 8),
                contentRow.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -8),
                contentRow.topAnchor.constraint(equalTo: topAnchor, constant: 2),
                contentRow.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -2),
            ])
        } else {
            addSubview(pickerRow)
            addSubview(buttonsRow)
            addSubview(keypadStack)

            NSLayoutConstraint.activate([
                pickerRow.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 8),
                pickerRow.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -8),
                pickerRow.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                pickerRow.heightAnchor.constraint(equalToConstant: 82),

                buttonsRow.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 10),
                buttonsRow.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -10),
                buttonsRow.topAnchor.constraint(equalTo: pickerRow.bottomAnchor, constant: 4),
                buttonsRow.heightAnchor.constraint(equalToConstant: 32),

                keypadStack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 22),
                keypadStack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -22),
                keypadStack.topAnchor.constraint(equalTo: buttonsRow.bottomAnchor, constant: 4),
                keypadStack.heightAnchor.constraint(equalToConstant: 138),
                keypadStack.bottomAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor, constant: -2),
            ])
        }

        typePicker.selectRow(0, inComponent: 0, animated: false)
        unitPicker.selectRow(0, inComponent: 0, animated: false)
        onHintChange("Choose a unit family and target unit")
    }

    private func configurePicker(_ picker: UIPickerView, tag: Int) {
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.backgroundColor = UIColor(red: 0.20, green: 0.21, blue: 0.22, alpha: 1.0)
        picker.layer.cornerRadius = 10
        picker.clipsToBounds = true
        picker.tag = tag
        picker.dataSource = self
        picker.delegate = self
    }

    private func makeActionButton(title: String, handler: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.monospacedSystemFont(ofSize: compactLayout ? 14 : 15, weight: .semibold)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.72
        button.contentEdgeInsets = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(red: 0.24, green: 0.25, blue: 0.27, alpha: 1.0)
        button.layer.cornerRadius = 10
        button.addAction(UIAction { _ in handler() }, for: .touchUpInside)
        return button
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        1
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        if pickerView === typePicker {
            return conversionCategories.count
        }
        return conversionCategories[selectedCategoryIndex].units.count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        if pickerView === typePicker {
            return conversionCategories[row].title
        }
        return conversionCategories[selectedCategoryIndex].units[row].label
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if pickerView === typePicker {
            selectedCategoryIndex = row
            unitPicker.reloadAllComponents()
            let selectedUnit = min(selectedUnitIndexes[row], max(0, conversionCategories[row].units.count - 1))
            unitPicker.selectRow(selectedUnit, inComponent: 0, animated: true)
            let unit = conversionCategories[row].units[selectedUnit]
            onHintChange("\(conversionCategories[row].title): \(unit.label)")
        } else {
            selectedUnitIndexes[selectedCategoryIndex] = row
            let unit = conversionCategories[selectedCategoryIndex].units[row]
            onHintChange("\(conversionCategories[selectedCategoryIndex].title): \(unit.label)")
        }
    }
}

private enum ScratchpadStyle {
    static let font = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
    static let numberFont = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
    static let insets = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
    static let gutterInsets = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 6)
    static let extraBottomScrollInset = ceil(font.lineHeight * 2)
    static let background = UIColor(red: 0.14, green: 0.145, blue: 0.153, alpha: 1.0)
    static let gutterBackground = UIColor(red: 0.12, green: 0.125, blue: 0.132, alpha: 1.0)
    static let text = UIColor.white
    static let secondaryText = UIColor(red: 0.78, green: 0.81, blue: 0.84, alpha: 1.0)
    static let accent = UIColor(red: 0.62, green: 0.68, blue: 0.26, alpha: 1.0)
    static let divider = UIColor.white.withAlphaComponent(0.08)
    static let functionColor = UIColor(red: 1.0, green: 0.82, blue: 0.40, alpha: 1.0)
    static let operatorColor = UIColor(red: 0.48, green: 0.87, blue: 0.95, alpha: 1.0)
    static let userSymbolColor = UIColor(red: 1.0, green: 0.62, blue: 0.41, alpha: 1.0)
    static let symbolColor = UIColor(red: 1.0, green: 0.42, blue: 0.54, alpha: 1.0)
    static let commentColor = UIColor(red: 0.56, green: 0.60, blue: 0.64, alpha: 1.0)
    static let unitColor = UIColor(red: 0.61, green: 0.90, blue: 0.39, alpha: 1.0)
    static let stringColor = UIColor(red: 0.73, green: 0.84, blue: 1.0, alpha: 1.0)
}

private let functionNames = [
    "floor", "ceil", "min", "max", "sum", "sqrt", "abs", "log", "log10", "log2", "exp",
    "sin", "cos", "tan", "asin", "acos", "atan", "rad", "deg", "cdf", "pdf", "findres",
    "findrdiv",
    "vdiv", "rpar", "hex", "bin", "bitget", "bitpunch", "a2h", "h2a",
]

private let symbolNames = ["ans", "pi", "e"]
private let unitNames = [
    "mm", "cm", "m", "km", "mil", "in", "mL", "L", "tsp", "tbl", "oz", "pt", "qt",
    "gal", "mg", "g", "kg", "lbs", "N", "kN", "lbf", "C", "F", "bits", "bytes",
    "KB", "MB", "GB", "TB", "Kb", "Mb", "Gb", "Tb",
]

private struct InlineCompletionHint {
    let ghostText: String
}

private let inlineFunctionSignatures: [String: String] = [
    "floor": "(value)",
    "ceil": "(value)",
    "min": "(value1, value2, ...)",
    "max": "(value1, value2, ...)",
    "sum": "(list)",
    "sqrt": "(value)",
    "abs": "(value)",
    "log": "(value)",
    "log10": "(value)",
    "log2": "(value)",
    "exp": "(value)",
    "sin": "(angle)",
    "cos": "(angle)",
    "tan": "(angle)",
    "asin": "(value)",
    "acos": "(value)",
    "atan": "(value)",
    "rad": "(deg)",
    "deg": "(rad)",
    "cdf": "(std_dev)",
    "pdf": "(std_dev)",
    "vdiv": "(vin, R1, R2)",
    "rpar": "(R1, R2)",
    "findres": "(value)",
    "findrdiv": "(vin, vout, tol)",
    "hex": "(value)",
    "bin": "(value)",
    "bitget": "(value, msb, lsb)",
    "bitpunch": "(value, bit, state)",
    "a2h": "(\"text\")",
    "h2a": "(value)",
]

private func findInlineCompletionHint(
    lineText: String,
    cursorColumn: Int,
    signatures: [String: String]
) -> InlineCompletionHint? {
    let safeColumn = min(max(0, cursorColumn), lineText.count)
    let beforeCursor = String(lineText.prefix(safeColumn))
    let afterCursor = String(lineText.dropFirst(safeColumn))

    if let first = afterCursor.first, first.isLetter || first.isNumber || first == "_" {
        return nil
    }

    if let callHint = findCallArgumentHint(beforeCursor: beforeCursor, afterCursor: afterCursor, signatures: signatures) {
        return callHint
    }

    guard let fragment = trailingToken(in: beforeCursor), fragment.count >= 3 else {
        return nil
    }

    let matches = signatures.keys.filter { $0.hasPrefix(fragment) }.sorted()
    guard matches.count == 1, let token = matches.first, let signature = signatures[token] else {
        return nil
    }

    if fragment == token {
        return InlineCompletionHint(ghostText: signature)
    }

    return InlineCompletionHint(ghostText: String(token.dropFirst(fragment.count)) + signature)
}

private func findCallArgumentHint(
    beforeCursor: String,
    afterCursor: String,
    signatures: [String: String]
) -> InlineCompletionHint? {
    if !afterCursor.isEmpty && !afterCursor.allSatisfy(\.isWhitespace) {
        return nil
    }

    guard let (token, argumentText) = findOpenCall(beforeCursor: beforeCursor, signatures: signatures),
          let signature = signatures[token],
          let remaining = remainingSignature(signature: signature, argumentText: argumentText)
    else {
        return nil
    }

    return InlineCompletionHint(ghostText: remaining)
}

private func findOpenCall(
    beforeCursor: String,
    signatures: [String: String]
) -> (String, String)? {
    let characters = Array(beforeCursor)
    var depth = 0

    for index in stride(from: characters.count - 1, through: 0, by: -1) {
        let character = characters[index]
        if character == ")" {
            depth += 1
        } else if character == "(" {
            if depth > 0 {
                depth -= 1
                continue
            }

            let prefix = String(characters[..<index]).trimmingCharacters(in: .whitespaces)
            guard let token = trailingToken(in: prefix), signatures[token] != nil else {
                return nil
            }
            return (token, String(characters[(index + 1)...]))
        }
    }

    return nil
}

private func remainingSignature(signature: String, argumentText: String) -> String? {
    guard signature.first == "(", signature.last == ")" else {
        return nil
    }

    let params = signature
        .dropFirst()
        .dropLast()
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

    guard !params.isEmpty else {
        return nil
    }

    let (argumentIndex, currentFragment) = argumentProgress(argumentText)
    guard argumentIndex < params.count else {
        return nil
    }

    if !currentFragment.isEmpty {
        let nextIndex = argumentIndex + 1
        guard nextIndex < params.count else {
            return nil
        }
        return ", " + params[nextIndex...].joined(separator: ", ") + ")"
    }

    return params[argumentIndex...].joined(separator: ", ") + ")"
}

private func argumentProgress(_ argumentText: String) -> (Int, String) {
    var depth = 0
    var argumentIndex = 0
    var current: [Character] = []

    for character in argumentText {
        if character == "," && depth == 0 {
            argumentIndex += 1
            current.removeAll(keepingCapacity: true)
            continue
        }
        if character == "(" {
            depth += 1
        } else if character == ")" && depth > 0 {
            depth -= 1
        }
        current.append(character)
    }

    return (argumentIndex, String(current).trimmingCharacters(in: .whitespacesAndNewlines))
}

private func trailingToken(in text: String) -> String? {
    var token: [Character] = []

    for character in text.reversed() {
        if character.isLetter || character.isNumber || character == "_" {
            token.append(character)
        } else {
            break
        }
    }

    guard !token.isEmpty else {
        return nil
    }

    let value = String(token.reversed())
    guard let first = value.first, first.isLetter || first == "_" else {
        return nil
    }
    return value
}

private func autoCloseFunctionCallIfNeeded(
    text: String,
    cursorLocation: Int,
    signatures: [String: String],
    insertedToken: String? = nil
) -> (text: String, cursorLocation: Int)? {
    let safeCursor = min(max(0, cursorLocation), text.count)
    let beforeCursor = String(text.prefix(safeCursor))
    let afterCursor = String(text.dropFirst(safeCursor))

    if afterCursor.hasPrefix(")") {
        return nil
    }

    guard let (token, argumentText) = findOpenCall(beforeCursor: beforeCursor, signatures: signatures),
          let signature = signatures[token],
          let arity = fixedArity(for: signature)
    else {
        return nil
    }

    let (argumentIndex, currentFragment) = argumentProgress(argumentText)
    guard argumentIndex == arity - 1 else {
        return nil
    }

    let shouldInsertImmediately =
        !currentFragment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (insertedToken != nil || !afterCursor.isEmpty || trailingDelimiterSuffixStart(in: beforeCursor) != nil || isCompleteArgumentFragment(currentFragment))

    guard shouldInsertImmediately else {
        return nil
    }

    let updatedBeforeCursor = beforeCursor + ")"
    return (updatedBeforeCursor + afterCursor, safeCursor)
}

private func trailingDelimiterSuffixStart(in text: String) -> Int? {
    let characters = Array(text)
    var index = characters.count

    while index > 0 && isAutoCloseDelimiter(characters[index - 1]) {
        index -= 1
    }

    return index == characters.count ? nil : index
}

private func isAutoCloseDelimiter(_ character: Character) -> Bool {
    if character.isWhitespace {
        return true
    }
    return "+-*/%=&|^<>".contains(character)
}

private func shouldAllowImmediateAutoClose(forInsertedToken token: String) -> Bool {
    guard !token.isEmpty else {
        return false
    }

    if token.count > 1 {
        return true
    }

    guard let character = token.first else {
        return false
    }

    if character.isWhitespace {
        return true
    }

    return !character.isLetter && !character.isNumber && character != "_"
}

private func fixedArity(for signature: String) -> Int? {
    guard !signature.contains("..."),
          signature.first == "(",
          signature.last == ")"
    else {
        return nil
    }

    let params = signature
        .dropFirst()
        .dropLast()
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

    return params.isEmpty ? nil : params.count
}

private func isCompleteArgumentFragment(_ fragment: String) -> Bool {
    let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return false
    }

    if let last = trimmed.last, "+-*/%=&|^<>,(".contains(last) {
        return false
    }

    var depth = 0
    var inString = false
    var escaped = false

    for character in trimmed {
        if escaped {
            escaped = false
            continue
        }
        if character == "\\" {
            escaped = true
            continue
        }
        if character == "\"" {
            inString.toggle()
            continue
        }
        if inString {
            continue
        }
        if character == "(" {
            depth += 1
        } else if character == ")" {
            depth -= 1
        }
    }

    return depth == 0 && !inString
}

struct ScratchpadTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var pendingInsertion: String?
    @Binding var scrollOffset: CGFloat
    @Binding var inputMode: EditorInputMode
    let scrollBridge: ScrollSyncBridge

    func makeUIView(context: Context) -> EditorContainerView {
        let container = EditorContainerView()
        container.textView.delegate = context.coordinator
        context.coordinator.install(in: container, scrollBridge: scrollBridge)
        context.coordinator.applyInputMode(inputMode, in: container)
        context.coordinator.applyText(text, to: container.textView)
        context.coordinator.updateLineNumbers(in: container, text: text)
        context.coordinator.refreshInlineHint(in: container)
        return container
    }

    func updateUIView(_ uiView: EditorContainerView, context: Context) {
        if uiView.textView.text != text {
            context.coordinator.applyText(text, to: uiView.textView)
            context.coordinator.updateLineNumbers(in: uiView, text: text)
            context.coordinator.refreshInlineHint(in: uiView)
        }

        scrollBridge.registerEditor(textView: uiView.textView, gutterView: uiView.gutterView)
        context.coordinator.syncVerticalOffset(in: uiView, to: scrollOffset)

        if let token = pendingInsertion, !context.coordinator.isApplyingInsertion {
            context.coordinator.isApplyingInsertion = true
            DispatchQueue.main.async {
                context.coordinator.insertToken(token, into: uiView)
                self.pendingInsertion = nil
                context.coordinator.isApplyingInsertion = false
            }
        }

        if context.coordinator.inputMode != inputMode {
            context.coordinator.applyInputMode(inputMode, in: uiView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, scrollOffset: $scrollOffset, inputMode: $inputMode)
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        @Binding private var text: String
        @Binding private var scrollOffset: CGFloat
        @Binding private var inputModeBinding: EditorInputMode
        private weak var container: EditorContainerView?
        private weak var scrollBridge: ScrollSyncBridge?
        private var isApplyingHighlight = false
        var isApplyingInsertion = false
        var inputMode: EditorInputMode
        private weak var customKeyboard: MonsterKeyboardView?
        private weak var customKeyboardHost: MonsterKeyboardHostView?
        private var orientationObserver: NSObjectProtocol?
        private var contentOffsetObserver: NSKeyValueObservation?
        private weak var horizontalPanRecognizer: UIPanGestureRecognizer?
        private weak var emptyEditorTapRecognizer: UITapGestureRecognizer?
        private var horizontalPanStartOffsetX: CGFloat = 0
        private let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")

        init(text: Binding<String>, scrollOffset: Binding<CGFloat>, inputMode: Binding<EditorInputMode>) {
            _text = text
            _scrollOffset = scrollOffset
            _inputModeBinding = inputMode
            self.inputMode = inputMode.wrappedValue
        }

        deinit {
            if let orientationObserver {
                NotificationCenter.default.removeObserver(orientationObserver)
            }
            contentOffsetObserver?.invalidate()
        }

        func install(in container: EditorContainerView, scrollBridge: ScrollSyncBridge) {
            self.container = container
            self.scrollBridge = scrollBridge
            scrollBridge.registerEditor(textView: container.textView, gutterView: container.gutterView)
            container.textView.onPreferredWidthChange = { [weak container] width in
                container?.updateEditorWidth(width)
            }
            if horizontalPanRecognizer == nil {
                let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handleHorizontalPan(_:)))
                panRecognizer.delegate = self
                panRecognizer.cancelsTouchesInView = false
                container.editorScrollView.addGestureRecognizer(panRecognizer)
                horizontalPanRecognizer = panRecognizer
            }
            if emptyEditorTapRecognizer == nil {
                let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleEmptyEditorTap(_:)))
                tapRecognizer.delegate = self
                tapRecognizer.cancelsTouchesInView = false
                container.editorScrollView.addGestureRecognizer(tapRecognizer)
                emptyEditorTapRecognizer = tapRecognizer
            }
            contentOffsetObserver?.invalidate()
            contentOffsetObserver = container.textView.observe(\.contentOffset, options: [.initial, .new]) { [weak self] textView, _ in
                guard let self else { return }
                self.handleEditorScrollOffsetChange(textView.contentOffset.y)
            }
            if orientationObserver == nil {
                orientationObserver = NotificationCenter.default.addObserver(
                    forName: UIDevice.orientationDidChangeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    guard let self, let container = self.container else { return }
                    self.customKeyboardHost?.refreshHeight()
                    if container.textView.isFirstResponder {
                        container.textView.reloadInputViews()
                    }
                }
            }
        }

        func applyInputMode(_ mode: EditorInputMode, in container: EditorContainerView) {
            inputMode = mode
            inputModeBinding = mode
            let keyboard = customKeyboard ?? MonsterKeyboardView(
                actionHandler: { [weak self, weak container] action in
                    guard let self, let container else { return }
                    self.handleKeyboardAction(action, in: container)
                },
                onPageChange: { [weak self] page in
                    self?.syncInputModeFromPage(page)
                },
                onDismissKeyboard: { [weak container] in
                    container?.textView.resignFirstResponder()
                }
            )
            let keyboardHost = customKeyboardHost ?? MonsterKeyboardHostView(keyboardView: keyboard)
            customKeyboard = keyboard
            customKeyboardHost = keyboardHost
            keyboardHost.refreshHeight()
            container.textView.inputView = keyboardHost
            container.textView.inputAccessoryView = nil
            keyboard.layoutIfNeeded()
            keyboard.setPage(mode.keyboardPageIndex, animated: false)
            container.textView.inputAssistantItem.leadingBarButtonGroups = []
            container.textView.inputAssistantItem.trailingBarButtonGroups = []
            if container.textView.isFirstResponder {
                container.textView.reloadInputViews()
            }
        }

        private func syncInputModeFromPage(_ page: Int) {
            let nextMode: EditorInputMode
            switch page {
            case 0:
                nextMode = .system
            case 1:
                nextMode = .calc
            case 2:
                nextMode = .math
            case 3:
                nextMode = .convert
            case 4:
                nextMode = .ee
            default:
                nextMode = .prog
            }
            inputMode = nextMode
            inputModeBinding = nextMode
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingHighlight else { return }
            var updatedText = textView.text ?? ""
            if textView.markedTextRange != nil {
                text = updatedText
                if let container {
                    updateLineNumbers(in: container, text: updatedText)
                    refreshInlineHint(in: container)
                }
                return
            }
            if let autoClosed = autoCloseFunctionCallIfNeeded(
                text: updatedText,
                cursorLocation: textView.selectedRange.location,
                signatures: inlineFunctionSignatures
            ) {
                updatedText = autoClosed.text
                textView.text = updatedText
                textView.selectedRange = NSRange(location: autoClosed.cursorLocation, length: 0)
            }
            applyText(updatedText, to: textView)
            text = updatedText
            if let container {
                updateLineNumbers(in: container, text: updatedText)
                refreshInlineHint(in: container)
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            updateEditorAccessibilityDebugState(for: textView)
            guard let container else { return }
            refreshInlineHint(in: container)
        }

        func textViewDidScroll(_ textView: UITextView) {
            updateEditorAccessibilityDebugState(for: textView)
            guard let container else { return }
            refreshInlineHint(in: container)
        }

        @objc private func handleHorizontalPan(_ gesture: UIPanGestureRecognizer) {
            guard let container else {
                return
            }

            let scrollView = container.editorScrollView
            let maxHorizontalOffset = max(0, scrollView.contentSize.width - scrollView.bounds.width)
            guard maxHorizontalOffset > 0 else {
                return
            }

            switch gesture.state {
            case .began:
                horizontalPanStartOffsetX = scrollView.contentOffset.x
            case .changed:
                let translation = gesture.translation(in: scrollView)
                let targetX = min(max(horizontalPanStartOffsetX - translation.x, 0), maxHorizontalOffset)
                scrollView.setContentOffset(CGPoint(x: targetX, y: scrollView.contentOffset.y), animated: false)
                container.textView.layoutManager.ensureLayout(for: container.textView.textContainer)
                container.textView.setNeedsDisplay()
                updateEditorAccessibilityDebugState(for: container.textView)
                refreshInlineHint(in: container)
            default:
                break
            }
        }

        @objc private func handleEmptyEditorTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let container else {
                return
            }

            let textView = container.textView
            guard (textView.text ?? "").isEmpty else {
                return
            }

            textView.becomeFirstResponder()
            textView.selectedRange = NSRange(location: 0, length: 0)
            refreshInlineHint(in: container)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === horizontalPanRecognizer,
               let panGesture = gestureRecognizer as? UIPanGestureRecognizer,
               let scrollView = panGesture.view as? UIScrollView {
                let velocity = panGesture.velocity(in: scrollView)
                let isHorizontal = abs(velocity.x) > abs(velocity.y)
                let hasHorizontalOverflow = scrollView.contentSize.width > scrollView.bounds.width + 1
                return isHorizontal && hasHorizontalOverflow
            }

            if gestureRecognizer === emptyEditorTapRecognizer {
                return (container?.textView.text ?? "").isEmpty
            }

            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer === horizontalPanRecognizer || gestureRecognizer === emptyEditorTapRecognizer
        }

        func insertToken(_ token: String, into container: EditorContainerView) {
            let textView = container.textView
            if let range = textView.selectedTextRange {
                textView.replace(range, withText: token)
            } else {
                textView.insertText(token)
            }
            var updatedText = textView.text ?? ""
            if let autoClosed = autoCloseFunctionCallIfNeeded(
                text: updatedText,
                cursorLocation: textView.selectedRange.location,
                signatures: inlineFunctionSignatures,
                insertedToken: token
            ) {
                updatedText = autoClosed.text
                textView.text = updatedText
                textView.selectedRange = NSRange(location: autoClosed.cursorLocation, length: 0)
            }
            applyText(updatedText, to: textView)
            updateLineNumbers(in: container, text: updatedText)
            text = updatedText
            refreshInlineHint(in: container)
        }

        fileprivate func handleKeyboardAction(_ action: KeyboardAction, in container: EditorContainerView) {
            let textView = container.textView
            switch action {
            case let .insert(token):
                insertToken(token, into: container)
            case .newline:
                handleSmartNewline(in: container)
            case .backspace:
                textView.deleteBackward()
                let updatedText = textView.text ?? ""
                applyText(updatedText, to: textView)
                updateLineNumbers(in: container, text: updatedText)
                text = updatedText
                refreshInlineHint(in: container)
            case .clearLine:
                clearCurrentLine(in: container)
            case .clearAll:
                clearScratchpad(in: container)
            case .toggleShift:
                break
            case .moveLeft:
                moveCaret(in: textView, delta: -1)
            case .moveRight:
                moveCaret(in: textView, delta: 1)
            case .none:
                break
            }
        }

        func updateLineNumbers(in container: EditorContainerView, text: String) {
            let lineCount = max(1, text.components(separatedBy: "\n").count)
            container.gutterView.text = (1...lineCount).map(String.init).joined(separator: "\n")
        }

        func applyText(_ text: String, to textView: UITextView) {
            let selectedRange = textView.selectedRange
            let contentOffset = textView.contentOffset
            isApplyingHighlight = true
            if textView.text != text {
                textView.text = text
            }
            applyHighlighting(to: textView.textStorage, text: text)
            let length = textView.textStorage.length
            textView.selectedRange = NSRange(
                location: min(selectedRange.location, length),
                length: min(selectedRange.length, max(0, length - min(selectedRange.location, length)))
            )
            textView.typingAttributes = [
                .font: ScratchpadStyle.font,
                .foregroundColor: ScratchpadStyle.text,
            ]
            textView.setContentOffset(CGPoint(x: 0, y: max(0, contentOffset.y)), animated: false)
            textView.layoutIfNeeded()
            keepCaretVisible(in: textView)
            updateEditorAccessibilityDebugState(for: textView)
            if let container {
                syncVerticalOffset(in: container, to: textView.contentOffset.y)
            }
            isApplyingHighlight = false
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                textView.layoutIfNeeded()
                self.keepCaretVisible(in: textView)
                self.updateEditorAccessibilityDebugState(for: textView)
                if let container = self.container {
                    self.refreshInlineHint(in: container)
                }
            }
        }

        func syncVerticalOffset(in container: EditorContainerView, to offset: CGFloat) {
            let targetOffset = clampedVerticalOffset(offset, in: container.textView)
            if abs(container.textView.contentOffset.y - targetOffset) > 0.5 {
                container.textView.setContentOffset(
                    CGPoint(x: container.textView.contentOffset.x, y: targetOffset),
                    animated: false
                )
            }
            if abs(container.gutterView.contentOffset.y - targetOffset) > 0.5 {
                container.gutterView.setContentOffset(CGPoint(x: 0, y: targetOffset), animated: false)
            }
        }

        private func handleEditorScrollOffsetChange(_ offset: CGFloat) {
            guard let container else { return }
            let targetOffset = clampedVerticalOffset(offset, in: container.textView)
            if abs(container.gutterView.contentOffset.y - targetOffset) > 0.5 {
                container.gutterView.setContentOffset(CGPoint(x: 0, y: targetOffset), animated: false)
            }
            scrollBridge?.syncVerticalOffset(targetOffset, source: container.textView)
            updateEditorAccessibilityDebugState(for: container.textView)
            if abs(scrollOffset - targetOffset) > 0.5 {
                scrollOffset = targetOffset
            }
        }

        func refreshInlineHint(in container: EditorContainerView) {
            let textView = container.textView
            let label = container.completionLabel

            guard textView.isFirstResponder, textView.markedTextRange == nil else {
                label.isHidden = true
                return
            }

            let selectedRange = textView.selectedRange
            guard selectedRange.length == 0 else {
                label.isHidden = true
                return
            }

            let text = textView.text ?? ""
            let nsText = text as NSString
            let cursorLocation = min(selectedRange.location, nsText.length)

            var lineStart = 0
            var lineContentsEnd = 0
            nsText.getLineStart(&lineStart, end: nil, contentsEnd: &lineContentsEnd, for: NSRange(location: cursorLocation, length: 0))

            let lineRange = NSRange(location: lineStart, length: max(0, lineContentsEnd - lineStart))
            let lineText = nsText.substring(with: lineRange)
            let cursorColumn = cursorLocation - lineStart

            guard let completion = findInlineCompletionHint(
                lineText: lineText,
                cursorColumn: cursorColumn,
                signatures: inlineFunctionSignatures
            ),
            let selectedTextRange = textView.selectedTextRange
            else {
                label.isHidden = true
                return
            }

            let caretRect = textView.caretRect(for: selectedTextRange.end)
            label.text = completion.ghostText
            label.font = ScratchpadStyle.font
            label.sizeToFit()
            label.frame = CGRect(
                x: caretRect.maxX + 1,
                y: caretRect.minY,
                width: label.bounds.width,
                height: max(label.bounds.height, caretRect.height)
            )
            label.isHidden = false
        }

        private func applyHighlighting(to storage: NSTextStorage, text: String) {
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            storage.beginEditing()
            storage.setAttributes([
                .font: ScratchpadStyle.font,
                .foregroundColor: ScratchpadStyle.text,
            ], range: fullRange)

            for range in regexRanges(#""(?:\\.|[^"\\])*""#, in: text) {
                storage.addAttribute(.foregroundColor, value: ScratchpadStyle.stringColor, range: range)
            }

            for name in functionNames {
                highlight(wordPattern: #"\b\#(name)\b"#, color: ScratchpadStyle.functionColor, font: UIFont.monospacedSystemFont(ofSize: 16, weight: .bold), in: storage, text: text)
            }

            for name in symbolNames {
                highlight(wordPattern: #"\b\#(name)\b"#, color: ScratchpadStyle.symbolColor, font: ScratchpadStyle.font, in: storage, text: text)
            }

            for unit in unitNames {
                highlight(wordPattern: #"\b\#(unit)\b"#, color: ScratchpadStyle.unitColor, font: UIFont.monospacedSystemFont(ofSize: 16, weight: .bold), in: storage, text: text)
            }

            for range in regexRanges(#"\bline\d+\b"#, in: text) {
                storage.addAttributes([
                    .foregroundColor: ScratchpadStyle.userSymbolColor,
                    .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .bold),
                ], range: range)
            }

            for variableName in assignedVariableNames(in: text) {
                for range in regexRanges(#"\b\#(variableName)\b"#, in: text) {
                    storage.addAttributes([
                        .foregroundColor: ScratchpadStyle.userSymbolColor,
                        .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .bold),
                    ], range: range)
                }
            }

            for range in regexRanges(#"\b(?:ans|pi|e)\b"#, in: text) {
                storage.addAttribute(.foregroundColor, value: ScratchpadStyle.symbolColor, range: range)
            }

            for range in regexRanges(#"(?<=\d)[pnumkMG]\b"#, in: text) {
                storage.addAttribute(.foregroundColor, value: ScratchpadStyle.symbolColor, range: range)
            }

            for range in regexRanges(#"\b0[xX][0-9A-Fa-f]+\b|\b0[bB][01]+\b"#, in: text) {
                storage.addAttribute(.foregroundColor, value: ScratchpadStyle.symbolColor, range: range)
            }

            for range in regexRanges(#"\bxor\b|\*\*|<<|>>|[+\-*/%=&|^]"#, in: text) {
                storage.addAttribute(.foregroundColor, value: ScratchpadStyle.operatorColor, range: range)
            }

            for range in regexRanges(#"#.*"#, in: text) {
                storage.addAttributes([
                    .foregroundColor: ScratchpadStyle.commentColor,
                    .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular),
                    .obliqueness: 0.18,
                ], range: range)
            }
            storage.endEditing()
        }

        private func highlight(
            wordPattern pattern: String,
            color: UIColor,
            font: UIFont,
            in storage: NSTextStorage,
            text: String
        ) {
            for range in regexRanges(pattern, in: text) {
                storage.addAttributes([
                    .foregroundColor: color,
                    .font: font,
                ], range: range)
            }
        }

        private func regexRanges(_ pattern: String, in text: String) -> [NSRange] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return []
            }
            return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).map(\.range)
        }

        private func assignedVariableNames(in text: String) -> [String] {
            guard let regex = try? NSRegularExpression(pattern: #"^\s*([A-Za-z_]\w*)\s*="#, options: [.anchorsMatchLines]) else {
                return []
            }
            let nsText = text as NSString
            return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
                guard match.numberOfRanges > 1 else {
                    return nil
                }
                return nsText.substring(with: match.range(at: 1))
            }
        }

        private func keepCaretVisible(in textView: UITextView) {
            guard let selectedRange = textView.selectedTextRange else {
                return
            }
            guard let container else {
                return
            }

            let caretLocation = min(textView.selectedRange.location, textView.textStorage.length)
            textView.layoutIfNeeded()

            let caretRect = textView.caretRect(for: selectedRange.end)
            var verticalOffset = textView.contentOffset.y
            var horizontalOffset = container.editorScrollView.contentOffset.x
            let horizontalPadding: CGFloat = 12
            let visibleLeft = horizontalOffset + horizontalPadding
            let visibleRight = horizontalOffset + container.editorScrollView.bounds.width - horizontalPadding

            let caretX = approximateCaretX(in: textView, caretLocation: caretLocation)
            if caretX > visibleRight {
                horizontalOffset = caretX - container.editorScrollView.bounds.width + horizontalPadding
            } else if caretX < visibleLeft {
                horizontalOffset = max(0, caretX - horizontalPadding)
            }

            let verticalPadding: CGFloat = 8
            let visibleTop = verticalOffset + verticalPadding
            let visibleBottom = verticalOffset + textView.bounds.height - verticalPadding

            if caretRect.maxY > visibleBottom {
                verticalOffset = caretRect.maxY - textView.bounds.height + verticalPadding
            } else if caretRect.minY < visibleTop {
                verticalOffset = max(0, caretRect.minY - verticalPadding)
            }

            let maxHorizontalOffset = max(0, container.editorScrollView.contentSize.width - container.editorScrollView.bounds.width)
            let clampedHorizontalOffset = min(max(horizontalOffset, 0), maxHorizontalOffset)
            if abs(container.editorScrollView.contentOffset.x - clampedHorizontalOffset) > 0.5 {
                container.editorScrollView.setContentOffset(
                    CGPoint(x: clampedHorizontalOffset, y: container.editorScrollView.contentOffset.y),
                    animated: false
                )
                container.textView.layoutManager.ensureLayout(for: container.textView.textContainer)
                container.textView.setNeedsDisplay()
            }

            let clampedYOffset = clampedVerticalOffset(verticalOffset, in: textView)
            if abs(textView.contentOffset.y - clampedYOffset) > 0.5 {
                textView.setContentOffset(CGPoint(x: 0, y: clampedYOffset), animated: false)
            }
        }

        private func approximateCaretX(in textView: UITextView, caretLocation: Int) -> CGFloat {
            if let textView = textView as? NonWrappingTextView {
                return textView.caretXPosition()
            }
            let length = textView.textStorage.length
            guard length > 0 else {
                return textView.textContainerInset.left
            }

            let clampedLocation = max(0, min(caretLocation, length))
            let glyphCharacterLocation = max(0, min(clampedLocation == length ? length - 1 : clampedLocation, length - 1))
            let glyphIndex = textView.layoutManager.glyphIndexForCharacter(at: glyphCharacterLocation)
            let glyphRect = textView.layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1),
                in: textView.textContainer
            )

            let isAtLineEnd = clampedLocation == length || clampedLocation > glyphCharacterLocation
            let glyphX = isAtLineEnd ? glyphRect.maxX : glyphRect.minX
            return glyphX + textView.textContainerInset.left + textView.textContainer.lineFragmentPadding
        }

        private func moveCaret(in textView: UITextView, delta: Int) {
            let length = (textView.text as NSString?)?.length ?? 0
            let current = textView.selectedRange.location
            let target = max(0, min(length, current + delta))
            textView.selectedRange = NSRange(location: target, length: 0)
            keepCaretVisible(in: textView)
            updateEditorAccessibilityDebugState(for: textView)
        }

        private func updateEditorAccessibilityDebugState(for textView: UITextView) {
            guard isUITesting else { return }
            let horizontalOffset = container?.editorScrollView.contentOffset.x ?? 0
            let horizontalBounds = container?.editorScrollView.bounds.width ?? textView.bounds.width
            let contentWidth = container?.editorScrollView.contentSize.width ?? textView.contentSize.width
            let caretX = approximateCaretX(in: textView, caretLocation: textView.selectedRange.location)
            let longestLineWidth = (textView as? NonWrappingTextView)?.longestLineWidth() ?? 0
            textView.accessibilityValue = String(
                format: "offsetX=%.1f;offsetY=%.1f;contentWidth=%.1f;boundsWidth=%.1f;caretX=%.1f;lineWidth=%.1f",
                horizontalOffset,
                textView.contentOffset.y,
                contentWidth,
                horizontalBounds,
                caretX,
                longestLineWidth
            )
        }

        private func handleSmartNewline(in container: EditorContainerView) {
            let textView = container.textView
            let nsText = (textView.text ?? "") as NSString
            let selectedRange = textView.selectedRange
            guard selectedRange.length == 0 else {
                insertToken("\n", into: container)
                return
            }

            let location = min(selectedRange.location, nsText.length)
            var lineStart = 0
            var contentsEnd = 0
            nsText.getLineStart(&lineStart, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))

            let suffixRange = NSRange(location: location, length: max(0, contentsEnd - location))
            let suffix = nsText.substring(with: suffixRange)
            let insertionLocation = suffix == ")" ? min(location + 1, nsText.length) : location
            let updatedText =
                nsText.substring(to: insertionLocation) +
                "\n" +
                nsText.substring(from: insertionLocation)

            textView.text = updatedText
            textView.selectedRange = NSRange(location: insertionLocation + 1, length: 0)
            applyText(updatedText, to: textView)
            updateLineNumbers(in: container, text: updatedText)
            text = updatedText
            refreshInlineHint(in: container)
        }

        private func clearCurrentLine(in container: EditorContainerView) {
            let textView = container.textView
            let nsText = (textView.text ?? "") as NSString
            let location = min(textView.selectedRange.location, nsText.length)

            var lineStart = 0
            var lineEnd = 0
            nsText.getLineStart(&lineStart, end: &lineEnd, contentsEnd: nil, for: NSRange(location: location, length: 0))

            let updatedText = nsText.replacingCharacters(in: NSRange(location: lineStart, length: max(0, lineEnd - lineStart)), with: "")
            textView.text = updatedText
            textView.selectedRange = NSRange(location: min(lineStart, (updatedText as NSString).length), length: 0)
            applyText(updatedText, to: textView)
            updateLineNumbers(in: container, text: updatedText)
            text = updatedText
            refreshInlineHint(in: container)
        }

        private func clearScratchpad(in container: EditorContainerView) {
            let textView = container.textView
            textView.text = ""
            textView.selectedRange = NSRange(location: 0, length: 0)
            applyText("", to: textView)
            updateLineNumbers(in: container, text: "")
            text = ""
            refreshInlineHint(in: container)
        }
    }
}

final class ResultsContainerView: UIView {
    let textView = NonWrappingTextView()
    let tapOverlay = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        clipsToBounds = true

        textView.translatesAutoresizingMaskIntoConstraints = false
        tapOverlay.translatesAutoresizingMaskIntoConstraints = false
        tapOverlay.backgroundColor = .clear

        addSubview(textView)
        addSubview(tapOverlay)

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),

            tapOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            tapOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            tapOverlay.topAnchor.constraint(equalTo: topAnchor),
            tapOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

struct ResultsTextView: UIViewRepresentable {
    let results: [LineResult]
    let text: String
    @Binding var scrollOffset: CGFloat
    let scrollBridge: ScrollSyncBridge
    let onInsertLineReference: (Int) -> Void

    func makeUIView(context: Context) -> ResultsContainerView {
        let container = ResultsContainerView()
        let textView = container.textView
        textView.font = ScratchpadStyle.font
        textView.backgroundColor = .clear
        textView.textColor = ScratchpadStyle.secondaryText
        textView.accessibilityIdentifier = "results.view"
        textView.clipsToBounds = true
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = true
        textView.isUserInteractionEnabled = false
        textView.alwaysBounceVertical = false
        textView.alwaysBounceHorizontal = false
        textView.bounces = false
        textView.delegate = context.coordinator
        textView.textContainerInset = ScratchpadStyle.insets
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byClipping
        textView.textContainer.widthTracksTextView = true
        textView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: ScratchpadStyle.extraBottomScrollInset, right: 0)
        textView.showsHorizontalScrollIndicator = false
        textView.showsVerticalScrollIndicator = false
        textView.contentInsetAdjustmentBehavior = .never
        textView.text = text
        scrollBridge.registerResults(textView: textView)

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(ResultsCoordinator.handleTap(_:)))
        container.tapOverlay.addGestureRecognizer(tapGesture)
        return container
    }

        func updateUIView(_ uiView: ResultsContainerView, context: Context) {
            context.coordinator.results = results
            context.coordinator.container = uiView
            scrollBridge.registerResults(textView: uiView.textView)
            if uiView.textView.text != text {
                uiView.textView.text = text
            }
            uiView.textView.layoutIfNeeded()

            let targetOffset = max(0, scrollOffset)
            if abs(uiView.textView.contentOffset.y - targetOffset) > 0.5 {
                uiView.textView.setContentOffset(CGPoint(x: uiView.textView.contentOffset.x, y: targetOffset), animated: false)
            }
        }

    func makeCoordinator() -> ResultsCoordinator {
        ResultsCoordinator(results: results, scrollOffset: $scrollOffset, scrollBridge: scrollBridge, onInsertLineReference: onInsertLineReference)
    }

    final class ResultsCoordinator: NSObject, UITextViewDelegate {
        var results: [LineResult]
        @Binding private var scrollOffset: CGFloat
        private weak var scrollBridge: ScrollSyncBridge?
        weak var container: ResultsContainerView?
        private let onInsertLineReference: (Int) -> Void

        init(results: [LineResult], scrollOffset: Binding<CGFloat>, scrollBridge: ScrollSyncBridge, onInsertLineReference: @escaping (Int) -> Void) {
            self.results = results
            _scrollOffset = scrollOffset
            self.scrollBridge = scrollBridge
            self.onInsertLineReference = onInsertLineReference
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let container else {
                return
            }

            let point = gesture.location(in: container.tapOverlay)
            let textPoint = container.tapOverlay.convert(point, to: container.textView)
            guard let lineNumber = lineNumber(at: textPoint, in: container.textView) else {
                return
            }

            guard let result = results.first(where: { $0.lineNumber == lineNumber }),
                  result.error == nil,
                  !result.display.isEmpty
            else {
                return
            }

            onInsertLineReference(lineNumber)
        }

        private func lineNumber(at point: CGPoint, in textView: UITextView) -> Int? {
            let containerPoint = CGPoint(
                x: point.x - textView.textContainerInset.left,
                y: point.y - textView.textContainerInset.top
            )

            guard containerPoint.x >= 0, containerPoint.y >= 0 else {
                return nil
            }

            let layoutManager = textView.layoutManager
            let textContainer = textView.textContainer
            let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)

            guard glyphIndex < layoutManager.numberOfGlyphs else {
                return nil
            }

            var lineRange = NSRange(location: 0, length: 0)
            let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
            guard lineRect.contains(containerPoint) else {
                return nil
            }

            let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let text = textView.text ?? ""
            let nsText = text as NSString
            let prefixLength = min(characterIndex, nsText.length)
            let prefix = nsText.substring(to: prefixLength)
            return prefix.reduce(into: 1) { count, character in
                if character == "\n" {
                    count += 1
                }
            }
        }
    }
}

final class EditorContainerView: UIView {
    let gutterView = UITextView()
    let editorScrollView = UIScrollView()
    let textView = NonWrappingTextView()
    let completionLabel = UILabel()
    let gutterWidthConstraint: NSLayoutConstraint
    let textViewWidthConstraint: NSLayoutConstraint
    private let divider = UIView()
    private var isUpdatingEditorWidth = false

    override init(frame: CGRect) {
        gutterWidthConstraint = gutterView.widthAnchor.constraint(equalToConstant: 44)
        textViewWidthConstraint = textView.widthAnchor.constraint(equalToConstant: 320)
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        gutterWidthConstraint = gutterView.widthAnchor.constraint(equalToConstant: 44)
        textViewWidthConstraint = textView.widthAnchor.constraint(equalToConstant: 320)
        super.init(coder: coder)
        configure()
    }

    func updateEditorWidth(_ width: CGFloat) {
        guard !isUpdatingEditorWidth else { return }
        isUpdatingEditorWidth = true
        defer { isUpdatingEditorWidth = false }

        let targetWidth = max(editorScrollView.bounds.width, ceil(width))
        if abs(textViewWidthConstraint.constant - targetWidth) > 0.5 {
            textViewWidthConstraint.constant = targetWidth
            setNeedsLayout()
        }
        let targetContentSize = CGSize(width: targetWidth, height: editorScrollView.bounds.height)
        if abs(editorScrollView.contentSize.width - targetContentSize.width) > 0.5 || abs(editorScrollView.contentSize.height - targetContentSize.height) > 0.5 {
            editorScrollView.contentSize = targetContentSize
        }
        textView.layoutManager.ensureLayout(for: textView.textContainer)
        textView.setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let horizontalInsets = textView.textContainerInset.left + textView.textContainerInset.right + (textView.textContainer.lineFragmentPadding * 2)
        let desiredWidth = max(
            editorScrollView.bounds.width,
            ceil(max(textView.longestLineWidth(), textView.caretXPosition()) + horizontalInsets + 48)
        )
        updateEditorWidth(desiredWidth)
    }

    private func configure() {
        backgroundColor = ScratchpadStyle.background
        layer.cornerRadius = 10
        clipsToBounds = true

        gutterView.translatesAutoresizingMaskIntoConstraints = false
        gutterView.font = ScratchpadStyle.numberFont
        gutterView.backgroundColor = ScratchpadStyle.gutterBackground
        gutterView.textColor = ScratchpadStyle.accent
        gutterView.accessibilityIdentifier = "scratchpad.gutter"
        gutterView.clipsToBounds = true
        gutterView.isEditable = false
        gutterView.isSelectable = false
        gutterView.isScrollEnabled = true
        gutterView.isUserInteractionEnabled = false
        gutterView.textAlignment = .right
        gutterView.textContainerInset = ScratchpadStyle.gutterInsets
        gutterView.textContainer.lineFragmentPadding = 0
        gutterView.textContainer.lineBreakMode = .byClipping
        gutterView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: ScratchpadStyle.extraBottomScrollInset, right: 0)
        gutterView.contentInsetAdjustmentBehavior = .never

        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = ScratchpadStyle.divider

        editorScrollView.translatesAutoresizingMaskIntoConstraints = false
        editorScrollView.backgroundColor = ScratchpadStyle.background
        editorScrollView.showsHorizontalScrollIndicator = true
        editorScrollView.showsVerticalScrollIndicator = false
        editorScrollView.alwaysBounceHorizontal = false
        editorScrollView.alwaysBounceVertical = false
        editorScrollView.bounces = false
        editorScrollView.isScrollEnabled = false
        editorScrollView.contentInsetAdjustmentBehavior = .never
        editorScrollView.clipsToBounds = true

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = ScratchpadStyle.font
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.keyboardAppearance = .dark
        textView.backgroundColor = ScratchpadStyle.background
        textView.textColor = ScratchpadStyle.text
        textView.tintColor = ScratchpadStyle.accent
        textView.accessibilityIdentifier = "scratchpad.editor"
        textView.textContainerInset = ScratchpadStyle.insets
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byClipping
        textView.textContainer.widthTracksTextView = true
        textView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: ScratchpadStyle.extraBottomScrollInset, right: 0)
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = false
        textView.alwaysBounceHorizontal = false
        textView.bounces = false
        textView.showsHorizontalScrollIndicator = false
        textView.contentInsetAdjustmentBehavior = .never

        addSubview(gutterView)
        addSubview(divider)
        addSubview(editorScrollView)
        editorScrollView.addSubview(textView)
        textView.addSubview(completionLabel)

        completionLabel.font = ScratchpadStyle.font
        completionLabel.textColor = ScratchpadStyle.commentColor
        completionLabel.isUserInteractionEnabled = false
        completionLabel.isHidden = true

        NSLayoutConstraint.activate([
            gutterView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gutterView.topAnchor.constraint(equalTo: topAnchor),
            gutterView.bottomAnchor.constraint(equalTo: bottomAnchor),
            gutterWidthConstraint,

            divider.leadingAnchor.constraint(equalTo: gutterView.trailingAnchor),
            divider.topAnchor.constraint(equalTo: topAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            editorScrollView.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            editorScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            editorScrollView.topAnchor.constraint(equalTo: topAnchor),
            editorScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            textView.leadingAnchor.constraint(equalTo: editorScrollView.contentLayoutGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: editorScrollView.contentLayoutGuide.trailingAnchor),
            textView.topAnchor.constraint(equalTo: editorScrollView.contentLayoutGuide.topAnchor),
            textView.bottomAnchor.constraint(equalTo: editorScrollView.contentLayoutGuide.bottomAnchor),
            textView.heightAnchor.constraint(equalTo: editorScrollView.frameLayoutGuide.heightAnchor),
            textViewWidthConstraint,
        ])
    }
}
