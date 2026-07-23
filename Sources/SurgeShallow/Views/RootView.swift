import AppKit
import SurgeModuleManagement
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            RelaySidebar(selection: $model.selection)
        } detail: {
            destinationView
                .toolbar {
                    if model.selection != .modules {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                Task { await model.refresh(force: true) }
                            } label: {
                                Label("更新并合并", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                            }
                            .disabled(model.isRefreshing)
                            .buttonStyle(.glassProminent)
                        }
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .background(SurgeBackground())
        .fileImporter(
            isPresented: $model.isChoosingProfileImport,
            allowedContentTypes: [.plainText, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    model.prepareFullProfileImport(from: url)
                }
            case .failure(let error):
                model.presentedError = "无法选择 Profile：\(error.localizedDescription)"
            }
        }
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
        .sheet(item: $model.pendingProfileImport) { draft in
            ProfileImportReviewView(draft: draft)
                .environment(model)
        }
        .overlay {
            if model.isParsingProfileImport {
                GlassProgressOverlay(
                    title: "正在分析 Profile",
                    detail: "识别通用配置、平台差异、Proxy、策略组与规则…"
                )
            }
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch model.selection {
        case .dashboard: DashboardView()
        case .sources: SourcesView()
        case .proxy: ProxyView()
        case .profiles: ProfilesView()
        case .modules:
            ModuleManagementView(
                controller: model.moduleManagement,
                onOpenSettings: { model.selection = .settings }
            )
        case .history: HistoryView()
        case .settings: SettingsView()
        }
    }
}

private struct RelaySidebar: View {
    @Binding var selection: SidebarDestination

    private let managementDestinations: [SidebarDestination] = [
        .dashboard, .sources, .proxy, .profiles, .modules, .history
    ]

    var body: some View {
        List(selection: $selection) {
            Section("管理") {
                ForEach(managementDestinations) { destination in
                    Label {
                        Text(destination.title)
                    } icon: {
                        Image(systemName: destination.symbol)
                    }
                    .tag(destination)
                }
            }
            Section {
                Label("设置", systemImage: SidebarDestination.settings.symbol)
                    .tag(SidebarDestination.settings)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarStatusPanel()
                .padding(.horizontal, SurgeSpacing.sm)
                .padding(.bottom, SurgeSpacing.sm)
        }
        .navigationTitle("Surge Shallow")
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 270)
    }
}

private struct SidebarStatusPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: SurgeSpacing.sm) {
            HStack(spacing: SurgeSpacing.sm) {
                statusIndicator

                Text(model.sidebarUpdateStatus.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if model.isRefreshing {
                    Text(model.progressFraction, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if model.isRefreshing {
                ProgressView(value: model.progressFraction)
                    .progressViewStyle(.linear)
            }

            Divider()

            SidebarStatusRow(label: "最后合并", value: lastMergeText)
            SidebarStatusRow(label: "规则总数", value: "\(model.currentRuleCount) 条")
            SidebarStatusRow(
                label: "规则源",
                value: "\(model.enabledSourceCount) / \(model.document.sources.count) 启用"
            )
            SidebarStatusRow(
                label: "模块",
                value: "\(model.moduleManagement.enabledModuleCount) / \(model.moduleManagement.moduleCount) 启用"
            )
        }
        .padding(SurgeSpacing.md)
        .background(
            SurgePalette.surface.opacity(0.88),
            in: RoundedRectangle(cornerRadius: SurgeRadius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: SurgeRadius.card, style: .continuous)
                .strokeBorder(.primary.opacity(0.08))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("软件状态")
        .accessibilityValue(accessibilitySummary)
        .accessibilityIdentifier("sidebar-status-panel")
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if model.isRefreshing {
            ProgressView()
                .controlSize(.small)
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: statusSymbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(statusColor)
                .frame(width: 18, height: 18)
        }
    }

    private var statusColor: Color {
        switch model.sidebarUpdateStatus {
        case .refreshing: SurgePalette.accent
        case .current: SurgePalette.success
        case .warning: SurgePalette.warning
        case .failed: SurgePalette.danger
        case .pending, .empty: .secondary
        }
    }

    private var statusSymbol: String {
        switch model.sidebarUpdateStatus {
        case .refreshing: "arrow.trianglehead.2.clockwise.rotate.90"
        case .current: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.circle.fill"
        case .pending: "clock.fill"
        case .empty: "link.badge.plus"
        }
    }

    private var lastMergeText: String {
        guard let date = model.lastSuccessfulUpdate else {
            return "尚未合并"
        }
        if Calendar.current.isDateInToday(date) {
            return "今天 \(date.formatted(date: .omitted, time: .shortened))"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "昨天 \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(.dateTime.month().day().hour().minute())
    }

    private var accessibilitySummary: String {
        "\(model.sidebarUpdateStatus.title)，最后合并 \(lastMergeText)，规则总数 \(model.currentRuleCount) 条，规则源 \(model.enabledSourceCount) / \(model.document.sources.count) 启用，模块 \(model.moduleManagement.enabledModuleCount) / \(model.moduleManagement.moduleCount) 启用"
    }
}

private struct SidebarStatusRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SurgeSpacing.sm) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(SurgePalette.accent)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .font(.caption)
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
