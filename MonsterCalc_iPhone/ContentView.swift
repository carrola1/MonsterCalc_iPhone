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
    struct SavedSheet: Identifiable, Codable, Equatable {
        let id: UUID
        var text: String
        var lastEdited: Date

        init(id: UUID = UUID(), text: String, lastEdited: Date = Date()) {
            self.id = id
            self.text = text
            self.lastEdited = lastEdited
        }

        var previewLine: String {
            text
                .components(separatedBy: .newlines)
                .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "Untitled Sheet"
        }
    }

    private enum SettingKey {
        static let sigFigures = "monstercalc.sigFigures"
        static let resultFormat = "monstercalc.resultFormat"
        static let editorFontSize = "monstercalc.editorFontSize"
        static let hasSeenInitialDemo = "monstercalc.hasSeenInitialDemo"
        static let savedSheets = "monstercalc.savedSheets"
        static let currentSheetID = "monstercalc.currentSheetID"
        static let currentSheetText = "monstercalc.currentSheetText"
    }

    private static let maxSavedSheets = 10

    @Published var text: String = "" {
        didSet {
            evaluate()
            persistCurrentSheetState()
            guard !isApplyingProgrammaticText else { return }
            autosaveCurrentSheetIfNeeded()
        }
    }
    @Published private(set) var results: [LineResult] = []
    @Published private(set) var savedSheets: [SavedSheet] = []
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
    @Published var editorFontSize: Int {
        didSet {
            let clamped = max(16, min(20, editorFontSize))
            if editorFontSize != clamped {
                editorFontSize = clamped
                return
            }
            saveSettings()
        }
    }

    private var engine = ScratchpadEngine()
    private let defaults: UserDefaults
    private var currentSheetID: UUID?
    private var isApplyingProgrammaticText = false
    private let uiTestingDemoKey: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.uiTestingDemoKey = Self.uiTestingDemoKey(from: ProcessInfo.processInfo.arguments)
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
        let storedEditorFontSize = defaults.object(forKey: SettingKey.editorFontSize) as? Int ?? 18
        self.editorFontSize = max(16, min(20, storedEditorFontSize))
        self.savedSheets = Self.loadSavedSheets(from: defaults)
        self.currentSheetID = defaults.string(forKey: SettingKey.currentSheetID).flatMap(UUID.init(uuidString:))

        if let uiTestingDemoKey {
            applyProgrammaticSheetState(text: DemoSheet.text(for: uiTestingDemoKey), sheetID: nil)
        } else if let storedText = defaults.string(forKey: SettingKey.currentSheetText) {
            applyProgrammaticSheetState(text: storedText, sheetID: currentSheetID)
        } else if defaults.bool(forKey: SettingKey.hasSeenInitialDemo) {
            applyProgrammaticSheetState(text: "", sheetID: nil)
        } else {
            applyProgrammaticSheetState(text: DemoSheet.text, sheetID: nil)
            defaults.set(true, forKey: SettingKey.hasSeenInitialDemo)
        }
        evaluate()
    }

    var recentSavedSheets: [SavedSheet] {
        savedSheets.reversed()
    }

    var resultsText: String {
        results
            .map(\.display)
            .joined(separator: "\n")
    }

    func loadDemo() {
        autosaveCurrentSheetIfNeeded()
        applyProgrammaticSheetState(text: DemoSheet.text, sheetID: nil)
    }

    func clear() {
        applyProgrammaticSheetState(text: "", sheetID: currentSheetID)
    }

    func createNewSheet() {
        autosaveCurrentSheetIfNeeded()
        applyProgrammaticSheetState(text: "", sheetID: nil)
    }

    func loadSheet(_ sheet: SavedSheet) {
        autosaveCurrentSheetIfNeeded()
        applyProgrammaticSheetState(text: sheet.text, sheetID: sheet.id)
    }

    func insert(_ token: String) {
        DispatchQueue.main.async {
            self.pendingInsertion = token
        }
    }

    private func evaluate() {
        engine.config = ScratchpadEngineConfig(
            sigFigures: sigFigures,
            resultFormat: resultFormat,
            editorFontSize: editorFontSize
        )
        results = engine.evaluateDocument(text)
    }

    private func saveSettings() {
        defaults.set(sigFigures, forKey: SettingKey.sigFigures)
        defaults.set(resultFormat.rawValue, forKey: SettingKey.resultFormat)
        defaults.set(editorFontSize, forKey: SettingKey.editorFontSize)
    }

    private func applyProgrammaticSheetState(text newText: String, sheetID: UUID?) {
        isApplyingProgrammaticText = true
        currentSheetID = sheetID
        text = newText
        isApplyingProgrammaticText = false
        persistCurrentSheetState()
    }

    private func autosaveCurrentSheetIfNeeded() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let sheetID = currentSheetID ?? UUID()
        currentSheetID = sheetID

        let savedSheet = SavedSheet(id: sheetID, text: text, lastEdited: Date())
        if let existingIndex = savedSheets.firstIndex(where: { $0.id == sheetID }) {
            savedSheets.remove(at: existingIndex)
        }
        savedSheets.append(savedSheet)
        if savedSheets.count > Self.maxSavedSheets {
            savedSheets.removeFirst(savedSheets.count - Self.maxSavedSheets)
        }
        persistSavedSheets()
        persistCurrentSheetState()
    }

    private func persistSavedSheets() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(savedSheets) else { return }
        defaults.set(data, forKey: SettingKey.savedSheets)
    }

    private func persistCurrentSheetState() {
        defaults.set(text, forKey: SettingKey.currentSheetText)
        defaults.set(currentSheetID?.uuidString, forKey: SettingKey.currentSheetID)
    }

    private static func loadSavedSheets(from defaults: UserDefaults) -> [SavedSheet] {
        guard let data = defaults.data(forKey: SettingKey.savedSheets) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SavedSheet].self, from: data)) ?? []
    }

    private static func uiTestingDemoKey(from arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "--ui-testing-demo"),
              arguments.indices.contains(index + 1)
        else {
            return nil
        }
        return arguments[index + 1]
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
    @State private var showingSavedSheets = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.13, blue: 0.14),
                            Color(red: 0.04, green: 0.05, blue: 0.06),
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
            .sheet(isPresented: $showingSavedSheets) {
                NavigationStack {
                    SavedSheetsScreen(
                        sheets: model.recentSavedSheets,
                        onLoadSheet: { sheet in
                            model.loadSheet(sheet)
                            showingSavedSheets = false
                        }
                    )
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
                    .foregroundStyle(Color(red: 0.56, green: 0.67, blue: 0.14))
            }

            Spacer()

            Button {
                model.createNewSheet()
            } label: {
                Image(systemName: "plus")
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
            .accessibilityIdentifier("header.newSheet")

            Menu {
                Section("Actions") {
                    Button("Load Sheet") {
                        showingSavedSheets = true
                    }

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

                    Menu("Font Size") {
                        ForEach(16...20, id: \.self) { size in
                            Button {
                                model.editorFontSize = size
                            } label: {
                                if model.editorFontSize == size {
                                    Label("\(size)", systemImage: "checkmark")
                                } else {
                                    Text("\(size)")
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
                ScratchpadTextView(
                    text: $model.text,
                    pendingInsertion: $model.pendingInsertion,
                    scrollOffset: $synchronizedScrollOffset,
                    inputMode: $inputMode,
                    fontSize: model.editorFontSize,
                    scrollBridge: scrollBridge
                )
                .frame(width: editorWidth, height: workspaceHeight)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1, height: workspaceHeight)

                ResultsTextView(
                    results: model.results,
                    text: model.resultsText,
                    fontSize: model.editorFontSize,
                    scrollOffset: $synchronizedScrollOffset,
                    scrollBridge: scrollBridge,
                    onInsertLineReference: { lineNumber in
                        model.insert("line\(lineNumber)")
                    }
                )
                .frame(width: resultsWidth, height: workspaceHeight)
                .background(Color(red: 0.10, green: 0.105, blue: 0.112))
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
            .fill(Color(red: 0.15, green: 0.16, blue: 0.17))
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

private struct SavedSheetsScreen: View {
    @Environment(\.dismiss) private var dismiss

    let sheets: [ScratchpadViewModel.SavedSheet]
    let onLoadSheet: (ScratchpadViewModel.SavedSheet) -> Void

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        Group {
            if sheets.isEmpty {
                ContentUnavailableView(
                    "No Saved Sheets",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Nonblank sheets will appear here automatically as you work.")
                )
            } else {
                List(sheets) { sheet in
                    Button {
                        onLoadSheet(sheet)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sheet.previewLine)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(Self.timestampFormatter.string(from: sheet.lastEdited))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Load Sheet")
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
