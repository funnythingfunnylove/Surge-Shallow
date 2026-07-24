import SwiftUI
import SurgeProfileRelayCore

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    eyebrow: "Surge Shallow",
                    title: "让 Surge 更好用，一键管理多端配置与模块",
                    detail: "在一个原生 macOS App 中管理规则、代理、Profile 与模块，再通过 Surge iCloud 安全同步到 Mac、iPhone 与 iPad。"
                )

                statusHero

                HStack(spacing: 14) {
                    MetricView(
                        title: "启用规则源",
                        value: "\(model.enabledSourceCount)",
                        symbol: "link",
                        tint: SurgePalette.accent
                    )
                    MetricView(
                        title: "生成规则",
                        value: "\(model.currentRuleCount)",
                        symbol: "line.3.horizontal.decrease.circle",
                        tint: SurgePalette.accent
                    )
                    MetricView(
                        title: "目标设备",
                        value: "\(model.document.targets.filter(\.isEnabled).count)",
                        symbol: "laptopcomputer.and.iphone",
                        tint: SurgePalette.accent
                    )
                }

                targets

                if let result = model.lastResult, !result.warnings.isEmpty {
                    warnings(result.warnings)
                }

                if model.document.sources.isEmpty {
                    ContentUnavailableView {
                        Label("还没有规则源", systemImage: "link.badge.plus")
                    } description: {
                        Text("添加一个或多个规则 URL，然后由 Relay 按顺序合并并同步到 iCloud。")
                    } actions: {
                        Button("添加规则源") { model.selection = .sources }
                            .buttonStyle(.glassProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .padding(26)
            .frame(maxWidth: 1200, alignment: .leading)
        }
        .navigationTitle("总览")
    }

    private var statusHero: some View {
        RelayCard {
            HStack(spacing: 18) {
                Image(systemName: model.isRefreshing ? "arrow.trianglehead.2.clockwise.rotate.90" : "checkmark.shield")
                    .font(.system(size: 30, weight: .semibold))
                    .symbolEffect(.rotate, isActive: model.isRefreshing)
                    .foregroundStyle(model.lastResult?.outcome == .failure ? SurgePalette.danger : SurgePalette.accent)
                    .frame(width: 58, height: 58)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.statusMessage)
                        .font(.title3.weight(.semibold))
                    if model.isRefreshing {
                        ProgressView(value: model.progressFraction)
                            .frame(maxWidth: 360)
                    } else if let date = model.lastSuccessfulUpdate {
                        Text("上次生成：\(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("完成首次合并后，最新 Profile 会直接写入 Surge 的 iCloud 目录。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        Button {
                            model.beginFullProfileImport()
                        } label: {
                            Label("导入现有 Profile", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.glass)
                        .help("分析现有 Surge Profile 并迁移到结构化管理")

                        Button {
                            Task { await model.refresh(force: true) }
                        } label: {
                            Label("合并生成", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(model.isRefreshing)
                    }
                }
                .controlSize(.large)
            }
        }
    }

    private var targets: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("同步目标")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("生成后自动出现在 Surge iCloud 目录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.document.targets) { target in
                RelayCard {
                    HStack(spacing: 14) {
                        Image(systemName: target.platform.symbolName)
                            .font(.title2)
                            .foregroundStyle(target.isEnabled ? .primary : .tertiary)
                            .frame(width: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(target.platform.displayName)
                                .font(.headline)
                            Text(target.outputFileName)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if target.lastGeneratedAt != nil {
                            Text("\(target.lastRuleCount) 条")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Button("预览") { model.showPreview(for: target.platform) }
                            .disabled(target.lastGeneratedAt == nil)
                        Button {
                            model.openOutput(for: target.platform)
                        } label: {
                            Label("在 Surge 中打开", systemImage: "arrow.up.forward.app")
                        }
                        .disabled(target.lastGeneratedAt == nil)
                    }
                }
                .opacity(target.isEnabled ? 1 : 0.55)
            }
        }
    }

    private func warnings(_ warnings: [String]) -> some View {
        RelayCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("本次生成提示", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                ForEach(warnings.prefix(8), id: \.self) { warning in
                    Text("• \(warning)")
                        .font(.callout)
                        .textSelection(.enabled)
                }
                if warnings.count > 8 {
                    Text("另有 \(warnings.count - 8) 条提示")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
