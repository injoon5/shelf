// Name: Pocket Browser
// Icon: safari
// Tint: blue
// Covers: Web

import SwiftUI
import WebKit

struct ContentView: View {
    @State private var page = WebPage()
    @State private var address = "https://www.apple.com"
    @State private var words = 0
    @State private var finding = false
    @State private var showNotes = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if page.isLoading {
                    ProgressView(value: page.estimatedProgress)
                }
                WebView(page)
                    .webViewBackForwardNavigationGestures(.enabled)
                    .webViewMagnificationGestures(.enabled)
                    .webViewLinkPreviews(.disabled)
                    .webViewTextSelection(.enabled)
                    .webViewContentBackground(.visible)
                    .webViewElementFullscreenBehavior(.enabled)
                    .findNavigator(isPresented: $finding)
            }
            .navigationTitle(page.title.isEmpty ? "Browser" : page.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Back", systemImage: "chevron.left") {
                        if let item = page.backForwardList.backList.last { page.load(item) }
                    }
                    .disabled(page.backForwardList.backList.isEmpty)
                    Button("Forward", systemImage: "chevron.right") {
                        if let item = page.backForwardList.forwardList.first { page.load(item) }
                    }
                    .disabled(page.backForwardList.forwardList.isEmpty)
                    Spacer()
                    Button("Count Words", systemImage: "textformat.size") { Task { await countWords() } }
                    Button("Find", systemImage: "magnifyingglass") { finding.toggle() }
                    Button("Reload", systemImage: "arrow.clockwise") { page.reload() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Notes", systemImage: "note.text") { showNotes = true }
                }
            }
            .safeAreaInset(edge: .top) {
                TextField("Address", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { go() }
                    .padding(.horizontal)
            }
            .overlay(alignment: .bottomTrailing) {
                if words > 0 {
                    Text("\(words) words")
                        .font(.caption)
                        .padding(8)
                        .background(.thinMaterial, in: Capsule())
                        .padding()
                }
            }
            .sheet(isPresented: $showNotes) {
                NavigationStack {
                    WebView(url: URL(string: "https://developer.apple.com/documentation/webkit"))
                        .navigationTitle("WebKit")
                }
            }
            .onAppear {
                page.load(html: """
                <html><head><title>Start</title>
                <meta name="viewport" content="width=device-width">
                <style>body { font: -apple-system-body; padding: 16px; } h1 { font: -apple-system-headline; }</style>
                </head><body><h1>Pocket Browser</h1><p>Type an address above and press return.</p></body></html>
                """)
            }
        }
    }

    func go() {
        var text = address.trimmingCharacters(in: .whitespaces)
        if !text.hasPrefix("http") { text = "https://" + text }
        guard let url = URL(string: text) else { return }
        var request = URLRequest(url: url)
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        page.load(request)
    }

    func countWords() async {
        do {
            let result = try await page.callJavaScript("return document.body.innerText.split(/\\s+/).filter(Boolean).length")
            words = result as? Int ?? 0
        } catch {
            words = 0
        }
    }
}
