import SwiftUI
import SurgeProfileRelayCore

struct ProfileImportReviewView: View {
    private enum Scope: String, CaseIterable, Identifiable {
        case both
        case macOS
        case iOS

        var id: String { rawValue }
        var title: String {
            switch self {
            case .both: "macOS 与 iOS"
            case .macOS: "仅 macOS"
            case .iOS: "仅 iOS"
            }
        }
        var platforms: Set<RelayPlatform> {
            switch self {
            case .both: Set(RelayPlatform.allCases)
            case .macOS: [.macOS]
            case .iOS: [.iOS]
            }
        }
    }

    @Environment(AppModel.self) private var model
    let draft: ProfileImportDraft
    @State private var scope: Scope = .both

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: SurgeSpacing.xl) {
                    scopeSection
                    summaryGrid
                    replacementNotice
                    if !draft.warnings.isEmpty { warningsSection }
                }
                .padding(SurgeSpacing.xl)
            }
            Divider()
            footer
        }
        .frame(minWidth: 720, idealWidth: 780, minHeight: 620)
        .background(SurgeBackground())
        .tint(SurgePalette.accent)
    }

    private var header: some View {
        HStack(spacing: SurgeSpacing.lg) {
            Image(systemName: "arrow.trianglehead.merge")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(SurgePalette.accent)
                .frame(width: 52, height: 52)
                .glassEffect()
            VStack(alignment: .leading, spacing: 4) {
                Text("准备迁移 Profile")
                    .font(.title2.weight(.semibold))
                Text(draft.fileName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("尚未更改配置")
                .font(.caption.weight(.medium))
                .foregroundStyle(SurgePalette.success)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(SurgePalette.success.opacity(0.11), in: Capsule())
        }
        .padding(SurgeSpacing.xl)
    }

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: SurgeSpacing.md) {
            Text("应用到")
                .font(.headline)
            Picker("应用平台", selection: $scope) {
                ForEach(Scope.allCases) { item in Text(item.title).tag(item) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("已识别的平台专属 General 项只会写入对应端；未知非通用段会保留到所选平台的差异配置。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var summaryGrid: some View {
        VStack(alignment: .leading, spacing: SurgeSpacing.md) {
            Text("识别结果")
                .font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ImportMetric(value: "\(draft.summary.generalOptionCount)", label: "General 项", symbol: "slider.horizontal.3")
                ImportMetric(value: "\(draft.summary.proxyCount)", label: "Proxy", symbol: "server.rack")
                ImportMetric(value: "\(draft.summary.proxyGroupCount)", label: "策略组", symbol: "point.3.connected.trianglepath.dotted")
                ImportMetric(value: "\(draft.summary.ruleCount)", label: "内联规则", symbol: "line.3.horizontal.decrease")
                ImportMetric(value: "\(draft.summary.rulesetCount)", label: "远端 Ruleset", symbol: "link.badge.plus")
                ImportMetric(value: "\(draft.summary.includeDirectiveCount)", label: "Include", symbol: "doc.badge.ellipsis")
                ImportMetric(value: draft.summary.finalPolicy ?? "未发现", label: "FINAL 策略", symbol: "flag.checkered")
                ImportMetric(value: "\(draft.summary.advancedSectionNames.count)", label: "其他配置段", symbol: "square.stack.3d.up")
            }
            if !draft.summary.advancedSectionNames.isEmpty {
                Text(draft.summary.advancedSectionNames.map { "[\($0)]" }.joined(separator: "  "))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var replacementNotice: some View {
        VStack(alignment: .leading, spacing: SurgeSpacing.sm) {
            Label("应用后会替换的内容", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
            Text("公共 General、Proxy、Proxy Group、高级公共段、现有规则源，以及所选平台的差异项与 FINAL 策略。每条 HTTP(S) RULE-SET 会拆为独立远端规则源，其他规则按原有顺序保留为内联片段。刷新周期、输出目录、历史记录和未选平台保持不变。")
                .font(.callout)
            Label("保存时会生成 relay.json.bak；不会立即生成或覆盖任何 Profile。", systemImage: "externaldrive.badge.checkmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(SurgeSpacing.lg)
        .background(SurgePalette.warning.opacity(0.085), in: RoundedRectangle(cornerRadius: SurgeRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: SurgeRadius.control)
                .strokeBorder(SurgePalette.warning.opacity(0.20))
        }
    }

    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: SurgeSpacing.sm) {
            Label("需要确认", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(SurgePalette.warning)
            ForEach(draft.warnings, id: \.self) { warning in
                Text("• \(warning)")
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("取消") { model.cancelFullProfileImport() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Text("应用后请先在 Profiles 中检查，再执行更新并合并。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("应用迁移") {
                model.applyFullProfileImport(platforms: scope.platforms)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(SurgeSpacing.lg)
    }
}

private struct ImportMetric: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        HStack(spacing: SurgeSpacing.md) {
            Image(systemName: symbol)
                .foregroundStyle(SurgePalette.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .lineLimit(1)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(SurgeSpacing.md)
        .background(SurgePalette.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: SurgeRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: SurgeRadius.control)
                .strokeBorder(.primary.opacity(0.065))
        }
        .accessibilityElement(children: .combine)
    }
}
