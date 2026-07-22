import AppKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            List(selection: $model.selection) {
                Section("管理") {
                    ForEach(SidebarDestination.allCases.filter { $0 != .settings }) { destination in
                        Label(destination.title, systemImage: destination.symbol)
                            .tag(destination)
                    }
                }
                Section {
                    Label(SidebarDestination.settings.title, systemImage: SidebarDestination.settings.symbol)
                        .tag(SidebarDestination.settings)
                }
            }
            .navigationTitle("Profile Relay")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 270)
        } detail: {
            destinationView
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await model.refresh(force: true) }
                        } label: {
                            Label("更新并合并", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                        }
                        .disabled(model.isRefreshing)
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .alert(
            "Surge Shallow",
            isPresented: Binding(
                get: { model.presentedError != nil },
                set: { if !$0 { model.presentedError = nil } }
            )
        ) {
            Button("好", role: .cancel) { model.presentedError = nil }
        } message: {
            Text(model.presentedError ?? "")
        }
        .sheet(
            isPresented: Binding(
                get: { model.previewContent != nil },
                set: { if !$0 { model.dismissPreview() } }
            )
        ) {
            ProfilePreviewView(
                title: model.previewTitle,
                content: model.previewContent ?? "",
                onDismiss: model.dismissPreview
            )
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch model.selection {
        case .dashboard: DashboardView()
        case .sources: SourcesView()
        case .proxy: ProxyView()
        case .profiles: ProfilesView()
        case .history: HistoryView()
        case .settings: SettingsView()
        }
    }
}

private struct ProfilePreviewView: View {
    let title: String
    let content: String
    let onDismiss: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text("只读预览 · 实际文件已通过原子写入发布")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                Button("完成", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(18)

            Divider()

            ReadOnlyProfileTextView(content: content)
                .accessibilityIdentifier("profile-preview-text")
        }
        .frame(minWidth: 780, minHeight: 560)
    }
}

private struct ReadOnlyProfileTextView: NSViewRepresentable {
    let content: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(
            containerSize: NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        textContainer.widthTracksTextView = false
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.identifier = NSUserInterfaceItemIdentifier("profile-preview-text")
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindPanel = true
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.string = content
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != content else { return }
        textView.string = content
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }
}
