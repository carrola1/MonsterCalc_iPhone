import SwiftUI
import UIKit
import WebKit

private extension UIResponder {
    private static weak var currentResponder: UIResponder?

    static func activeResponder() -> UIResponder? {
        currentResponder = nil
        UIApplication.shared.sendAction(#selector(captureFirstResponder(_:)), to: nil, from: nil, for: nil)
        return currentResponder
    }

    @objc func captureFirstResponder(_ sender: Any) {
        UIResponder.currentResponder = self
    }
}

@MainActor
final class ScratchpadViewModel: ObservableObject {
    private enum SettingKey {
        static let sigFigures = "monstercalc.sigFigures"
        static let resultFormat = "monstercalc.resultFormat"
        static let hasSeenInitialDemo = "monstercalc.hasSeenInitialDemo"
    }

    @Published var text: String = "" {
        didSet {
            evaluate()
        }
    }
    @Published private(set) var results: [LineResult] = []
    @Published var pendingInsertion: String?
    @Published var sigFigures: Int {
        didSet {
            let clamped = max(1, min(12, sigFigures))
            if sigFigures != clamped {
                sigFigures = clamped
                return
            }
            saveSettings()
            evaluate()
        }
    }
    @Published var resultFormat: ResultFormat {
        didSet {
            saveSettings()
            evaluate()
        }
    }

    private var engine = ScratchpadEngine()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset"),
           let bundleIdentifier = Bundle.main.bundleIdentifier
        {
            defaults.removePersistentDomain(forName: bundleIdentifier)
        }
        let storedSigFigures = defaults.object(forKey: SettingKey.sigFigures) as? Int ?? 5
        self.sigFigures = max(1, min(12, storedSigFigures))
        self.resultFormat = ResultFormat(
            rawValue: defaults.string(forKey: SettingKey.resultFormat) ?? ""
        ) ?? .si

        if defaults.bool(forKey: SettingKey.hasSeenInitialDemo) {
            self.text = ""
        } else {
            self.text = DemoSheet.text
            defaults.set(true, forKey: SettingKey.hasSeenInitialDemo)
        }
        evaluate()
    }

    var resultsText: String {
        results
            .map { result in
                if let error = result.error, !error.isEmpty {
                    return error
                }
                return result.display
            }
            .joined(separator: "\n")
    }

    func loadDemo() {
        text = DemoSheet.text
    }

    func clear() {
        text = ""
    }

    func insert(_ token: String) {
        DispatchQueue.main.async {
            self.pendingInsertion = token
        }
    }

    private func evaluate() {
        engine.config = ScratchpadEngineConfig(
            sigFigures: sigFigures,
            resultFormat: resultFormat
        )
        results = engine.evaluateDocument(text)
    }

    private func saveSettings() {
        defaults.set(sigFigures, forKey: SettingKey.sigFigures)
        defaults.set(resultFormat.rawValue, forKey: SettingKey.resultFormat)
    }
}

private enum HeaderSheet: String, Identifiable {
    case about
    case userGuide
    case releaseNotes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .about:
            return "About"
        case .userGuide:
            return "User Guide"
        case .releaseNotes:
            return "Release Notes"
        }
    }
}

struct ContentView: View {
    @StateObject private var model = ScratchpadViewModel()
    @StateObject private var scrollBridge = ScrollSyncBridge()
    @State private var synchronizedScrollOffset: CGFloat = 0
    @State private var inputMode: EditorInputMode = .calc
    @State private var activeSheet: HeaderSheet?

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.17, blue: 0.18),
                            Color(red: 0.09, green: 0.10, blue: 0.11),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()

                    VStack(spacing: 10) {
                        headerCard(compact: geometry.size.width > geometry.size.height)
                        workspaceCard(in: geometry.size)
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $activeSheet) { sheet in
                NavigationStack {
                    switch sheet {
                    case .about:
                        AboutSheet()
                    case .userGuide:
                        HTMLDocumentScreen(
                            title: sheet.title,
                            resourceName: "UserGuide",
                            fallbackText: "User guide is not available in this build."
                        )
                    case .releaseNotes:
                        HTMLDocumentScreen(
                            title: sheet.title,
                            resourceName: "ReleaseNotes",
                            fallbackText: "Release notes are not available in this build."
                        )
                    }
                }
            }
        }
    }

    private func headerCard(compact compactHeader: Bool) -> some View {
        HStack(spacing: 10) {
            if let uiImage = UIImage(named: "MonsterApp") {
                Image(uiImage: uiImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: compactHeader ? 36 : 42, height: compactHeader ? 36 : 42)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("MONSTER CALC")
                    .font(.system(size: compactHeader ? 19 : 22, weight: .bold, design: .serif))
                    .foregroundStyle(Color(red: 0.66, green: 0.77, blue: 0.25))
            }

            Spacer()

            Menu {
                Section("Actions") {
                    Button("Load Demo") {
                        model.loadDemo()
                    }

                    Button("Undo") {
                        UIResponder.activeResponder()?.undoManager?.undo()
                    }

                    Button("Clear Scratchpad", role: .destructive) {
                        model.clear()
                    }
                }

                Section("Settings") {
                    Menu("Significant Figures") {
                        ForEach(1...12, id: \.self) { value in
                            Button {
                                model.sigFigures = value
                            } label: {
                                if model.sigFigures == value {
                                    Label("\(value)", systemImage: "checkmark")
                                } else {
                                    Text("\(value)")
                                }
                            }
                        }
                    }

                    Menu("Results Format") {
                        ForEach(ResultFormat.allCases) { format in
                            Button {
                                model.resultFormat = format
                            } label: {
                                if model.resultFormat == format {
                                    Label(format.title, systemImage: "checkmark")
                                } else {
                                    Text(format.title)
                                }
                            }
                        }
                    }
                }

                Section("Help") {
                    Button("About") {
                        activeSheet = .about
                    }

                    Button("User Guide") {
                        activeSheet = .userGuide
                    }

                    Button("Release Notes") {
                        activeSheet = .releaseNotes
                    }

                    Divider()

                    Button("Version 1.0.0") { }
                        .disabled(true)
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
            .accessibilityIdentifier("header.menu")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, compactHeader ? 8 : 10)
        .background(cardBackground)
    }

    private func workspaceCard(in size: CGSize) -> some View {
        let isLandscape = size.width > size.height
        let totalWidth = max(0, size.width - 12)
        let workspaceHeight = max(isLandscape ? 92 : 220, size.height - (isLandscape ? 78 : 90))
        let editorFraction = isLandscape ? 0.67 : 0.64
        let widthShift: CGFloat = 10
        let preferredEditorWidth = floor((totalWidth - 1) * editorFraction)
        let resultsWidth = max(110, totalWidth - preferredEditorWidth - 1 - widthShift)
        let editorWidth = max(0, totalWidth - resultsWidth - 1)

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                paneLabel("Scratchpad")
                    .accessibilityIdentifier("scratchpad.title")
                    .frame(width: editorWidth, alignment: .leading)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)

                paneLabel("Live Results")
                    .accessibilityIdentifier("results.title")
                    .frame(width: resultsWidth, alignment: .leading)
            }
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.02))

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            HStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    ScratchpadTextView(
                        text: $model.text,
                        pendingInsertion: $model.pendingInsertion,
                        scrollOffset: $synchronizedScrollOffset,
                        inputMode: $inputMode,
                        scrollBridge: scrollBridge
                    )

                    if model.text.isEmpty {
                        Text("One expr per line\n\nx = 2*pi\nvdiv(5, 10k, 10k)\nline2 + ans")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.top, 12)
                            .padding(.leading, 53)
                    }
                }
                .frame(width: editorWidth, height: workspaceHeight)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1, height: workspaceHeight)

                ResultsTextView(
                    results: model.results,
                    text: model.resultsText,
                    scrollOffset: $synchronizedScrollOffset,
                    scrollBridge: scrollBridge,
                    onInsertLineReference: { lineNumber in
                        model.insert("line\(lineNumber)")
                    }
                )
                .frame(width: resultsWidth, height: workspaceHeight)
                .background(Color(red: 0.14, green: 0.145, blue: 0.153))
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func paneLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 10)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(red: 0.19, green: 0.20, blue: 0.21))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

private struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let uiImage = UIImage(named: "MonsterApp") {
                    HStack(spacing: 14) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 58, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("MONSTER CALC")
                                .font(.system(size: 24, weight: .bold, design: .serif))
                            Text("Version 1.0.0")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text("A fast scratchpad calculator for math, programming, and electronics.")
                Text("Created by Andrew Carroll.")
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

private struct HTMLDocumentScreen: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let resourceName: String
    let fallbackText: String

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: resourceName, withExtension: "html") {
                HTMLDocumentView(url: url)
            } else {
                ScrollView {
                    Text(fallbackText)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

private struct HTMLDocumentView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }
}

#Preview {
    ContentView()
}
