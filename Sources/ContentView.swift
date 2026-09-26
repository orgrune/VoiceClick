import SwiftUI
import WebKit

struct WebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var typed = ""

    var body: some View {
        HSplitView {
            WebViewRepresentable(webView: model.webView)
                .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
            sidebar
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                TextField("Lesson URL", text: $model.urlString)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.load() }
                Button("Go") { model.load() }
                Button { model.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Reload")
            }

            Button(action: model.toggleListening) {
                Label(model.isListening ? "Stop listening" : "Start listening",
                      systemImage: model.isListening ? "mic.fill" : "mic")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(model.isListening ? .red : .green)
            .keyboardShortcut("l", modifiers: .command)

            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox("Hearing") {
                Text(model.heard.isEmpty ? "…" : model.heard)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.title3)
                    .lineLimit(3)
            }

            GroupBox("Last command") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.lastCommand.isEmpty ? "—" : "“\(model.lastCommand)”")
                        .font(.headline)
                    Text(model.lastResult.isEmpty ? " " : model.lastResult)
                        .font(.caption)
                        .foregroundStyle(model.lastOK ? Color.green : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            TextField("Type a command to test, then press Return", text: $typed)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    model.handleCommand(typed)
                    typed = ""
                }

            GroupBox("You can say") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        if model.candidates.isEmpty {
                            Text("No clickable text found yet").foregroundStyle(.secondary)
                        }
                        ForEach(Array(model.candidates.enumerated()), id: \.offset) { _, text in
                            Text(text).font(.callout).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 120)
            }

            GroupBox("Log") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(model.log.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.caption).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 80)
            }

            Text("Also: “option B”, “second one”, “next”, “scroll down”, “go back”, “stop listening”.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
    }
}
