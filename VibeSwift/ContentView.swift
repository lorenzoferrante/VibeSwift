//
//  ContentView.swift
//  VibeSwift
//
//  Created by Lorenzo Ferrante on 10/02/26.
//

import SwiftUI
import CodeEditorView
import LanguageSupport

private enum EditorMode: String, CaseIterable {
    case run = "Run"
    case live = "Live Renderer"
    case build = "Build App"
}

struct ContentView: View {
    @State private var text: String = """
let name = "Vibe"
let upper = name.uppercased()
print("Hello " + upper)
return upper
"""
    @State private var position: CodeEditor.Position       = CodeEditor.Position()
    @State private var messages: Set<TextLocated<Message>> = Set()
    @State private var selectedMode: EditorMode = .run
    @StateObject private var viewModel = InterpreterDemoViewModel()

    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Picker("Mode", selection: $selectedMode) {
                    ForEach(EditorMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 340)

                if selectedMode == .run {
                    Button {
                        messages = []
                        viewModel.run(source: text)
                    } label: {
                        Label("Run", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isRunning)
                } else if selectedMode == .live {
                    Button {
                        messages = []
                        viewModel.runLive(source: text)
                    } label: {
                        Label("Launch Live", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isLiveRunning)

                    Button {
                        messages = []
                        viewModel.recomputeLive(source: text)
                    } label: {
                        Label("Recompute", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        messages = []
                        viewModel.build(source: text)
                    } label: {
                        Label("Build App", systemImage: "hammer.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isBuilding)
                }

                Button {
                    text = sampleSource(for: selectedMode)
                    position = CodeEditor.Position()
                } label: {
                    Label("Load Sample", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)

                Toggle("SwiftUI Bridge", isOn: $viewModel.allowSwiftUIBridge)
                    .toggleStyle(.switch)

                Spacer()
            }

            if selectedMode == .build {
                GroupBox("Build Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("App Name", text: $viewModel.buildAppName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                        TextField("Bundle Identifier", text: $viewModel.buildBundleIdentifier)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
            }

            CodeEditor(text: $text, position: $position, messages: $messages, language: .swift())
                .frame(minHeight: 320)
                .environment(
                    \.codeEditorTheme,
                    colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight
                )

            if selectedMode == .run {
                GroupBox("Interpreter Result") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Returned Value: \(viewModel.resultText.isEmpty ? "nil" : viewModel.resultText)")
                            .font(.system(.body, design: .monospaced))

                        if !viewModel.outputLines.isEmpty {
                            Divider()
                            Text("Console Output")
                                .font(.headline)
                            ForEach(Array(viewModel.outputLines.enumerated()), id: \.offset) { idx, line in
                                Text("[\(idx)] \(line)")
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if !viewModel.diagnosticLines.isEmpty {
                            Divider()
                            Text("Diagnostics")
                                .font(.headline)
                            ForEach(Array(viewModel.diagnosticLines.enumerated()), id: \.offset) { idx, line in
                                Text("[\(idx)] \(line)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if let renderedView = viewModel.renderedView {
                            Divider()
                            Text("Rendered SwiftUI View")
                                .font(.headline)
                            renderedView
                                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if selectedMode == .live {
                GroupBox("Live Renderer Result") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.liveStatusText.isEmpty ? "Live renderer is idle." : viewModel.liveStatusText)
                            .font(.system(.body, design: .monospaced))

                        if let renderedView = viewModel.renderedView {
                            Divider()
                            Text("Rendered View")
                                .font(.headline)
                            renderedView
                                .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                        }

                        if !viewModel.outputLines.isEmpty {
                            Divider()
                            Text("Console Output")
                                .font(.headline)
                            ForEach(Array(viewModel.outputLines.enumerated()), id: \.offset) { idx, line in
                                Text("[\(idx)] \(line)")
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if !viewModel.diagnosticLines.isEmpty {
                            Divider()
                            Text("Diagnostics")
                                .font(.headline)
                            ForEach(Array(viewModel.diagnosticLines.enumerated()), id: \.offset) { idx, line in
                                Text("[\(idx)] \(line)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if !viewModel.liveStateText.isEmpty {
                            Divider()
                            Text("State (JSON)")
                                .font(.headline)
                            ScrollView {
                                Text(viewModel.liveStateText)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(minHeight: 80, maxHeight: 160)
                        }

                        if !viewModel.liveIRText.isEmpty {
                            Divider()
                            Text("ViewTree IR (JSON)")
                                .font(.headline)
                            ScrollView {
                                Text(viewModel.liveIRText)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(minHeight: 80, maxHeight: 180)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                GroupBox("Build Result") {
                    VStack(alignment: .leading, spacing: 8) {
                        if !viewModel.buildSummary.isEmpty {
                            Text(viewModel.buildSummary)
                                .font(.system(.body, design: .monospaced))
                        }

                        if let packageURL = viewModel.buildPackageURL {
                            ShareLink(item: packageURL) {
                                Label("Export .vibeapp", systemImage: "square.and.arrow.up")
                            }
                        }

                        if !viewModel.buildWarnings.isEmpty {
                            Divider()
                            Text("Warnings")
                                .font(.headline)
                            ForEach(Array(viewModel.buildWarnings.enumerated()), id: \.offset) { idx, line in
                                Text("[\(idx)] \(line)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.orange)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if !viewModel.buildDiagnostics.isEmpty {
                            Divider()
                            Text("Diagnostics")
                                .font(.headline)
                            ForEach(Array(viewModel.buildDiagnostics.enumerated()), id: \.offset) { idx, line in
                                Text("[\(idx)] \(line)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if !viewModel.buildManifestText.isEmpty {
                            Divider()
                            Text("manifest.json")
                                .font(.headline)
                            ScrollView {
                                Text(viewModel.buildManifestText)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(minHeight: 80, maxHeight: 160)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
    }

    private func sampleSource(for mode: EditorMode) -> String {
        switch mode {
        case .run:
            return """
let name = "Vibe"
let upper = name.uppercased()
print("Hello " + upper)
return upper
"""
        case .live:
            return """
func body() {
    let state = State()
    let title = state.get("title")
    let nameBinding = state.bind("name")
    let enabledBinding = state.bind("enabled")

    var root = VStack(
        12,
        Text(title),
        TextField("Name", nameBinding),
        Toggle("Enabled", enabledBinding),
        Button("Save", "saveTapped")
    )
    root = padding(root, 12)
    root = font(root, "body")
    root = background(root, "gray")
    return root
}

func saveTapped() {
    let state = State()
    let currentName = state.get("name")
    state.set("title", "Hello " + currentName)
}
"""
        case .build:
            return """
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Hello from Build App mode")
            Image(systemName: "sparkles")
                .foregroundStyle(.blue)
        }
        .padding()
    }
}
"""
        }
    }
}

#Preview {
    ContentView()
}
